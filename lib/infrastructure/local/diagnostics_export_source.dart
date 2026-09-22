// 诊断包内容来源的实现（T048；端口在 features/settings/application/maintenance_ports.dart）。
//
// 四节的字段都逐条来自**已经存在的读取路径**，不新增一条「为了诊断」的查询：
//   * 系统信息：Flutter/Dart/OS 版本与运行模式由 `dart:io` 与 `foundation` 提供，版本常量取自
//     core 的发布元数据（与设置页关于区同一份，不抄第二个数字）；
//   * 存储统计：复用 T047 的 [StorageCleanupStore.measureDatabase]（分类占用）与三个计数；
//   * 同步摘要：复用 T044 的窄读取端口（它本来就只读本机状态、不发请求）；
//   * 日志：DiagnosticLog 的 `export()`（它自身已在导出时再跑一遍脱敏）。
//
// **没有**任何字段来自 `articles`（正文/标题/摘要）、`ai_tasks`（输入快照/结果文本）或
// `news_runs`（初稿/prompt）。这不是「本文件没写」，而是「本文件拿不到」——它注入的端口是
// 存储统计与状态摘要，没有任何一个是正文读取口。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/cleanup_ports.dart';
import 'package:flux/features/settings/application/maintenance_ports.dart';

import 'diagnostics.dart';

/// 诊断包内容来源实现。
final class LocalDiagnosticsExportSource implements DiagnosticsExportSource {
  /// 构造实现。
  const LocalDiagnosticsExportSource({
    required this.log,
    required this.appVersion,
    required this.cleanupStore,
    required this.mediaCache,
    this.counts,
    required this.syncSummary,
    required this.environment,
    this.dataDirectoryPresent = false,
    this.mediaLimitMiB = kDefaultCacheMiB,
    this.settingsSummary,
    this.clock = const SystemClock(),
  });

  /// 诊断日志（内存 + 文件）。
  final DiagnosticLog log;

  /// 应用版本（来自 core 的发布元数据）。
  final String appVersion;

  /// 存储统计来源（T047）；为 null 表示数据库不可用（storage 小节只报可读的部分）。
  final StorageCleanupStore? cleanupStore;

  /// 媒体缓存端口（媒体占用的来源；为 null 表示没有装配）。
  ///
  /// 与数据库分开注入：媒体占用住在文件系统，把它的读取塞进数据库端口会让「一个接口同时
  /// 回答两类不同介质的问题」（与 T047 的端口划分同一口径）。
  final MediaCachePort? mediaCache;

  /// 订阅数与文章数（**只读计数**，不读任何标题或正文）。
  ///
  /// 用回调而不是往 [StorageCleanupStore] 上加一个 `counts()`：那个端口的职责是清理，而
  /// 「库里有多少条」是一次纯粹的统计查询，让清理端口多一个与清理无关的方法会稀释它的语义
  /// （与 T024 不把正文写入塞进 ArticleCatalogStore 同一个理由）。
  final Future<({int feeds, int articles})> Function()? counts;

  /// 同步状态摘要来源；为 null 表示没有数据库（按「未配置」报）。
  final Future<Result<SyncStatusBaseline>> Function()? syncSummary;

  /// 环境信息（OS / Dart 版本 / 架构 / 语言与主题）。
  final DiagnosticsEnvironment environment;

  /// 数据目录是否存在（**只报存在性，不报路径**：路径里有用户名）。
  final bool dataDirectoryPresent;

  /// 媒体上限（SET-080 的当前值）。
  final int mediaLimitMiB;

  /// 读界面语言与主题（SET-001/SET-002 的**有效值**）。
  ///
  /// 用回调而不是在构造时取值：构造发生在组合根（同步），而设置读取是异步的。把两个假的占位
  /// 字符串塞进诊断包比少两个字段更糟——那会让读者以为语言是那个字符串。为 null 时如实报
  /// `unavailable`。
  final Future<({String locale, String themeMode})> Function()? settingsSummary;

  /// 时钟。
  final Clock clock;

