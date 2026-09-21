// T025：模型管理用例（CRUD、排序/启停、删除引用检查、凭据脱敏、最小生成测试）。
//
// 这一组用例最要紧的不是「方法能跑通」，而是几条业务边界：
//   1) **Key 永不进日志/诊断**（用真实 DiagnosticLog 断言导出文本里没有 Key）；
//   2) **删除不悬空**（有引用时先报引用，force 才删；读不到引用时一律不放行）；
//   3) **测试按钮先要费用确认**，且被拒绝的调用不产生任何请求（不产生费用）；
//   4) **停用不等于删除**、**读取失败不等于没有引用**。
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/model_manager.dart';
import 'package:flux/features/ai/domain/ai_credential_store.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_model_references.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/model_capability.dart';
import 'package:flux/infrastructure/local/ai_model_store.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';

import 'ai_test_support.dart';
import 'fake_ai_provider.dart';

void main() {
  late AppDatabase db;
  late DriftAiModelStore store;
  late DiagnosticLog log;
  late _FakeCredentials credentials;
  late ModelManager manager;
  late FakeAiProviderFactory factory;
  final FakeClock clock = FakeClock();

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    store = DriftAiModelStore(db);
    // info 级别：本用例要断言「确实记了凭据事件」，因此不能停在 error 级别。
    log = DiagnosticLog(level: DiagnosticLevel.info);
    credentials = _FakeCredentials();
    factory = FakeAiProviderFactory();
    manager = ModelManager(
      store: store,
      credentials: credentials,
      diagnostics: _LogSink(log),
      providerFactory: factory,
      clock: clock,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('模型 CRUD', () {
    test('新增后可读回，字段原样保留', () async {
      final Result<AiModel> saved = await manager.saveModel(testModel());
      expect(saved.isOk, isTrue, reason: saved.errorOrNull?.message);
      expect(saved.valueOrNull!.id, isNotNull, reason: '插入后应带回 id');

      final List<AiModel> all = (await manager.loadModels()).unwrap();
      expect(all, hasLength(1));
      expect(all.single.alias, 'deepseek');
      expect(all.single.protocol, AiProtocol.openAiChatCompletions);
      expect(all.single.baseUrl, 'https://api.deepseek.com');
      expect(all.single.modelId, 'deepseek-chat');
      expect(all.single.enabled, isTrue);
    });

    test('别名/模型 ID/Base URL 的前后空白被规范化', () async {
      final Result<AiModel> saved = await manager.saveModel(
        testModel(
          alias: '  deepseek  ',
          baseUrl: ' https://api.deepseek.com ',
          modelId: ' deepseek-chat ',
        ),
      );
      expect(saved.valueOrNull!.alias, 'deepseek');
      expect(saved.valueOrNull!.baseUrl, 'https://api.deepseek.com');
      expect(saved.valueOrNull!.modelId, 'deepseek-chat');
    });

    test('能力五项独立落库并原样读回（SET-033）', () async {
      final Result<AiModel> saved = await manager.saveModel(
        testModel(
          capability: const ModelCapability(
            vision: true,
            streaming: true,
            contextWindow: 65536,
            maxOutput: 4096,
          ),
        ),
      );
      final AiModel reloaded = (await manager.loadModels()).unwrap().single;
      expect(reloaded.id, saved.valueOrNull!.id);
      expect(reloaded.capability.text, isTrue);
      expect(reloaded.capability.vision, isTrue);
      expect(reloaded.capability.streaming, isTrue);
      expect(
        reloaded.capability.tools,
        isFalse,
        reason: '视觉与工具是独立能力：声明一个不得连带打开另一个',
      );
      expect(reloaded.capability.contextWindow, 65536);
      expect(reloaded.capability.maxOutput, 4096);
    });

    test('未声明的上限落库为 null（按保守预算使用时才算 8192/2048）', () async {
      await manager.saveModel(testModel());
      final AiModel reloaded = (await manager.loadModels()).unwrap().single;
      expect(reloaded.capability.contextWindow, isNull);
      expect(reloaded.capability.maxOutput, isNull);
      expect(reloaded.capability.contextIsConservative, isTrue);
      expect(reloaded.capability.effectiveOutputBudget, 2048);
    });

    test('别名重复被拒绝为 SET-030.alias，且**不覆盖**已有记录', () async {
      await manager.saveModel(testModel());
      final Result<AiModel> duplicate = await manager.saveModel(
        testModel(modelId: 'deepseek-reasoner'),
      );
      expect(duplicate.isErr, isTrue);
      expect(
        (duplicate.errorOrNull! as ValidationError).field,
        'SET-030.alias',
      );
      final List<AiModel> all = (await manager.loadModels()).unwrap();
      expect(all, hasLength(1));
      expect(
        all.single.modelId,
        'deepseek-chat',
        reason: '覆盖会把另一份凭据引用悄悄接到新配置上',
      );
    });

    test('更新保留 id 并写回新值', () async {
      final AiModel saved = (await manager.saveModel(testModel())).unwrap();
      final Result<AiModel> updated = await manager.saveModel(
        saved.copyWith(modelId: 'deepseek-reasoner', enabled: false),
      );
      expect(updated.isOk, isTrue, reason: updated.errorOrNull?.message);
      final AiModel reloaded = (await manager.loadModels()).unwrap().single;
      expect(reloaded.id, saved.id);
      expect(reloaded.modelId, 'deepseek-reasoner');
      expect(reloaded.enabled, isFalse);
    });

    test('删除后列表为空', () async {
      final AiModel saved = (await manager.saveModel(testModel())).unwrap();
      expect((await manager.deleteModel(saved)).isOk, isTrue);
      expect((await manager.loadModels()).unwrap(), isEmpty);
    });

    test('删除未落库的记录被拒绝（不静默成功）', () async {
      final Result<void> deleted = await manager.deleteModel(testModel());
      expect(deleted.isErr, isTrue);
      expect(deleted.errorOrNull, isA<ValidationError>());
    });

    test('非法 Base URL 不落库', () async {
      final Result<AiModel> saved = await manager.saveModel(
        testModel(baseUrl: 'file:///tmp/x'),
      );
      expect(saved.isErr, isTrue);
      expect((await manager.loadModels()).unwrap(), isEmpty);
    });

    test('保存失败也会在诊断里留下类别（便于排查而不含敏感值）', () async {
      await manager.saveModel(testModel());
      await manager.saveModel(testModel(modelId: 'other'));
      final String exported = log.export();
      expect(exported, contains('ai.model'));
      expect(exported, contains('kind=validation'));
    });
  });

  group('启用/停用与故障转移顺序（SET-032/035）', () {
    test('停用的模型不出现在启用列表，但仍在全部列表里', () async {
      await manager.saveModel(testModel(alias: 'a'));
      final AiModel b = (await manager.saveModel(testModel(alias: 'b')))
          .unwrap();
      expect((await manager.setEnabled(b, false)).isOk, isTrue);

      expect(
        (await manager.loadEnabledModels()).unwrap().map(
          (AiModel m) => m.alias,
        ),
        <String>['a'],
      );
      expect(
        (await manager.loadModels()).unwrap(),
        hasLength(2),
        reason: '停用不是删除：记录必须还在，否则重新启用时得重填一遍',
      );
    });

    test('排序按传入顺序落库，读取时按该顺序返回', () async {
      final AiModel a = (await manager.saveModel(testModel(alias: 'a')))
          .unwrap();
      final AiModel b = (await manager.saveModel(testModel(alias: 'b')))
          .unwrap();
      final AiModel c = (await manager.saveModel(testModel(alias: 'c')))
          .unwrap();

      final Result<void> reordered = await manager.reorder(<int>[
        c.id!,
        a.id!,
        b.id!,
      ]);
      expect(reordered.isOk, isTrue, reason: reordered.errorOrNull?.message);
      expect(
        (await manager.loadModels()).unwrap().map((AiModel m) => m.alias),
        <String>['c', 'a', 'b'],
      );
    });

    test('排序列表含重复 id 被拒绝（否则会留下两个相同序号）', () async {
      final AiModel a = (await manager.saveModel(testModel())).unwrap();
      final Result<void> result = await manager.reorder(<int>[a.id!, a.id!]);
      expect(result.isErr, isTrue);
      expect(
        (result.errorOrNull! as ValidationError).field,
        'SET-032.sortOrder',
      );
    });

    test('任务默认模型唯一：设新的会清掉旧的', () async {
      final AiModel a = (await manager.saveModel(testModel(alias: 'a')))
          .unwrap();
      final AiModel b = (await manager.saveModel(testModel(alias: 'b')))
          .unwrap();
      await manager.setDefaultForTasks(a.id!, isDefault: true);
      await manager.setDefaultForTasks(b.id!, isDefault: true);

      final List<AiModel> defaults = (await manager.loadModels())
          .unwrap()
          .where((AiModel m) => m.isDefaultForTasks)
          .toList();
      expect(defaults, hasLength(1), reason: '两个默认模型会让「取默认」变得不确定');
      expect(defaults.single.alias, 'b');
    });

    test('取消默认后没有任何记录被标为默认', () async {
      final AiModel a = (await manager.saveModel(testModel())).unwrap();
      await manager.setDefaultForTasks(a.id!, isDefault: true);
      await manager.setDefaultForTasks(a.id!, isDefault: false);
      expect(
        (await manager.loadModels()).unwrap().where(
          (AiModel m) => m.isDefaultForTasks,
        ),
        isEmpty,
      );
    });

    test('对不存在的 id 设默认会被拒绝，且不会留下「谁都不是默认」的库', () async {
      final AiModel a = (await manager.saveModel(testModel())).unwrap();
      await manager.setDefaultForTasks(a.id!, isDefault: true);
      final Result<void> result = await manager.setDefaultForTasks(
        99999,
        isDefault: true,
      );
      expect(result.isErr, isTrue);
      expect(
        (await manager.loadModels())
            .unwrap()
            .where((AiModel m) => m.isDefaultForTasks)
            .map((AiModel m) => m.alias),
        <String>['deepseek'],
        reason: '失败必须整体回滚，不能只是把原来的默认清掉',
      );
    });
  });

  group('删除引用不悬空（SET-034/035）', () {
    test('无引用时可直接删除', () async {
      final AiModel a = (await manager.saveModel(testModel(alias: 'a')))
          .unwrap();
      final ModelManager withSettings = _withSettings(
        manager,
        FakeSettingsReader(),
      );
      final Result<void> deleted = await withSettings.deleteModel(a);
      expect(deleted.isOk, isTrue, reason: deleted.errorOrNull?.message);
    });

    test('被任务默认引用时返回 ModelInUseError，force 后才删', () async {
      final AiModel a = (await manager.saveModel(testModel(alias: 'a')))
          .unwrap();
      await manager.setDefaultForTasks(a.id!, isDefault: true);
      final AiModel reloaded = (await manager.loadModels()).unwrap().single;

      final Result<void> blocked = await manager.deleteModel(reloaded);
      expect(blocked.isErr, isTrue);
      final ModelInUseError error = blocked.errorOrNull! as ModelInUseError;
      expect(error.alias, 'a');
      expect(error.referenceDescriptions, contains('defaultForTasks'));
      expect(
        (await manager.loadModels()).unwrap(),
        hasLength(1),
        reason: '未确认时不得删除',
      );

      expect((await manager.deleteModel(reloaded, force: true)).isOk, isTrue);
      expect((await manager.loadModels()).unwrap(), isEmpty);
    });

    test('被 SET-034 视觉模型引用时被拦住并指出编号', () async {
      final AiModel a = (await manager.saveModel(testModel(alias: 'a')))
          .unwrap();
      final ModelManager withSettings = _withSettings(
        manager,
        FakeSettingsReader(
          values: <String, Object?>{'SET-034': 'a', 'SET-035': null},
        ),
      );
      final Result<List<ModelReference>> references = await withSettings
          .describeReferencesTo(a);
      expect(references.isOk, isTrue, reason: references.errorOrNull?.message);
      expect(
        references.valueOrNull!.map((ModelReference r) => r.settingId),
        contains('SET-034'),
      );
      expect((await withSettings.deleteModel(a)).isErr, isTrue);
    });

    test('被 SET-035 允许列表引用时被拦住', () async {
      final AiModel a = (await manager.saveModel(testModel(alias: 'a')))
          .unwrap();
      final ModelManager withSettings = _withSettings(
        manager,
        FakeSettingsReader(
          values: <String, Object?>{
            'SET-034': null,
            'SET-035': <String, Object?>{
              'enabled': true,
              'allowedModels': <String>['a', 'other'],
            },
          },
        ),
      );
      final Result<void> blocked = await withSettings.deleteModel(a);
      expect(blocked.isErr, isTrue);
      expect(
        (blocked.errorOrNull! as ModelInUseError).referenceDescriptions,
        contains('failoverAllowList(SET-035)'),
      );
    });

    test('设置读取失败时不放行删除（「读不到」不等于「没有引用」）', () async {
      final AiModel a = (await manager.saveModel(testModel(alias: 'a')))
          .unwrap();
      final ModelManager broken = _withSettings(
        manager,
        FailingSettingsReader(),
      );
      final Result<void> deleted = await broken.deleteModel(a);
      expect(deleted.isErr, isTrue);
      expect(
        (await manager.loadModels()).unwrap(),
        hasLength(1),
        reason: '读不到引用时必须保守地不删除',
      );
    });

    test('未接线设置端口时只检查本机默认标记，并在诊断里说明未检查 SET-034/035', () async {
      final AiModel a = (await manager.saveModel(testModel(alias: 'a')))
          .unwrap();
      final Result<List<ModelReference>> references = await manager
          .describeReferencesTo(a);
      expect(references.isOk, isTrue);
      expect(references.valueOrNull!, isEmpty, reason: '本机默认标记未设置，因此当前没有已知引用');
      expect(
        log.export(),
        contains('SET-034/035 引用未检查'),
        reason: '不能把「没检查」伪装成「检查过且为空」',
      );
    });

    test('引用判定的纯函数口径：别名不匹配不构成引用', () {
      expect(
        referencesToAlias(
          alias: 'b',
          isDefaultForTasks: false,
          visionModelAlias: 'a',
          failoverAllowList: <String>['c'],
        ),
        isEmpty,
      );
      expect(
        referencesToAlias(
          alias: 'a',
          isDefaultForTasks: true,
          visionModelAlias: '',
          failoverAllowList: const <String>[],
        ).map((ModelReference r) => r.kind),
        <ModelReferenceKind>[ModelReferenceKind.defaultForTasks],
      );
    });
  });

  group('凭据（SET-031）：写入/删除/状态，且永不进日志', () {
    test('写入后状态为已配置，删除后回到未配置', () async {
      expect((await manager.hasCredential('deepseek')).unwrap(), isFalse);
      expect(
        (await manager.saveCredential('deepseek', 'sk-test-abc')).isOk,
        isTrue,
      );
      expect((await manager.hasCredential('deepseek')).unwrap(), isTrue);
      expect((await manager.deleteCredential('deepseek')).isOk, isTrue);
      expect((await manager.hasCredential('deepseek')).unwrap(), isFalse);
    });

    test('空 Key 被拒绝，不写进安全存储', () async {
      expect((await manager.saveCredential('a', '   ')).isErr, isTrue);
      expect((await manager.hasCredential('a')).unwrap(), isFalse);
      expect(credentials.entries, isEmpty);
    });

    test('删除不存在的 Key 是幂等的', () async {
      expect((await manager.deleteCredential('never')).isOk, isTrue);
    });

    test('**诊断日志里不出现 Key**（含导出文本）', () async {
      const String key = 'sk-1234567890abcdefghijklmnop';
      await manager.saveCredential('deepseek', key);
      await manager.deleteCredential('deepseek');
      await manager.saveCredential('deepseek', key);

      final String exported = log.export();
      expect(exported, contains('ai.credential'), reason: '应当确实记录了凭据事件');
      expect(exported, isNot(contains(key)));
      expect(exported, isNot(contains('sk-1234567890')));
      expect(exported, isNot(contains('1234567890abcdefghijklmnop')));
    });

    test('安全存储不可用时如实报告（界面据此提示会话使用或失败）', () async {
      expect(await manager.isCredentialStoreAvailable(), isTrue);
      final ModelManager unavailable = ModelManager(
        store: store,
        credentials: _FakeCredentials(available: false),
        diagnostics: _LogSink(log),
        clock: clock,
      );
      expect(await unavailable.isCredentialStoreAvailable(), isFalse);
    });

    test('Key 原样交给适配器（适配器不做 trim 之类的改写）', () async {
      const String key = ' sk-with-space ';
      final AiModel saved = (await manager.saveModel(testModel())).unwrap();
      await manager.saveCredential('deepseek', key);
      await manager.runMinimalGeneration(saved, confirmation: _confirmation);
      expect(factory.lastApiKey, key);
    });
  });

  group('最小生成测试（SET-042 动作，会产生费用）', () {
    test('成功路径返回耗时、usage 与字符数，输出上限压到最小测试预算', () async {
      final AiModel saved = (await manager.saveModel(
        testModel(
          capability: const ModelCapability(
            contextWindow: 32768,
            maxOutput: 4096,
          ),
        ),
      )).unwrap();
      await manager.saveCredential('deepseek', 'sk-test');
      final Result<ModelTestReport> result = await manager.runMinimalGeneration(
        saved,
        confirmation: _confirmation,
      );

      expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
      final ModelTestReport report = result.valueOrNull!;
      expect(report.usage!.inputTokens, 11);
      expect(report.usage!.outputTokens, 5);
      expect(report.textLength, '连接正常'.length);
      expect(report.finishReason, 'stop');
      expect(
        factory.lastRequest!.maxTokens,
        ModelManager.minimalTestMaxTokens,
        reason: '连通性测试不该按用户配置的 4096 去花',
      );
      expect(factory.lastRequest!.modelId, 'deepseek-chat');
      expect(
        factory.lastRequest!.messages.first.content,
        contains('连接测试'),
        reason: '测试请求带一个最小的系统指令',
      );
    });

    test('用户预算比最小测试预算更小时取用户值（不抬高）', () async {
      final AiModel saved = (await manager.saveModel(
        testModel(capability: const ModelCapability(maxOutput: 16)),
      )).unwrap();
      await manager.saveCredential('deepseek', 'sk-test');
      await manager.runMinimalGeneration(saved, confirmation: _confirmation);
      expect(factory.lastRequest!.maxTokens, 16);
    });

    test('模型未启用时直接拒绝，不发请求（不产生费用）', () async {
      final AiModel saved = (await manager.saveModel(testModel(enabled: false)))
          .unwrap();
      await manager.saveCredential('deepseek', 'sk-test');
      final Result<ModelTestReport> result = await manager.runMinimalGeneration(
        saved,
        confirmation: _confirmation,
      );
      expect(result.isErr, isTrue);
      expect(
        (result.errorOrNull! as ModelConfigurationError).reason,
        'disabled',
      );
      expect(factory.createdCount, 0);
    });

    test('协议没有适配器时明确拒绝（T025 期间的 Anthropic）', () async {
      final AiModel saved = (await manager.saveModel(
        testModel(protocol: AiProtocol.anthropicMessages),
      )).unwrap();
      await manager.saveCredential('deepseek', 'sk-test');
      final Result<ModelTestReport> result = await manager.runMinimalGeneration(
        saved,
        confirmation: _confirmation,
      );
      expect(result.isErr, isTrue);
      expect(
        (result.errorOrNull! as ModelConfigurationError).reason,
        'adapterMissing',
      );
      expect(factory.createdCount, 0, reason: '未实现的协议不得发起真实调用');
    });

    test('工厂未接线时同样报 adapterMissing 而不是崩溃', () async {
      final AiModel saved = (await manager.saveModel(testModel())).unwrap();
      await manager.saveCredential('deepseek', 'sk-test');
      final ModelManager noFactory = ModelManager(
        store: store,
        credentials: credentials,
        diagnostics: _LogSink(log),
        clock: clock,
      );
      final Result<ModelTestReport> result = await noFactory
          .runMinimalGeneration(saved, confirmation: _confirmation);
      expect(result.isErr, isTrue);
      expect(
        (result.errorOrNull! as ModelConfigurationError).reason,
        'adapterMissing',
      );
    });

    test('缺 Key 时拒绝，不发请求', () async {
      final AiModel saved = (await manager.saveModel(testModel())).unwrap();
      final Result<ModelTestReport> result = await manager.runMinimalGeneration(
        saved,
        confirmation: _confirmation,
      );
      expect(result.isErr, isTrue);
      expect(
        (result.errorOrNull! as ModelConfigurationError).reason,
        'credentialMissing',
      );
      expect(factory.createdCount, 0);
    });

    test('适配器抛出的类型化错误原样返回（不吞成成功）', () async {
      factory.failure = AuthError(provider: 'deepseek', statusCode: 401);
      final AiModel saved = (await manager.saveModel(testModel())).unwrap();
      await manager.saveCredential('deepseek', 'sk-test');
      final Result<ModelTestReport> result = await manager.runMinimalGeneration(
        saved,
        confirmation: _confirmation,
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<AuthError>());
      expect(log.export(), contains('kind=authentication'));
    });

    test('适配器抛出非类型化异常被翻译成 NetworkError（不透出原始异常文本）', () async {
      factory.untypedFailure = StateError('internal adapter bug');
      final AiModel saved = (await manager.saveModel(testModel())).unwrap();
      await manager.saveCredential('deepseek', 'sk-test');
      final Result<ModelTestReport> result = await manager.runMinimalGeneration(
        saved,
        confirmation: _confirmation,
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<NetworkError>());
      expect(
        result.errorOrNull!.message,
        isNot(contains('internal adapter bug')),
        reason: '原始异常文本可能带请求/响应片段，不得进入错误消息',
      );
    });

    test('成功路径的诊断只记结构事实：不含 Key，也不含模型输出正文', () async {
      final AiModel saved = (await manager.saveModel(testModel())).unwrap();
      await manager.saveCredential('deepseek', 'sk-abcdefghijklmnopqrst');
      await manager.runMinimalGeneration(saved, confirmation: _confirmation);

      final String exported = log.export();
      expect(exported, contains('elapsedMs='));
      expect(exported, contains('inTokens='));
      expect(exported, contains('outTokens='));
      expect(exported, isNot(contains('sk-abcdefghijklmnopqrst')));
      expect(exported, isNot(contains('连接正常')), reason: '测试生成的正文没有展示价值，不该进入日志');
    });

    test('协议未提供 usage 时报告里是 null（不编造 token 数）', () async {
      factory.usage = null;
      final AiModel saved = (await manager.saveModel(testModel())).unwrap();
      await manager.saveCredential('deepseek', 'sk-test');
      final ModelTestReport report = (await manager.runMinimalGeneration(
        saved,
        confirmation: _confirmation,
      )).valueOrNull!;
      expect(report.usage, isNull);
      expect(
        log.export(),
        contains('inTokens=unknown'),
        reason: '未知就写 unknown，不用 0 假装是统计结果',
      );
    });
  });
}

/// 固定的费用确认（时间使用固定值，便于断言可复现）。
final CostConfirmation _confirmation = CostConfirmation(
  acknowledgedAtUtc: DateTime.utc(2026, 9, 22),
);

/// 把 [ModelManager] 换上一个设置端口（其它依赖沿用当前用例的替身）。
ModelManager _withSettings(ModelManager base, SettingsReader settings) =>
    ModelManager(
      store: base.store,
      credentials: base.credentials,
      diagnostics: base.diagnostics,
      providerFactory: base.providerFactory,
      clock: base.clock,
      settings: settings,
    );

/// 内存凭据存储（测试不触碰真实 Keychain）。
final class _FakeCredentials implements AiCredentialStore {
  _FakeCredentials({this.available = true});

  final bool available;
  final Map<String, String> entries = <String, String>{};

  @override
  Future<Result<String>> read(String alias) async {
    final String? value = entries[alias];
    if (value == null) {
      return Err<String>(
        StorageError(
          operation: 'credentialStore.read',
          detail: 'no entry for $alias',
          isMissing: true,
        ),
      );
    }
    return Ok<String>(value);
  }

  @override
  Future<Result<void>> write(String alias, String apiKey) async {
    entries[alias] = apiKey;
    return okUnit();
  }

  @override
  Future<Result<void>> delete(String alias) async {
    entries.remove(alias);
    return okUnit();
  }

  @override
  Future<Result<bool>> exists(String alias) async {
    return Ok<bool>(entries.containsKey(alias));
  }

  @override
  Future<bool> isAvailable() async => available;
}

/// 把 [DiagnosticLog] 接成 features 侧的诊断端口（与生产同一路径）。
final class _LogSink implements DiagnosticSink {
  const _LogSink(this._log);

  final DiagnosticLog _log;

  @override
  void record(DiagnosticSeverity severity, String message, {String? tag}) {
    _log.record(_level(severity), message, tag: tag);
  }

  @override
  void error(String message, {String? tag}) => _log.error(message, tag: tag);

  @override
  void warning(String message, {String? tag}) =>
      _log.warning(message, tag: tag);

  @override
  void info(String message, {String? tag}) => _log.info(message, tag: tag);

  static DiagnosticLevel _level(DiagnosticSeverity severity) =>
      switch (severity) {
        DiagnosticSeverity.error => DiagnosticLevel.error,
        DiagnosticSeverity.warning => DiagnosticLevel.warning,
        DiagnosticSeverity.info => DiagnosticLevel.info,
      };
}
