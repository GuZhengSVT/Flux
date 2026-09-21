// T020 证据采集：在真实 macOS 上驱动真实应用进入「详情页」与「图片查看器」，供外部截图。
//
// 与 T011 的采集用例同一套协调方式与理由（见 t011_evidence_test.dart 的详细说明）：
//   本机 macOS 辅助功能权限被禁用，脚本无法点击真实窗口，因此由 Flutter 自己的测试
//   框架完成「切到哪个状态」，外部脚本只按窗口 id 做 screencapture -l。
//
// **每个状态是一个独立 testWidgets**（理由同 T011：同一用例里第二次 pumpWidget 会复用
// element 树与容器，状态之间可能互相污染）。
//
// 运行：flutter test integration_test/t020_evidence_test.dart -d macos
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flux/app/app.dart';
import 'package:flux/app/app_bootstrap.dart';
import 'package:flux/app/app_providers.dart';
import 'package:flux/app/shell/app_shell.dart';
import 'package:flux/app/shell/app_destination.dart';
import 'package:flux/core/core.dart';
import 'package:flux/features/articles/presentation/article_detail_page.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
/// 每个状态停留的时长：要覆盖外部脚本的轮询间隔与截图耗时。
const Duration stateHold = Duration(seconds: 6);

/// 证据目录名（位于应用支持目录下）。
const String evidenceDirName = 'flux-t020-evidence';

/// 需要外部 screencapture 抓真实窗口的状态名。
const List<String> screenshotStates = <String>[
  'reading_list_light_zh_wide',
  'article_detail_light_zh_wide',
  'image_viewer_light_zh_wide',
];

/// 采集用的正文（含链接、代码、图片与列表，让详情页一屏就能看出渲染范围）。
const String sampleBody =
    '# 采集用标题\n'
    '\n'
    '这一段用于截图核对正文排版：正文 18、行高 1.7、段间距 0.8em。\n'
    '\n'
    '![采集用图片](https://cdn.example.com/t020.png)\n'
    '\n'
    '- 列表项一\n'
    '- 列表项二\n'
    '\n'
    '\u0060\u0060\u0060dart\n'
    'final answer = 42;\n'
    '\u0060\u0060\u0060\n'
    '\n'
    '外链示例：[Flux 仓库](https://github.com/guzhengsvt/flux)\n';

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
        'note':
            '真实 macOS 窗口截图；卡片图片与详情页图片引用的是 fixture 域名，'
            '因此图片位显示加载失败态（这是真实行为，不是缺陷）。',
      }),
    );
  });

  /// 把一个状态名写给外部脚本，并停留等待截图。
  ///
  /// 停留期间**持续 pump**（与 T011 的 announce 同一做法）：窗口必须保持可绘制，
  /// 截图才有内容。只 sleep 不 pump 会截到一帧空窗口或旧画面。
  Future<void> announce(WidgetTester tester, String state) async {
    File('${evidenceDir.path}/state.txt')
        .writeAsStringSync(jsonEncode(<String, Object?>{'state': state}));
    final DateTime deadline = DateTime.now().add(stateHold);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// 装配**真实应用**（真实数据库，落在独立子目录），写入证据文章并停在阅读页。
  Future<void> pumpApp(WidgetTester tester, {required bool openDetail}) async {
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
        syncId: 'feed.evidence',
        normalizedUrl: 'https://evidence.example.com/feed.xml',
        name: '证据源',
      ),
    )).unwrap().id;

    await db
        .into(db.articles)
        .insert(
          ArticlesCompanion.insert(
            feedId: Value<int?>(feedId),
            title: 'T020 证据文章：选区、复制、图片与链接',
            identityBasis: IdentityBasis.guid,
            guid: const Value<String?>('evidence-1'),
            guidPresent: const Value<bool>(true),
            summary: const Value<String?>('这是一段摘要，用于卡片与列表的截图核对。'),
            body: const Value<String?>(sampleBody),
            author: const Value<String?>('Flux'),
            bodyCompleteness: const Value<BodyCompleteness>(
              BodyCompleteness.sourceBody,
            ),
            publishedAt: Value<DateTime?>(DateTime.utc(2026, 9, 21, 12)),
            fetchedAt: Value<DateTime>(DateTime.utc(2026, 9, 21, 12)),
          ),
        );
    for (int i = 0; i < 12; i++) {
      await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: Value<int?>(feedId),
              title: '列表文章 $i：用于核对卡片形态与分批加载',
              identityBasis: IdentityBasis.guid,
              guid: Value<String?>('evidence-list-$i'),
              guidPresent: const Value<bool>(true),
              summary: const Value<String?>('列表摘要。'),
              publishedAt: Value<DateTime?>(
                DateTime.utc(
                  2026,
                  9,
                  21,
                  12,
                ).subtract(Duration(minutes: i + 1)),
              ),
              fetchedAt: Value<DateTime>(DateTime.utc(2026, 9, 21, 12)),
            ),
          );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: bootstrapOverrides(current),
        // 挂**真实根组件**而不是自建 MaterialApp：
        //   1) 本地化委托由 FluxApp 装配，自建 MaterialApp 必须自己配齐
        //      （实测漏了会直接报 AppLocalizations 空断言，截到的是一屏红字）；
        //   2) 截图要反映产品真实的主题/壳层，而不是证据用例自己搭的一个近似物。
        child: const FluxApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 引导已完成 → 会落到应用壳；切到 RSS 阅读去向。
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(FluxApp)),
    );
    container.read(selectedDestinationProvider.notifier).state =
        AppDestination.reading;
    await tester.pumpAndSettle();

    if (openDetail) {
      await tester.tap(find.textContaining('T020 证据文章').first);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('阅读列表（卡片形态 + 分批加载）', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await pumpApp(tester, openDetail: false);
    await announce(tester, 'reading_list_light_zh_wide');
  });

  testWidgets('文章详情（正文、图片位、外链、复制全文入口）', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await pumpApp(tester, openDetail: true);
    expect(
      find.byType(ArticleDetailPage),
      findsOneWidget,
      reason: '详情页必须真的打开了，否则截到的不是详情页',
    );
    await announce(tester, 'article_detail_light_zh_wide');
  });

  testWidgets('图片查看器（全屏、可缩放）', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await pumpApp(tester, openDetail: true);
    await tester.tap(
      find.textContaining('采集用图片').first,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await announce(tester, 'image_viewer_light_zh_wide');
  });
}
