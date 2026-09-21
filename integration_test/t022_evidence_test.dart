// T022 证据采集：在真实 macOS 上驱动真实应用进入「检索结果（片段高亮）」与
// 「无结果态」，供外部截图。
//
// 与 T011/T020 同一套协调方式与理由（本机辅助功能权限被禁用，脚本无法点击真实窗口，
// 因此由 Flutter 测试框架完成状态切换，外部脚本只按窗口 id 做 screencapture -l）。
//
// **每个状态是一个独立 testWidgets**（理由同 T011：同一用例里第二次 pumpWidget 会复用
// element 树与容器，状态之间可能互相污染）。
//
// 运行：flutter test integration_test/t022_evidence_test.dart -d macos
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flux/app/app_providers.dart';
import 'package:flux/app/app_bootstrap.dart';
import 'package:flux/core/core.dart';
import 'package:flux/features/articles/presentation/reading_page.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/platform/credential_store.dart';
import 'package:flux/l10n/l10n.dart';

/// 每个状态停留的时长：覆盖外部脚本的轮询与截图耗时。
const Duration stateHold = Duration(seconds: 6);

/// 需要外部 screencapture 抓真实窗口的状态名。
const List<String> screenshotStates = <String>[
  'search_results_light_zh_wide',
  'search_empty_light_zh_wide',
];

/// 建一个内存库并灌入三篇可检索的文章。
Future<AppDatabase> seed() async {
  final AppDatabase db = AppDatabase.memory();
  await db.customSelect('SELECT 1').get();
  final int feedId = await db
      .into(db.feeds)
      .insert(
        FeedsCompanion.insert(
          syncId: 'evidence',
          normalizedUrl: 'https://evidence.example.com/feed.xml',
          name: '示例科技源',
        ),
      );
  for (int i = 0; i < 3; i++) {
    await db
        .into(db.articles)
        .insert(
          ArticlesCompanion.insert(
            feedId: Value<int?>(feedId),
            title: '离线阅读与 AI 摘要（第 $i 篇）',
            identityBasis: IdentityBasis.guid,
            guid: Value<String?>('evidence-$i'),
            guidPresent: const Value<bool>(true),
            summary: const Value<String?>('摘要：本文讨论离线缓存的实现。'),
            body: Value<String?>('正文第 $i 篇：本文说明离线阅读的完整实现方式，涵盖缓存与同步设计。'),
          ),
        );
  }
  return db;
}

/// 把阅读页挂进真实的组合根（主题与本地化走生产路径）。
Future<void> pumpReading(WidgetTester tester, AppDatabase db) async {
  final AppBootstrapResult result = AppBootstrapResult(
    database: db,
    databaseFailure: null,
    settingsStore: const InMemorySettingsStore(),
    onboardingStore: InMemoryOnboardingStore(),
    credentialStore: InMemoryCredentialStore(),
    diagnosticLog: DiagnosticLog(),
    dataDirectoryPath: null,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: bootstrapOverrides(result),
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ReadingPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('状态 1：检索结果（片段高亮）', (WidgetTester tester) async {
    final AppDatabase db = await seed();
    addTearDown(db.close);
    await pumpReading(tester, db);

    // 长片段走 MATCH 路径，片段由 fts5 的 snippet() 高亮。
    await tester.enterText(find.byType(TextField).first, '离线阅读的完整实现');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.textContaining('命中'), findsWidgets);
    await tester.pump(stateHold);
  });

  testWidgets('状态 2：无结果态', (WidgetTester tester) async {
    final AppDatabase db = await seed();
    addTearDown(db.close);
    await pumpReading(tester, db);

    await tester.enterText(find.byType(TextField).first, 'zzzzz这个词不存在');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的文章'), findsOneWidget);
    await tester.pump(stateHold);
  });
}
