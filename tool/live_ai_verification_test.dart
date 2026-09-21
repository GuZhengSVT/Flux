// T026 真实验证探针（唯一一次授权调用；不进 flutter test 的默认集合）。
//
// 复现方式（Key 只通过环境变量进内存，不落盘、不回显）：
//   FLUX_TEST_DSK=<key> flutter test tool/live_ai_verification_test.dart --reporter expanded
//
// 为什么走 **ModelManager 的测试路径**（而不是直接 new 适配器）：
//   T026 的适配器只在「被模型管理与凭据端口驱动」时才真正可用。直接构造适配器能证明
//   协议解析对，但证明不了「用户配好模型点一下测试」这条链路是通的——而后者才是本任务
//   的交付目标。因此这里装配真实的 ModelManager + OpenAiProviderFactory。
//
// 预算纪律（架构 4.5、手册 T003 的超支记录）：
//   本文件**只发一次**生成调用；max_tokens 由 ModelManager.minimalTestMaxTokens 夹到 64
//   （在授权的 200 以内）。失败不自动重试——重试由人来决定，而不是测试偷偷再花一次钱。
//
// 脱敏检查是断言的一部分：调用记录里只有耗时/计数/结构化错误码，不含 Key。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/model_manager.dart';
import 'package:flux/features/ai/domain/ai_credential_store.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/ai_model_store.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/network/ai_provider_factory.dart';
import 'package:flux/infrastructure/platform/credential_store.dart';

/// 被测端点（T003 已人工核实连通：OpenAI Chat Completions 兼容）。
const String kBaseUrl = 'https://api.deepseek.com';

/// 被测模型（T003 实测过的模型之一）。
const String kModelId = 'deepseek-chat';

void main() {
  test('真实 DeepSeek Chat Completions 一次最小生成（需 FLUX_TEST_DSK）', () async {
    final String? apiKey = Platform.environment['FLUX_TEST_DSK'];
    if (apiKey == null || apiKey.isEmpty) {
      fail('FLUX_TEST_DSK 未设置：拒绝发起一次未认证的调用');
    }

    // 诊断日志停在 error：本探针要断言「记录里没有 Key」，因此不需要 info 级别噪音。
    final DiagnosticLog log = DiagnosticLog(level: DiagnosticLevel.info);
    final AppDatabase db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    addTearDown(db.close);

    final InMemoryCredentialStore keychain = InMemoryCredentialStore();
    final AiCredentialStore credentials = _Adapter(keychain);

    final ModelManager manager = ModelManager(
      store: DriftAiModelStore(db),
      credentials: credentials,
      diagnostics: _LogSink(log),
      providerFactory: const OpenAiProviderFactory(),
      clock: const SystemClock(),
    );

    final Result<AiModel> saved = await manager.saveModel(
      const AiModel(
        alias: 'deepseek-live',
        protocol: AiProtocol.openAiChatCompletions,
        baseUrl: kBaseUrl,
        modelId: kModelId,
      ),
    );
    expect(saved.isOk, isTrue, reason: saved.errorOrNull?.message);
    expect(
      (await manager.saveCredential('deepseek-live', apiKey)).isOk,
      isTrue,
    );

    // ---- 唯一一次真实调用 ------------------------------------------------
    final Result<ModelTestReport> result = await manager.runMinimalGeneration(
      saved.valueOrNull!,
      confirmation: CostConfirmation(acknowledgedAtUtc: DateTime.now().toUtc()),
    );

    // ---- 脱敏检查（无论成功失败都要跑） ----------------------------------
    final String exported = log.export();
    expect(exported, isNot(contains(apiKey)), reason: '诊断导出里出现了 Key');
    expect(exported, isNot(contains('Bearer')), reason: '诊断里不应出现任何认证头形态');

    if (result.isErr) {
      final AppError error = result.errorOrNull!;
      // 失败也如实记录，但不重试。
      // ignore: avoid_print
      print(
        'LIVE_RESULT=FAIL kind=${error.kind} '
        'retryable=${error.isRetryable} message=${error.message}',
      );
      expect(
        error.toLogString(),
        isNot(contains(apiKey)),
        reason: '错误对象里出现了 Key',
      );
      fail('真实调用失败（不重试）：${error.kind} — ${error.message}');
    }

    final ModelTestReport report = result.valueOrNull!;
    final AiUsage? usage = report.usage;
    // ignore: avoid_print
    print(
      'LIVE_RESULT=OK endpoint=$kBaseUrl/chat/completions model=$kModelId '
      'elapsedMs=${report.elapsed.inMilliseconds} '
      'inTokens=${usage == null ? 'unknown' : usage.inputTokens} '
      'outTokens=${usage == null ? 'unknown' : usage.outputTokens} '
      'totalTokens=${usage == null ? 'unknown' : usage.effectiveTotal} '
      'chars=${report.textLength} finish=${report.finishReason}',
    );

    expect(report.finishReason, isNotNull, reason: '必须拿到结束原因');
    expect(report.textLength, greaterThan(0), reason: '模型应至少回一个字（不是空流）');
    // 结构断言，不断言具体文案：服务商可以改措辞，但 token 计数必须存在且自洽。
    if (usage != null) {
      expect(usage.inputTokens, greaterThan(0));
      expect(usage.outputTokens, greaterThanOrEqualTo(0));
      if (!usage.totalIsEstimated) {
        expect(usage.totalTokens, usage.inputTokens + usage.outputTokens);
      }
    }
  });
}

/// 把底层凭据存储接到 features 侧端口（与组合根同一条路径）。
final class _Adapter implements AiCredentialStore {
  _Adapter(this._inner);

  final CredentialStore _inner;

  CredentialKey _key(String alias) =>
      CredentialKey(category: 'ai-provider', identifier: alias);

  @override
  Future<Result<String>> read(String alias) => _inner.read(_key(alias));

  @override
  Future<Result<void>> write(String alias, String apiKey) =>
      _inner.write(_key(alias), apiKey);

  @override
  Future<Result<void>> delete(String alias) => _inner.delete(_key(alias));

  @override
  Future<Result<bool>> exists(String alias) => _inner.exists(_key(alias));

  @override
  Future<bool> isAvailable() => _inner.isAvailable();
}

/// 诊断端口适配（与生产 DiagnosticLogSink 同一语义；探针内联避免依赖 app 层）。
final class _LogSink implements DiagnosticSink {
  const _LogSink(this._log);

  final DiagnosticLog _log;

  @override
  void record(DiagnosticSeverity severity, String message, {String? tag}) {}

  @override
  void error(String message, {String? tag}) => _log.error(message, tag: tag);

  @override
  void warning(String message, {String? tag}) =>
      _log.warning(message, tag: tag);

  @override
  void info(String message, {String? tag}) => _log.info(message, tag: tag);
}