  @override
  Future<Result<DiagnosticsSection>> systemSection() async {
    String locale = 'unavailable';
    String themeMode = 'unavailable';
    final Future<({String locale, String themeMode})> Function()? readSettings =
        settingsSummary;
    if (readSettings != null) {
      final ({String locale, String themeMode}) value = await readSettings();
      locale = value.locale;
      themeMode = value.themeMode;
    }
    // 先构造字段列表再交给小节：`DiagnosticsSection` 是 const 构造器，而这里的值全部是运行期
    // 读出来的（版本常量、平台信息、设置），直接内联会让分析器把整块当成「可以 const」
    // 而报出与事实不符的提示。
    final List<DiagnosticsField> fields = <DiagnosticsField>[
      DiagnosticsField(name: 'appVersion', value: appVersion),
      // kReleaseMode / kProfileMode 是编译期常量，因此这一条整体是常量值。
      const DiagnosticsField(
        name: 'buildMode',
        value: kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      ),
      DiagnosticsField(name: 'osName', value: environment.osName),
      DiagnosticsField(name: 'osVersion', value: environment.osVersion),
      DiagnosticsField(name: 'dartVersion', value: environment.dartVersion),
      DiagnosticsField(
        name: 'cpuArchitecture',
        value: environment.architecture,
      ),
      DiagnosticsField(name: 'locale', value: locale),
      DiagnosticsField(name: 'themeMode', value: themeMode),
      DiagnosticsField(
        name: 'dataDirectoryPresent',
        value: dataDirectoryPresent ? 'true' : 'false',
      ),
    ];
    return Ok<DiagnosticsSection>(
      DiagnosticsSection(title: 'system', fields: fields),
    );
  }

  @override
  Future<Result<DiagnosticsSection>> storageSection() async {
    final StorageCleanupStore? store = cleanupStore;
    final List<DiagnosticsField> fields = <DiagnosticsField>[];
    fields.add(
      DiagnosticsField(
        name: 'mediaLimitBytes',
        value: '${cacheLimitBytes(mediaLimitMiB)}',
      ),
    );
    if (store == null) {
      // 数据库不可用：只报「读不到」这一事实，而不是编 0（那会让读者以为占用真的是 0）。
      fields.add(
        const DiagnosticsField(
          name: 'measuredAt',
          value: 'unavailable:database',
        ),
      );
      return Ok<DiagnosticsSection>(
        DiagnosticsSection(title: 'storage', fields: fields),
      );
    }
    final DateTime measuredAt = clock.now().toUtc();
    final Result<StorageUsageReport> measured = await store.measureDatabase(
      measuredAt: measuredAt,
    );
    if (measured.isErr) {
      fields.add(
        DiagnosticsField(
          name: 'measuredAt',
          value: 'unavailable:${measured.errorOrNull!.kind}',
        ),
      );
      return Ok<DiagnosticsSection>(
        DiagnosticsSection(title: 'storage', fields: fields),
      );
    }
    final StorageUsageReport report = measured.unwrap();
    final StorageCategoryUsage bodies = report.usageOf(
      StorageCategory.articleBody,
    );
    final StorageCategoryUsage summaries = report.usageOf(
      StorageCategory.newsSummary,
    );
    final StorageCategoryUsage database = report.usageOf(
      StorageCategory.database,
    );
    final Result<({int entries, int bytes})> ai = await store.aiCacheUsage();
    final Result<({int entries, int bytes})> drafts = await store
        .failedTaskDraftUsage();
    // 媒体占用由文件系统端口提供（数据库侧的统计里那一类是 0）。
    int mediaBytes = 0;
    int mediaEntries = 0;
    final MediaCachePort? media = mediaCache;
    if (media != null) {
      final Result<
        ({int entryCount, int imageBytes, int metaBytes, int tempBytes})
      >
      usage = await media.diskUsage();
      if (usage.isOk) {
        mediaBytes =
            usage.unwrap().imageBytes +
            usage.unwrap().metaBytes +
            usage.unwrap().tempBytes;
        mediaEntries = usage.unwrap().entryCount;
      }
    }
    fields.addAll(<DiagnosticsField>[
      DiagnosticsField(name: 'databaseBytes', value: '${database.byteCount}'),
      DiagnosticsField(name: 'mediaBytes', value: '$mediaBytes'),
      DiagnosticsField(name: 'mediaEntries', value: '$mediaEntries'),
      DiagnosticsField(name: 'articleBodyBytes', value: '${bodies.byteCount}'),
      DiagnosticsField(name: 'articleBodyCount', value: '${bodies.itemCount}'),
      DiagnosticsField(
        name: 'newsSummaryBytes',
        value: '${summaries.byteCount}',
      ),
      DiagnosticsField(
        name: 'newsSummaryCount',
        value: '${summaries.itemCount}',
      ),
      DiagnosticsField(
        name: 'aiCacheBytes',
        value: '${ai.valueOrNull?.bytes ?? 0}',
      ),
      DiagnosticsField(
        name: 'aiCacheEntries',
        value: '${ai.valueOrNull?.entries ?? 0}',
      ),
      DiagnosticsField(
        name: 'failedDraftCount',
        value: '${drafts.valueOrNull?.entries ?? 0}',
      ),
      DiagnosticsField(name: 'measuredAt', value: measuredAt.toIso8601String()),
    ]);
    final Future<({int feeds, int articles})> Function()? readCounts = counts;
    if (readCounts != null) {
      final ({int feeds, int articles}) value = await readCounts();
      fields
        ..add(DiagnosticsField(name: 'feedCount', value: '${value.feeds}'))
        ..add(
          DiagnosticsField(name: 'articleCount', value: '${value.articles}'),
        );
    }
    return Ok<DiagnosticsSection>(
      DiagnosticsSection(title: 'storage', fields: fields),
    );
  }

