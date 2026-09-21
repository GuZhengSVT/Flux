// 启动装配（T011，完成 T010 遗留第 3 条）。
//
// 职责：在 widget 树之外把「进程级依赖」准备好——数据目录、数据库、设置仓储、
// 本机状态、凭据存储与诊断日志——再用一次 ProviderScope.overrides 注入进去。
//
// 为什么把装配结果做成一个显式对象而不是在 main 里散写：
//   1) 失败必须以「壳层仍可显示」的形式呈现。数据库打不开（版本过新、磁盘满、
//      权限不足）时，应用仍应启动并明确告知，而不是白屏或反复重启——主题与语言
//      仍可临时查看，但必须说明改动不会保存；
//   2) 测试要能在内存数据库上构造同样的注入（见 test/app/），不依赖真实磁盘；
//   3) 释放需要一个明确归属者，散写会漏关数据库。
//
// 安全边界（架构第 8 节）：
//   - 凭据存储**没有明文回退**：Keychain 不可用时退到会话内存，并在诊断里记录；
//   - 诊断日志只写结构化摘要（错误类别/操作名），不写正文、prompt 与凭据。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/onboarding/application/onboarding_state.dart';
import 'package:flux/features/settings/application/settings_store.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/ai_task_store.dart';
import 'package:flux/infrastructure/local/device_state_repository.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart';
import 'package:flux/infrastructure/local/settings_repository.dart';
import 'package:flux/infrastructure/platform/credential_store.dart';
import 'package:flux/infrastructure/platform/keychain_store.dart';

/// 应用数据目录名（与包标识一致的稳定名字，便于用户定位）。
const String fluxDataDirectoryName = 'Flux';

/// 数据库文件名。
const String fluxDatabaseFileName = 'flux.sqlite';

/// 诊断日志文件名。
const String fluxDiagnosticLogFileName = 'diagnostics.log';

/// 媒体缓存目录名（T021；与数据库同放在应用数据目录下）。
///
/// 与数据库并列而不是放进系统临时目录：缓存要跨启动保留（「离线可读」依赖它），
/// 而临时目录会被系统清理。放在同一个数据目录下也让「一键清缓存」与「彻底卸载」
/// 有一个明确的边界（T047 处理清理策略）。
const String fluxMediaCacheDirectoryName = 'media';

/// 启动装配结果：可用依赖，以及「哪些能力被降级」的明确记录。
final class AppBootstrapResult {
  /// 构造装配结果。
  const AppBootstrapResult({
    required this.database,
    required this.databaseFailure,
    required this.settingsStore,
    required this.onboardingStore,
    required this.credentialStore,
    required this.diagnosticLog,
    required this.dataDirectoryPath,
    this.mediaCacheDirectory,
    this.interruptedTaskCount = 0,
  });

  /// 已打开的数据库；启动失败时为 null。
  final AppDatabase? database;

  /// 数据库打开失败的原因（已类型化）；成功时为 null。
  final AppError? databaseFailure;

  /// 设置读写端口（数据库不可用时退化为只读默认值 + 明确失败的写入）。
  final SettingsStore settingsStore;

  /// 首次引导标记端口（数据库不可用时只在本次会话内有效）。
  final OnboardingStore onboardingStore;

  /// 凭据存储（Keychain，或没有安全存储时的会话内存）。
  final CredentialStore credentialStore;

  /// 诊断日志。
  final DiagnosticLog diagnosticLog;

  /// 实际使用的数据目录路径；未能解析时为 null。
  final String? dataDirectoryPath;

  /// 媒体缓存目录（T021）；数据目录不可用时为 null。
  ///
  /// 为 null 时图片仍然可用（每次都重新取，不落盘），因为「本次运行不持久化」不等于
  /// 「图片功能不可用」。
  final Directory? mediaCacheDirectory;

  /// 本次启动时被标记为 interrupted 的 AI 任务数（T030）。
  ///
  /// 为什么把它带到装配结果里：用户需要知道「上次有任务没跑完」，而清单里没有任何
  /// 界面状态能表达「这是本次启动判定出来的」。为 0 表示上次没有留下未完成任务
  /// （正常情况，不需要任何提示）。
  final int interruptedTaskCount;

  /// 数据库是否不可用（界面据此显示「本次运行不保存改动」）。
  bool get isDegraded => database == null;

  /// 释放进程级资源。
  Future<void> dispose() async {
    await database?.close();
  }
}

