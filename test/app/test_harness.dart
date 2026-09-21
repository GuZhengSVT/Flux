// T011 组件测试的公共装配。
//
// 为什么用真实的内存数据库而不是替身：
//   「语言/主题切换会写入设置存储」是本任务的核心行为。若测试用假的设置端口，
//   验证的就只是「调用了一个方法」，而不是「值真的落库、重读仍在」。这里用
//   drift 的内存库 + T010 的真实仓储 + 组合根里同一个适配器，因此测试路径与
//   生产路径只差「存储介质」这一个变量。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/app/app_bootstrap.dart';
import 'package:flux/app/app_providers.dart';
import 'package:flux/app/theme/flux_theme.dart';
import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_platform_ports.dart';
import 'package:flux/features/articles/application/article_image_ports.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/device_state_repository.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/local/settings_repository.dart';
import 'package:flux/infrastructure/platform/credential_store.dart';
import 'package:flux/l10n/l10n.dart';

import 'fake_article_image_loader.dart';

/// 一个测试用的装配结果，绑定到内存数据库。
final class TestBootstrap {
  TestBootstrap._({
    required this.database,
    required this.settingsRepository,
    required this.deviceStateRepository,
    required this.credentialStore,
    this.degraded = false,
    this.failureKind,
  });

  /// 构造测试装配：默认在**同一个**内存数据库上建立两个仓储。
  ///
  /// 必须共用同一个数据库实例：如果设置与本机状态各自建一个内存库，
  /// 「写入后重读」的断言会因为读的是另一个库而失真。
  factory TestBootstrap({
    AppDatabase? database,
    bool degraded = false,
    String? failureKind,
    CredentialStore? credentialStore,
  }) {
    final AppDatabase resolved = database ?? AppDatabase.memory();
    return TestBootstrap._(
      database: resolved,
      settingsRepository: SettingsRepository(resolved),
      deviceStateRepository: DeviceStateRepository(resolved),
      credentialStore: credentialStore ?? InMemoryCredentialStore(),
      degraded: degraded,
      failureKind: failureKind,
    );
  }

  /// 内存数据库。
  final AppDatabase database;

  /// 设置仓储（真实 T010 实现）。
  final SettingsRepository settingsRepository;

  /// 本机状态仓储（真实 T011 实现）。
  final DeviceStateRepository deviceStateRepository;

  /// 凭据存储（内存；测试不触碰真实 Keychain）。
  final CredentialStore credentialStore;

  /// 是否模拟「数据库不可用」的降级启动。
  final bool degraded;

  /// 降级时的失败类别。
  final String? failureKind;

  /// 诊断日志（内存）。
  final DiagnosticLog diagnosticLog = DiagnosticLog();

  /// 生成组合根 overrides。
  ///
  /// 与生产**共用** [bootstrapOverrides] 的字段清单，但这里直接构造
  /// AppBootstrapResult：测试需要显式控制「降级」与「数据库可用」两种启动结果，
  /// 而不必真的制造一个磁盘错误。
  /// 生成组合根 overrides。
  ///
  /// [feedFetcher] 让订阅管理相关的测试注入固定的抓取响应（不联网）；为空时用
  /// 生产实现。放在这里而不是让测试各自 override：Riverpod 不允许同一容器内
  /// 重复覆盖一个 Provider，而这里正是生产装配路径上的那个位置。
  /// [networkConditions] 让阅读/刷新相关的测试构造「计费网络 / 离线」两种世界。
  /// 与 [feedFetcher] 一样走生产装配路径的那一个位置，避免「测试自己再覆盖一次」
  /// 触发 Riverpod 的重复覆盖断言。
  List<Override> overrides({
    FeedFetcher? feedFetcher,
    NetworkConditionPort? networkConditions,
    ExternalLinkOpener? externalLinkOpener,
    ImageSaveService? imageSaveService,
    SystemShareService? systemShareService,
    ArticleImageLoader? articleImageLoader,
  }) {
    return bootstrapOverrides(
      AppBootstrapResult(
        database: degraded ? null : database,
        databaseFailure: degraded
            ? StorageError(operation: 'test', detail: failureKind)
            : null,
        // 与 bootstrapApp 的选择保持一致：降级时用只读默认值 + 写入必然失败的
        // 端口。若这里仍给仓储，测试会「通过」，但通过的是一条生产中不存在的路径。
        settingsStore: degraded
            ? const InMemorySettingsStore()
            : RepositorySettingsStore(settingsRepository),
        onboardingStore: degraded
            ? InMemoryOnboardingStore()
            : RepositoryOnboardingStore(deviceStateRepository),
        credentialStore: credentialStore,
        diagnosticLog: diagnosticLog,
        dataDirectoryPath: null,
      ),
      feedFetcher: feedFetcher,
      networkConditions: networkConditions,
      externalLinkOpener: externalLinkOpener,
      imageSaveService: imageSaveService,
      systemShareService: systemShareService,
      // 默认注入一个**不联网**的图片加载器：绝大多数用例（golden、列表、阅读器）
      // 并不关心图片字节，但它们会挂载真实的图片位控件。不注入的话，每个用例都会
      // 走真实的 DNS 解析 + HTTP 请求（在 www.example.com 这类地址上等待超时），
      // 既慢又依赖网络、还会给测试留下 pending timer。需要验证缓存行为的用例
      // 自己传入真实或替身加载器。
      // 刻意**每次新建**一个加载器实例（不用 const）：图片 Provider 的缓存键包含
      // 加载器身份，而 ImageCache 是全局的、跨用例存活的。若各用例共用同一个常量
      // 实例，同一地址的键就会在用例之间相同，上一个用例被拆掉后残留的 pending
      // completer 会被下一个用例复用——而它已经不会再产出结果，于是失败会被报成
      // 「未处理的图像异常」并算到下一个用例头上（实测到的连锁失败）。
      articleImageLoader: articleImageLoader ?? OfflineArticleImageLoader(),
    );
  }

