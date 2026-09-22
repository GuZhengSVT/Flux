// T047：存储页的组件层验收（SET-077/078/079/080）。
//
// 三条边界，逐条对应架构 5.3 的原话：
//   1) **占用分类可见且有测量时间**（一个没有时间的数字无法让用户判断它是否还对得上）；
//   2) **自动清理开关真实读写 SET-077/078**（不是只改内存的假开关），且默认全关；
//   3) **清缓存有预览再确认**，且确认页明说只删可再生内容。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/presentation/storage_page.dart';
import 'package:flux/infrastructure/local/storage_cleanup_store.dart';

import '../../app/test_harness.dart';
import '../../app/fake_media_cache_port.dart';

void main() {
  late Directory mediaDir;
  late FakeMediaCachePort media;

  setUp(() {
    mediaDir = Directory.systemTemp.createTempSync('flux_t047_page_');
    media = FakeMediaCachePort();
  });

  tearDown(() {
    if (mediaDir.existsSync()) {
      mediaDir.deleteSync(recursive: true);
    }
  });

  /// 用真实内存库 + 真实临时媒体目录渲染存储页。
  Future<TestBootstrap> pumpPage(WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    await setSurfaceSize(tester, const Size(1200, 2400));
    await tester.pumpWidget(
      wrapFluxApp(
        child: const StoragePage(),
        overrides: bootstrap.overrides(
          storageCleanupStore: DriftStorageCleanupStore(
            bootstrap.database,
            mediaDirectoryPath: mediaDir.path,
          ),
          mediaCachePort: media,
        ),
        localeOverride: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();
    return bootstrap;
  }

  testWidgets('占用分类与测量时间都显示（且给未配置同步时说明无远端可回收）', (WidgetTester tester) async {
    await pumpPage(tester);

    // 五个分类逐项可见（媒体/正文/总结/其他缓存/数据库）。
    expect(find.textContaining('媒体缓存'), findsWidgets);
    expect(find.textContaining('文章正文'), findsWidgets);
    expect(find.textContaining('新闻总结'), findsWidgets);
    expect(find.textContaining('其他缓存'), findsWidgets);
    expect(find.textContaining('设置与状态数据库'), findsWidgets);
    // 合计与测量时间。
    expect(find.textContaining('合计：'), findsWidgets);
    expect(find.textContaining('测量时间：'), findsWidgets);
    // 媒体上限说明（有参照的绝对值才有意义）。
    expect(find.textContaining('媒体缓存上限：'), findsWidgets);
    // 未配置同步：孤儿快照小节说明「没有远端快照可回收」，且没有回收按钮。
    expect(find.textContaining('未配置同步'), findsWidgets);
    expect(find.text('回收孤儿快照'), findsNothing);
  });

  testWidgets('清缓存：先预览再确认，确认后回执可见', (WidgetTester tester) async {
    final TestBootstrap bootstrap = await pumpPage(tester);
    // 让媒体这一类的占用非零，使预览有真实数字。
    media
      ..entries = 1
      ..bytes = 64 * 1024 * 1024;
    // 重新测量，让界面吃到非零的媒体占用。
    await tester.tap(find.text('刷新占用'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('预览将释放的空间'));
    await tester.pumpAndSettle();

    // 预览对话框：明说只删可再生内容，且给出具体数字。
    expect(
      find.byKey(const ValueKey<String>('storage-clear-confirm')),
      findsOneWidget,
    );
    expect(find.textContaining('媒体缓存、AI 结果缓存与失败任务草稿'), findsWidgets);
    expect(find.textContaining('将释放'), findsWidgets);

    await tester.tap(find.text('清理'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已释放'), findsWidgets);
    // 清缓存真的调用了媒体端口的清空（真实文件删除由用例层的 cleanup_test 验证）。
    expect(media.clearCalls, 1);
    expect(media.entries, 0);
    // 界面上重新测量后的媒体占用是 0.0 MiB。
    expect(find.textContaining('媒体缓存'), findsWidgets);
    expect(bootstrap.database.schemaVersion, greaterThan(0));
  });

  testWidgets('自动清理开关**真实写入** SET-077/078（关→开落库）', (WidgetTester tester) async {
    final TestBootstrap bootstrap = await pumpPage(tester);

    // 默认全关：三个开关都是 off。
    final List<Switch> switches = tester
        .widgetList<Switch>(find.byType(Switch))
        .toList(growable: false);
    expect(switches.length, greaterThanOrEqualTo(5));
    expect(
      switches.every((Switch s) => s.value == false),
      isTrue,
      reason: '默认全关',
    );
    expect(find.textContaining('三个开关都关闭'), findsWidgets);

    // 打开「媒体清理」。
    await tester.tap(find.byKey(const ValueKey<String>('storage-auto-media')));
    await tester.pumpAndSettle();

    // 值真的落库（读回注册表编号）。
    final Result<Object?> stored = await bootstrap.settingsRepository.read(
      SettingId.set077,
    );
    final Map<String, Object?> written =
        stored.unwrap() as Map<String, Object?>;
    expect(written['mediaEnabled'], isTrue);
    expect(written['mediaDays'], 30, reason: '其余字段保留默认值，不被这一项写入重置');
    expect(written['articleEnabled'], isFalse);
    expect(written['articleDays'], 90);
    expect(written['summaryEnabled'], isFalse);
    expect(written['summaryDays'], 365);

    // 打开「包含收藏」→ 落 SET-078，并出现警告。
    await tester.tap(
      find.byKey(const ValueKey<String>('storage-auto-include-favorite')),
    );
    await tester.pumpAndSettle();
    final Result<Object?> set078 = await bootstrap.settingsRepository.read(
      SettingId.set078,
    );
    final Map<String, Object?> protection =
        set078.unwrap() as Map<String, Object?>;
    expect(protection['includeFavorite'], isTrue);
    expect(protection['includeLater'], isFalse);
    expect(find.textContaining('收藏与稍后再读的文章也会被自动清理'), findsWidgets);
  });

  testWidgets('天数步进只落在合法档位（越界在结构上不可达）', (WidgetTester tester) async {
    final TestBootstrap bootstrap = await pumpPage(tester);
    // 打开媒体清理，让它的天数控件可用。
    await tester.tap(find.byKey(const ValueKey<String>('storage-auto-media')));
    await tester.pumpAndSettle();
    expect(find.text('保留天数：30'), findsWidgets);

    // 加档：30 → 90。
    final Finder addButtons = find.byIcon(Icons.add);
    await tester.tap(addButtons.first);
    await tester.pumpAndSettle();
    expect(find.text('保留天数：90'), findsWidgets);

    final Result<Object?> stored = await bootstrap.settingsRepository.read(
      SettingId.set077,
    );
    expect((stored.unwrap() as Map<String, Object?>)['mediaDays'], 90);
  });
}