/// 执行启动装配。
///
/// [dataDirectoryOverride] 与 [credentialStoreOverride] 只给测试使用，
/// 避免测试依赖真实平台目录与系统钥匙串。
Future<AppBootstrapResult> bootstrapApp({
  Directory? dataDirectoryOverride,
  CredentialStore? credentialStoreOverride,
  bool enableFileLog = true,
}) async {
  // ---- 1. 数据目录 -------------------------------------------------------
  Directory? dataDirectory = dataDirectoryOverride;
  if (dataDirectory == null) {
    try {
      final Directory support = await getApplicationSupportDirectory();
      dataDirectory = Directory(p.join(support.path, fluxDataDirectoryName));
    } on Exception {
      // 目录解析失败不是致命错误：壳层与主题仍可用，只是不能持久化。
      dataDirectory = null;
    }
  }

  // ---- 2. 诊断日志（先建，后面的步骤才能记日志） --------------------------
  DiagnosticLog diagnostics = DiagnosticLog();
  if (enableFileLog && dataDirectory != null) {
    try {
      await dataDirectory.create(recursive: true);
      diagnostics = DiagnosticLog(
        fileSink: FileDiagnosticSink(
          file: File(p.join(dataDirectory.path, fluxDiagnosticLogFileName)),
        ),
      );
    } on Exception {
      // 文件 sink 不可用（只读目录、磁盘满）时退回纯内存日志，不阻断启动。
      diagnostics = DiagnosticLog();
      diagnostics.warning('诊断日志文件不可用，本次运行只保留内存日志', tag: 'bootstrap');
    }
  }

  // ---- 3. 数据库 ---------------------------------------------------------
  AppDatabase? database;
  AppError? databaseFailure;
  if (dataDirectory != null) {
    try {
      final File file = File(p.join(dataDirectory.path, fluxDatabaseFileName));
      final Result<AppDatabase> opened = await openAppDatabase(file);
      if (opened.isOk) {
        database = opened.valueOrNull;
      } else {
        databaseFailure = opened.errorOrNull;
        diagnostics.error('数据库打开失败：${databaseFailure?.kind}', tag: 'bootstrap');
      }
    } on Exception {
      // 只记录操作名与类别；异常原始文本可能含文件路径与用户目录结构。
      databaseFailure = StorageError(
        operation: 'bootstrapApp',
        detail: '数据目录初始化失败',
      );
      diagnostics.error('数据目录初始化失败', tag: 'bootstrap');
    }
  } else {
    databaseFailure = StorageError(
      operation: 'bootstrapApp',
      detail: '无法解析应用数据目录',
    );
  }

  // ---- 4. 设置与本机状态端口 --------------------------------------------
  final AppDatabase? db = database;
  final SettingsStore settingsStore = db == null
      ? const InMemorySettingsStore()
      : RepositorySettingsStore(SettingsRepository(db));
  final OnboardingStore onboardingStore = db == null
      ? InMemoryOnboardingStore()
      : RepositoryOnboardingStore(DeviceStateRepository(db));

  // ---- 4b. 中断恢复（T030） --------------------------------------------
  // 把上次进程结束时仍在进行中的 AI 任务标成 interrupted，并**不**自动重发
  // （架构 4.5：不能自动重放不确定是否计费的请求）。这一步必须在任何界面代码读到
  // 任务列表之前完成，否则用户会先看到一个永远不会完成的「运行中」任务。
  int interrupted = 0;
  if (db != null) {
    final Result<int> marked = await DriftAiTaskStore(
      db,
      diagnostics: DiagnosticLogSink(diagnostics),
    ).markActiveAsInterrupted(at: DateTime.now().toUtc());
    if (marked.isOk) {
      interrupted = marked.valueOrNull!;
    } else {
      diagnostics.warning(
        'AI 任务中断标记失败 kind=${marked.errorOrNull!.kind}',
        tag: 'bootstrap',
      );
    }
  }

  // ---- 5. 凭据存储 ------------------------------------------------------
  final CredentialStore credentialStore =
      credentialStoreOverride ?? await _resolveCredentialStore(diagnostics);

  return AppBootstrapResult(
    database: database,
    databaseFailure: databaseFailure,
    settingsStore: settingsStore,
    onboardingStore: onboardingStore,
    credentialStore: credentialStore,
    diagnosticLog: diagnostics,
    dataDirectoryPath: dataDirectory?.path,
    mediaCacheDirectory: dataDirectory == null
        ? null
        : Directory(p.join(dataDirectory.path, fluxMediaCacheDirectoryName)),
    interruptedTaskCount: interrupted,
  );
}

