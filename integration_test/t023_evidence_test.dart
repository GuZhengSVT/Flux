// T023 证据采集：在真实 macOS 上驱动真实应用进入「阅读统计」页，供外部截图。
//
// 与 T011/T020/T022 同一套协调方式与理由（本机辅助功能权限被禁用，脚本无法点击真实
// 窗口，因此由 Flutter 测试框架完成状态切换，外部脚本只按窗口 id 做 screencapture -l）。
//
// **每个状态是一个独立 testWidgets**（理由同 T011：同一用例里第二次 pumpWidget 会复用
// element 树与容器，状态之间可能互相污染）。
//
// 运行：flutter test integration_test/t023_evidence_test.dart -d macos
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flux/app/app_bootstrap.dart';
import 'package:flux/app/app_providers.dart';
import 'package:flux/app/app.dart' show FluxApp;
import 'package:flux/app/shell/app_destination.dart';
import 'package:flux/app/shell/app_shell.dart';
import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/infrastructure/local/reading_stats_store.dart';

/// 证据目录名（外部脚本按它轮询状态文件）。
const String evidenceDirName = 'flux-t023-evidence';

/// 每个状态停留的时长：覆盖外部脚本的轮询与截图耗时。
const Duration stateHold = Duration(seconds: 8);

/// 需要外部 screencapture 抓真实窗口的状态名。
const List<String> screenshotStates = <String>['stats_page_light_zh_wide'];

const SessionLocalZone _zone = FixedOffsetZone(
  Duration(hours: 8),
  ianaName: 'Asia/Shanghai',
);

/// 用固定偏移构造当地日期键对应的 UTC 起点。
DateTime _utcFor(String localDate, int hour) => _zone.toUtc(
  DateTime.utc(
    int.parse(localDate.substring(0, 4)),
    int.parse(localDate.substring(5, 7)),
    int.parse(localDate.substring(8, 10)),
    hour,
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory evidenceDir;
  AppBootstrapResult? bootstrap;
  int stateIndex = 0;

  setUpAll(() async {
    final Directory support = await getApplicationSupportDirectory();
    evidenceDir = Directory('${support.path}/$evidenceDirName');
    if (evidenceDir.existsSync()) {
      evidenceDir.deleteSync(recursive: true);
    }
    evidenceDir.createSync(recursive: true);
  });

  tearDown(() async {
    await bootstrap?.dispose();
    bootstrap = null;
  });

  tearDownAll(() {
    File('${evidenceDir.path}/done.txt').writeAsStringSync(
      jsonEncode(<String, Object?>{
        'states': screenshotStates,
        'note': '真实 macOS 窗口截图；统计页展示年度热力图、图例与近七日柱状图。',
      }),
    );
  });

  /// 把一个状态名写给外部脚本，并停留等待截图。
  Future<void> announce(WidgetTester tester, String state) async {
    File('${evidenceDir.path}/state.txt')
        .writeAsStringSync(jsonEncode(<String, Object?>{'state': state}));
    final DateTime deadline = DateTime.now().add(stateHold);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// 装配真实应用、灌入阅读会话，并停在统计页。
  Future<void> pumpStatsPage(WidgetTester tester) async {
    stateIndex += 1;
    final Directory dataDir = Directory('${evidenceDir.path}/data-$stateIndex');
    dataDir.createSync(recursive: true);

    final AppBootstrapResult current = await bootstrapApp(
      dataDirectoryOverride: dataDir,
    );
    bootstrap = current;
    await current.settingsStore.writeSetting(SettingId.set001, 'zh-Hans');
    await current.settingsStore.writeSetting(SettingId.set002, 'light');
    await current.onboardingStore.markCompleted();

    final AppDatabase? db = current.database;
    expect(db, isNotNull, reason: '证据采集需要真实数据库');
    final int feedId = (await DriftFeedCatalogStore(db!).createFeed(
      const FeedInsert(
        syncId: 'feed.evidence.t023',
        normalizedUrl: 'https://evidence.example.com/feed.xml',
        name: '证据源',
      ),
    )).unwrap().id;

    final int articleId = await db
        .into(db.articles)
        .insert(
          ArticlesCompanion.insert(
            feedId: Value<int?>(feedId),
            title: '统计证据文章',
            identityBasis: IdentityBasis.guid,
            guid: const Value<String?>('evidence-t023'),
            guidPresent: const Value<bool>(true),
            body: const Value<String?>('用于构造阅读会话的正文。'),
          ),
        );

    // 造一段「形态像真实使用」的历史：最近两周每天都有长短不一的阅读，
    // 再加上几个月前的一些日子，让热力图上既有深色格也有 0 值格。
    final ReadingStatsStore store = DriftReadingStatsStore(db);
    final DateTime today = DateTime.utc(2026, 9, 22);
    final List<ReadingSessionDraft> drafts = <ReadingSessionDraft>[];
    for (int i = 0; i < 14; i++) {
      final DateTime day = today.subtract(Duration(days: i));
      // 隔天有数据：这样热力图里既有活跃格，也有可辨的 0 值格。
      if (i.isOdd) {
        continue;
      }
      final int minutes = 5 + (i * 7) % 55;
      final DateTime startedAt = _utcFor(localDateKey(day), 9);
      drafts.add(
        ReadingSessionDraft(
          articleId: articleId,
          startedAt: startedAt,
          endedAt: startedAt.add(Duration(minutes: minutes)),
          effectiveSeconds: minutes * 60,
          timeZone: 'Asia/Shanghai',
          localDate: localDateKey(day),
        ),
      );
    }
    for (final String date in <String>[
      '2026-01-12',
      '2026-02-03',
      '2026-03-08',
      '2026-04-19',
      '2026-05-27',
      '2026-06-14',
      '2026-07-21',
    ]) {
      final DateTime startedAt = _utcFor(date, 10);
      drafts.add(
        ReadingSessionDraft(
          articleId: articleId,
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(minutes: 42)),
          effectiveSeconds: 42 * 60,
          timeZone: 'Asia/Shanghai',
          localDate: date,
        ),
      );
    }
    await store.appendSessions(drafts);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          // 统计页要读会话时区：用固定偏移（UTC+8），保证热力图与柱状图的
          // 「今天」在截图里是确定的。必须通过 bootstrapOverrides 的参数传入——
          // Riverpod 禁止同一容器里重复覆盖同一个 Provider。
          ...bootstrapOverrides(current, sessionZone: _zone),
        ],
        child: const FluxApp(),
      ),
    );
    await tester.pumpAndSettle();

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(FluxApp)),
    );
    container.read(selectedDestinationProvider.notifier).state =
        AppDestination.mine;
    await tester.pumpAndSettle();

    // 进入「阅读统计」。
    await tester.tap(find.text('阅读统计').first);
    await tester.pumpAndSettle();
  }

  testWidgets('阅读统计页（浅色中文宽窗）', (WidgetTester tester) async {
    await pumpStatsPage(tester);
    await announce(tester, 'stats_page_light_zh_wide');
  });
}