  @override
  Future<Result<DiagnosticsSection>> syncSection() async {
    final Future<Result<SyncStatusBaseline>> Function()? read = syncSummary;
    if (read == null) {
      return const Ok<DiagnosticsSection>(
        DiagnosticsSection(
          title: 'sync',
          fields: <DiagnosticsField>[
            DiagnosticsField(name: 'configured', value: 'false'),
            DiagnosticsField(name: 'enabled', value: 'false'),
            DiagnosticsField(name: 'capability', value: 'unknown'),
          ],
        ),
      );
    }
    final Result<SyncStatusBaseline> baseline = await read();
    if (baseline.isErr) {
      return Ok<DiagnosticsSection>(
        DiagnosticsSection(
          title: 'sync',
          fields: <DiagnosticsField>[
            DiagnosticsField(
              name: 'configured',
              value: 'unavailable:${baseline.errorOrNull!.kind}',
            ),
          ],
        ),
      );
    }
    final SyncStatusBaseline value = baseline.unwrap();
    return Ok<DiagnosticsSection>(
      DiagnosticsSection(
        title: 'sync',
        fields: <DiagnosticsField>[
          const DiagnosticsField(name: 'configured', value: 'true'),
          DiagnosticsField(name: 'capability', value: value.capability.name),
          DiagnosticsField(
            name: 'lastSyncedAt',
            value: value.lastSyncedAt?.toUtc().toIso8601String() ?? 'never',
          ),
          DiagnosticsField(
            name: 'pendingChangeCount',
            value: '${value.pendingChangeCount}',
          ),
          DiagnosticsField(
            name: 'baseVersionPresent',
            value: value.baseVersion == null ? 'false' : 'true',
          ),
          DiagnosticsField(
            name: 'degraded',
            value: value.capability == WebDavWriteCapability.readOnlyPull
                ? 'true'
                : 'false',
          ),
        ],
      ),
    );
  }

  @override
  Future<Result<DiagnosticsSection>> logSection() async {
    // `export()` 自身会在导出时对每条记录再跑一遍脱敏（T010 的第 3 层防线）。
    final String text = log.export();
    return Ok<DiagnosticsSection>(
      DiagnosticsSection(
        title: 'log',
        fields: <DiagnosticsField>[
          DiagnosticsField(
            name: 'logEntryCount',
            value: '${log.entries.length}',
          ),
          DiagnosticsField(name: 'logText', value: text),
        ],
      ),
    );
  }
}

/// 采集到的环境信息（由组合根填写；这样存储层不必依赖 path_provider 或平台通道）。
final class DiagnosticsEnvironment {
  /// 构造环境信息。
  const DiagnosticsEnvironment({
    required this.osName,
    required this.osVersion,
    required this.dartVersion,
    required this.architecture,
  });

  /// 从当前进程采集。
  ///
  /// 只采集**平台的事实**（OS / Dart / 架构）；语言与主题来自设置，不属于这里（见
  /// `settingsSummary`）。
  factory DiagnosticsEnvironment.current() => DiagnosticsEnvironment(
    osName: Platform.operatingSystem,
    osVersion: Platform.operatingSystemVersion,
    dartVersion: Platform.version.split(' ').first,
    architecture: Platform.version.contains('arm64') ? 'arm64' : 'unknown',
  );

  /// 操作系统名（`macos` / `android`）。
  final String osName;

  /// 操作系统版本原文。
  final String osVersion;

  /// Dart 版本（`3.13.0`）。
  final String dartVersion;

  /// CPU 架构。
  final String architecture;
}