/// 选择凭据存储实现。
///
/// 启动时探测一次平台通道：通道可用就用 Keychain，不可用（纯 Dart 测试环境、
/// 未注册插件的构建、被系统策略禁用）则退到会话内存并明确记录。
///
/// 这里**必须**真的探测而不是「默认假设可用」：假设可用会让凭据写入在用户
/// 首次配置 AI 时才失败，而那时用户已经以为密钥保存好了。
///
/// 绝不回退到明文文件——架构第 8 节把这条写成硬约束。
Future<CredentialStore> _resolveCredentialStore(
  DiagnosticLog diagnostics,
) async {
  final KeychainCredentialStore keychain = KeychainCredentialStore();
  try {
    if (await keychain.isAvailable()) {
      return keychain;
    }
  } on Exception {
    // 探测本身抛异常等同于「不可用」，继续走降级分支。
  }
  diagnostics.warning('安全存储不可用，本次会话使用内存凭据（不会持久化）', tag: 'credentials');
  return InMemoryCredentialStore();
}

/// 由 T010 仓储支撑的设置端口。
///
/// 公开而不是私有：测试要能用**同一个**适配器把内存数据库接到设置页上，
/// 这样「测试里写设置」与「生产里写设置」走的是同一条路径。
final class RepositorySettingsStore implements SettingsStore {
  /// 绑定一个设置仓储。
  const RepositorySettingsStore(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Result<Object?>> readSetting(SettingId id) => _repository.read(id);

  @override
  Future<Result<Object?>> writeSetting(SettingId id, Object? value) =>
      _repository.write(id, value);

  @override
  Future<Result<Map<String, Object?>>> readEffectiveSettings() =>
      _repository.readEffective();
}

/// 数据库不可用时的设置端口：读回注册表默认值，写入明确失败。
///
/// 为什么写入要失败而不是「内存里接受」：本次运行本来就不保存任何改动，
/// 假装写成功会让设置页显示一个重启后就消失的值。宁可让界面明确提示不保存。
final class InMemorySettingsStore implements SettingsStore {
  /// 构造只读默认值、写入必然失败的设置端口。
  const InMemorySettingsStore();

  @override
  Future<Result<Object?>> readSetting(SettingId id) async {
    final SettingDefinition? definition = SettingRegistry.findById(id);
    if (definition == null) {
      return Err<Object?>(unknownSettingId(id));
    }
    return Ok<Object?>(definition.defaultValue);
  }

  @override
  Future<Result<Object?>> writeSetting(SettingId id, Object? value) async =>
      Err<Object?>(
        StorageError(
          operation: 'settings.write(${id.code})',
          detail: '本次运行数据库不可用，设置不会保存',
        ),
      );

  @override
  Future<Result<Map<String, Object?>>> readEffectiveSettings() async =>
      Ok<Map<String, Object?>>(<String, Object?>{
        for (final SettingDefinition definition in SettingRegistry.all)
          definition.id.code: definition.defaultValue,
      });
}

/// 由本机状态仓储支撑的引导标记端口。
final class RepositoryOnboardingStore implements OnboardingStore {
  /// 绑定一个本机状态仓储。
  const RepositoryOnboardingStore(this._repository);

  final DeviceStateRepository _repository;

  @override
  Future<bool> isCompleted() async {
    final Result<bool> result = await _repository.readBool(
      DeviceStateKey.onboardingCompleted,
    );
    // 读失败按「未完成」处理：见 OnboardingStore.isCompleted 的说明。
    return result.getOrElse(false);
  }

  @override
  Future<void> markCompleted() async {
    final Result<void> result = await _repository.writeBool(
      DeviceStateKey.onboardingCompleted,
      true,
    );
    if (result.isErr) {
      // 不抛异常：引导已经走完，标记写失败只影响「下次是否再显示」，
      // 不值得让用户当场看到一个失败对话框。调试输出便于定位磁盘/权限问题。
      debugPrint('onboardingCompleted 写入失败');
    }
  }
}

/// 数据库不可用时的引导标记端口：只在本次会话内有效。
final class InMemoryOnboardingStore implements OnboardingStore {
  /// 构造一个空的会话内存引导标记。
  InMemoryOnboardingStore();

  bool _completed = false;

  @override
  Future<bool> isCompleted() async => _completed;

  @override
  Future<void> markCompleted() async {
    _completed = true;
  }
}
