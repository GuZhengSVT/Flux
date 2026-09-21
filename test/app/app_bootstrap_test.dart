// 启动装配测试（T011，完成 T010 遗留第 3 条的验收）。
//
// T010 记录的三条遗留中，第 3 条是「凭据与设置的运行时装配未接线到启动流程」。
// 本文件用**真实磁盘上的临时目录**跑 bootstrapApp，因此验证的是实际装配：
//   - 数据库真的建在指定目录里；
//   - 设置与引导标记真的落到那个数据库；
//   - 数据库打不开时进入明确的降级状态，而不是静默用内存假装成功；
//   - overrides 清单覆盖了所有「未接线就抛错」的 Provider。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/app/app_bootstrap.dart';
import 'package:flux/app/app_providers.dart';
import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/application/file_access.dart';
import 'package:flux/features/onboarding/application/onboarding_state.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/device_state_repository.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/platform/credential_store.dart';

void main() {
  // 装配会探测平台通道（Keychain 可用性），因此需要先初始化绑定。
  // 这是纯测试脚手架要求，不代表生产中需要额外初始化（生产走 runApp）。
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flux-t011-bootstrap-');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 在临时目录上做一次正常装配。
  Future<AppBootstrapResult> bootstrapInTemp() => bootstrapApp(
    dataDirectoryOverride: tempDir,
    credentialStoreOverride: InMemoryCredentialStore(),
  );

  group('正常装配', () {
    test('数据库建在指定目录，设置可写可读回', () async {
      final AppBootstrapResult result = await bootstrapInTemp();
      addTearDown(result.dispose);

      expect(result.isDegraded, isFalse);
      expect(result.databaseFailure, isNull);
      expect(result.dataDirectoryPath, tempDir.path);
      // 数据库文件真的落在磁盘上。
      expect(
        File('${tempDir.path}${Platform.pathSeparator}$fluxDatabaseFileName')
            .existsSync(),
        isTrue,
      );

      final Result<Object?> written = await result.settingsStore.writeSetting(
        SettingId.set002,
        'dark',
      );
      expect(written.isOk, isTrue);
      final Result<Object?> read = await result.settingsStore.readSetting(
        SettingId.set002,
      );
      expect(read.valueOrNull, 'dark');
    });

    test('未写过的设置读到注册表默认值，而不是 null', () async {
      final AppBootstrapResult result = await bootstrapInTemp();
      addTearDown(result.dispose);

      final Result<Object?> language = await result.settingsStore.readSetting(
        SettingId.set001,
      );
      expect(language.valueOrNull, 'system');
    });

    test('引导标记默认未完成，标记后为完成', () async {
      final AppBootstrapResult result = await bootstrapInTemp();
      addTearDown(result.dispose);

      expect(await result.onboardingStore.isCompleted(), isFalse);
      await result.onboardingStore.markCompleted();
      expect(await result.onboardingStore.isCompleted(), isTrue);
    });

    test('诊断日志已装配到文件 sink，默认级别为 error（SET-082）', () async {
      final AppBootstrapResult result = await bootstrapInTemp();
      addTearDown(result.dispose);

      expect(result.diagnosticLog.fileSink, isNotNull);
      expect(result.diagnosticLog.level, DiagnosticLevel.error);
    });

    test('凭据使用注入的实现；数据目录里不留任何凭据文件', () async {
      final AppBootstrapResult injected = await bootstrapInTemp();
      addTearDown(injected.dispose);
      expect(injected.credentialStore, isA<InMemoryCredentialStore>());

      // 未注入时要么走真实 Keychain，要么走会话内存——**绝不**写明文文件。
      final AppBootstrapResult resolved = await bootstrapApp(
        dataDirectoryOverride: tempDir,
      );
      addTearDown(resolved.dispose);
      final List<String> files = tempDir
          .listSync()
          .whereType<File>()
          .map((File file) => file.uri.pathSegments.last)
          .toList();
      expect(
        files.where((String name) => name.contains('credential')),
        isEmpty,
        reason: '凭据不得以文件形式落在数据目录',
      );
      expect(files.where((String name) => name.endsWith('.json')), isEmpty);
    });

    test('内存库可真实写入并读回（上层测试的替代路径）', () async {
      final AppDatabase memory = AppDatabase.memory();
      addTearDown(memory.close);
      final DeviceStateRepository repository = DeviceStateRepository(memory);
      expect(
        (await repository.readBool(DeviceStateKey.onboardingCompleted))
            .getOrElse(true),
        isFalse,
      );
      await repository.writeBool(DeviceStateKey.onboardingCompleted, true);
      expect(
        (await repository.readBool(DeviceStateKey.onboardingCompleted))
            .getOrElse(false),
        isTrue,
      );
    });
  });

  group('降级装配（数据目录不可用）', () {
    test('进入降级并说明原因；设置写入必须失败', () async {
      // 让「父级是普通文件」的路径无法建目录：创建必然失败。
      final File blocker = File(
        '${tempDir.path}${Platform.pathSeparator}blocker',
      );
      await blocker.writeAsString('not a directory');

      final AppBootstrapResult result = await bootstrapApp(
        dataDirectoryOverride: Directory(
          '${blocker.path}${Platform.pathSeparator}sub',
        ),
        credentialStoreOverride: InMemoryCredentialStore(),
        enableFileLog: false,
      );
      addTearDown(result.dispose);

      expect(result.isDegraded, isTrue);
      expect(result.database, isNull);
      expect(result.databaseFailure, isNotNull);
      expect(result.databaseFailure!.kind, 'storage');

      // 读回默认值（界面仍可用）。
      expect(
        (await result.settingsStore.readSetting(SettingId.set001)).valueOrNull,
        'system',
      );
      // 写入必须失败：本次运行不保存任何改动，不能假装成功。
      final Result<Object?> write = await result.settingsStore.writeSetting(
        SettingId.set001,
        'en',
      );
      expect(write.isErr, isTrue);
    });

    test('降级时引导标记只在会话内有效', () async {
      final File blocker = File(
        '${tempDir.path}${Platform.pathSeparator}blocker2',
      );
      await blocker.writeAsString('not a directory');
      final AppBootstrapResult result = await bootstrapApp(
        dataDirectoryOverride: Directory(
          '${blocker.path}${Platform.pathSeparator}sub',
        ),
        credentialStoreOverride: InMemoryCredentialStore(),
        enableFileLog: false,
      );
      addTearDown(result.dispose);

      expect(await result.onboardingStore.isCompleted(), isFalse);
      await result.onboardingStore.markCompleted();
      expect(await result.onboardingStore.isCompleted(), isTrue);
    });
  });

  group('组合根注入清单', () {
    test('overrides 覆盖全部「未接线即抛错」的 Provider', () async {
      final AppBootstrapResult result = await bootstrapInTemp();
      addTearDown(result.dispose);

      final ProviderContainer container = ProviderContainer(
        overrides: bootstrapOverrides(result),
      );
      addTearDown(container.dispose);

      // 这些读取若漏了 override 会抛 StateError（见 app_providers.dart 的设计）。
      expect(container.read(settingsStoreProvider), isNotNull);
      expect(container.read(onboardingStoreProvider), isNotNull);
      expect(container.read(credentialStoreProvider), isNotNull);
      expect(container.read(diagnosticLogProvider), isNotNull);
      expect(container.read(databaseProvider), isNotNull);
      // T015 的文件读写端口与数据库无关（只要系统文件面板），也必须在这里接好：
      // 漏接会让 OPML 导入/导出在使用时抛 StateError，而不是在启动时暴露。
      expect(container.read(fileAccessProvider), isNotNull);
      expect(container.read(appBootstrapStatusProvider).degraded, isFalse);
    });

    test('降级时不覆盖 databaseProvider，状态 Provider 明确报告降级', () {
      final AppBootstrapResult result = AppBootstrapResult(
        database: null,
        databaseFailure: StorageError(operation: 'test', detail: 'readonly'),
        settingsStore: const InMemorySettingsStore(),
        onboardingStore: InMemoryOnboardingStore(),
        credentialStore: InMemoryCredentialStore(),
        diagnosticLog: DiagnosticLog(),
        dataDirectoryPath: null,
      );

      final ProviderContainer container = ProviderContainer(
        overrides: bootstrapOverrides(result),
      );
      addTearDown(container.dispose);

      expect(container.read(appBootstrapStatusProvider).degraded, isTrue);
      expect(container.read(appBootstrapStatusProvider).failureKind, 'storage');
      // 数据库未注入：读取时必须失败，而不是返回一个空实现把「没接库」演成正常。
      // riverpod 3 会把 Provider 抛出的异常包成 ProviderException，因此这里断言
      // 「抛出且信息里点明是组装问题」，而不是具体异常类型。
      expect(
        () => container.read(databaseProvider),
        throwsA(
          predicate(
            (Object error) => error.toString().contains('未被组合根覆盖'),
            '读取未注入的 Provider 应抛出装配错误',
          ),
        ),
      );
    });
  });

  group('设置端口契约', () {
    test('InMemorySettingsStore 读默认值、写入明确失败、有效值覆盖 70 项', () async {
      const InMemorySettingsStore store = InMemorySettingsStore();
      expect((await store.readSetting(SettingId.set001)).valueOrNull, 'system');
      expect((await store.writeSetting(SettingId.set001, 'en')).isErr, isTrue);

      final Map<String, Object?> effective =
          (await store.readEffectiveSettings()).valueOrNull!;
      expect(effective.length, 70);
      // 与注册表完全一致，避免这里的默认值与文档口径漂移。
      expect(
        effective.keys.toSet(),
        SettingRegistry.all.map((SettingDefinition d) => d.id.code).toSet(),
      );
    });

    test('未注册编号读取失败（不返回一个幽灵默认值）', () async {
      const InMemorySettingsStore store = InMemorySettingsStore();
      final Result<Object?> unknown = await store.readSetting(
        const SettingId('SET-999'),
      );
      expect(unknown.isErr, isTrue);
    });
  });
}