  /// 释放数据库。
  Future<void> dispose() => database.close();

  /// 预置 SET-001 界面语言（走真实仓储，因此也验证持久化路径）。
  Future<void> seedLanguage(String value) async {
    final Result<Object?> written = await settingsRepository.write(
      SettingId.set001,
      value,
    );
    expect(written.isOk, isTrue, reason: '预置语言失败');
  }

  /// 预置 SET-002 主题。
  Future<void> seedTheme(String value) async {
    final Result<Object?> written = await settingsRepository.write(
      SettingId.set002,
      value,
    );
    expect(written.isOk, isTrue, reason: '预置主题失败');
  }

  /// 预置「首次引导已完成」，让根组件直接进入应用壳。
  Future<void> completeOnboarding() async {
    final Result<void> written = await deviceStateRepository.writeBool(
      DeviceStateKey.onboardingCompleted,
      true,
    );
    expect(written.isOk, isTrue, reason: '预置引导标记失败');
  }
}

/// 只提供 ProviderScope 与 MediaQuery 的包装，供**自带 MaterialApp 的根组件**
/// （FluxApp）使用。
///
/// 不能复用 [wrapFluxApp]：那会在 FluxApp 之外再套一层 MaterialApp，
/// 于是「界面语言由 SET-001 决定」这条链路被外层固定 locale 掩盖——测试会通过，
/// 但通过的原因与产品行为无关。
Widget wrapRoot({
  required Widget child,
  required List<Override> overrides,
  Size surfaceSize = const Size(1200, 900),
  Brightness platformBrightness = Brightness.light,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MediaQuery(
      data: MediaQueryData(
        platformBrightness: platformBrightness,
        size: surfaceSize,
      ),
      child: child,
    ),
  );
}

/// 把被测组件包进与生产一致的 MaterialApp（主题 + locale + 委托）。
///
/// [localeOverride] 用于在测试里固定界面语言：locale 为 null 时按设备语言解析，
/// 而 flutter_test 默认环境是 en_US，若不定住语言断言中文文案会随机失败。
Widget wrapFluxApp({
  required Widget child,
  required List<Override> overrides,
  Locale? localeOverride = const Locale('zh'),
  ThemeMode themeMode = ThemeMode.light,
  Brightness platformBrightness = Brightness.light,
  Size? surfaceSize,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MediaQuery(
      data: MediaQueryData(
        platformBrightness: platformBrightness,
        // 固定窗口逻辑尺寸，让断点行为在测试里可复现。
        size: surfaceSize ?? const Size(1200, 800),
      ),
      child: MaterialApp(
        theme: FluxTheme.light(),
        darkTheme: FluxTheme.dark(),
        themeMode: themeMode,
        locale: localeOverride,
        supportedLocales: supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      ),
    ),
  );
}

/// 把测试窗口设置为指定逻辑尺寸（影响 LayoutBuilder 与断点判断）。
Future<void> setSurfaceSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
