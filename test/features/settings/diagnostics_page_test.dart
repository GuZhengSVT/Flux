// T048：诊断页的组件层验收（SET-082）。
//
// 三条边界：
//   1) **导出前明说包内有什么、不含什么**，且确认之前不写文件；
//   2) **恢复编排状态如实展示**：三种阶段各自说明「当前数据在哪」；
//   3) **只在可用的阶段给出动作**——没有停放目录时不给「删除旧目录」按钮（那是最危险的假功能）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/maintenance_ports.dart';
import 'package:flux/features/settings/presentation/diagnostics_page.dart';
import 'package:flux/features/feeds/application/file_access.dart';

import '../../app/test_harness.dart';

/// 记录写盘内容的文件端口替身（组件层不弹系统面板）。
final class RecordingFilePort implements FileAccessPort {
  /// 每次保存写下的文本。
  final List<String> savedTexts = <String>[];

  @override
  Future<Result<String?>> saveBytes(
    String suggestedName,
    List<int> bytes, {
    required String mimeType,
    required List<String> extensions,
  }) async {
    savedTexts.add(utf8.decode(bytes));
    return Ok<String?>('/tmp/$suggestedName');
  }

  @override
  Future<Result<String?>> saveOpml(
    String suggestedName,
    String content,
  ) async => const Ok<String?>(null);

  @override
  Future<Result<PickedFile?>> pickOpmlToRead() async =>
      const Ok<PickedFile?>(null);

  @override
  Future<Result<PickedFile?>> pickArchiveToRead() async =>
      const Ok<PickedFile?>(null);
}

/// 恢复编排端口替身：从给定的标记与目录事实回答。
final class _FakeRestorePort implements RestoreOrchestrationPort {
  _FakeRestorePort({this.markerValue});

  RestoreMarker? markerValue;

  /// 删除过的目录（断言「确认后才删」）。
  final List<String> deleted = <String>[];

  @override
  String? get currentDataDirectoryPath => '/tmp/Flux';

  @override
  Future<Result<RestoreMarker?>> readMarker() async =>
      Ok<RestoreMarker?>(markerValue);

  @override
  Future<Result<void>> writeMarker(RestoreMarker marker) async {
    markerValue = marker;
    return okUnit();
  }

  @override
  Future<Result<void>> clearMarker() async {
    markerValue = null;
    return okUnit();
  }

  @override
  Future<bool> directoryExists(String path) async => true;

  @override
  Future<bool> databaseUsable(String directory) async => true;

  @override
  Future<Result<void>> moveDirectory({
    required String from,
    required String to,
  }) async => okUnit();

  @override
  Future<Result<void>> deleteDirectory(String path) async {
    deleted.add(path);
    return okUnit();
  }

  @override
  String newParkedDirectoryName(String token) => '/tmp/Flux.superseded-$token';
}

void main() {
  /// 渲染诊断页；[port] 决定展示哪一个阶段。
  Future<(TestBootstrap, _FakeRestorePort, RecordingFilePort)> pumpPage(
    WidgetTester tester, {
    RestoreMarker? marker,
  }) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    final _FakeRestorePort port = _FakeRestorePort(markerValue: marker);
    final RecordingFilePort files = RecordingFilePort();
    await setSurfaceSize(tester, const Size(1200, 1600));
    await tester.pumpWidget(
      wrapFluxApp(
        child: const DiagnosticsPage(),
        overrides: bootstrap.overrides(
          restoreOrchestrationPort: port,
          fileAccessPort: files,
          diagnosticsExportSource: _StubSource(),
        ),
        localeOverride: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();
    return (bootstrap, port, files);
  }

  testWidgets('导出：先说明再确认，确认前不写文件', (WidgetTester tester) async {
    final (TestBootstrap _, _FakeRestorePort _, RecordingFilePort files) =
        await pumpPage(tester);

    // 说明常驻可见（不需要点任何东西）。
    expect(find.textContaining('不含'), findsWidgets);
    expect(find.textContaining('文章原文'), findsWidgets);

    // 点导出：先出确认框，此时还没有写任何文件。
    await tester.tap(find.byKey(const ValueKey<String>('diagnostics-export')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('diagnostics-export-confirm')),
      findsOneWidget,
    );
    expect(files.savedTexts, isEmpty, reason: '确认之前不得写文件');

    // 取消：仍然没有写。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(files.savedTexts, isEmpty);

    // 再来一次并确认：这次真的写到文件。
    await tester.tap(find.byKey(const ValueKey<String>('diagnostics-export')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('diagnostics-export-go')),
    );
    await tester.pumpAndSettle();
    expect(files.savedTexts, hasLength(1));
    expect(files.savedTexts.single, contains('[system]'));
    expect(find.textContaining('已导出'), findsOneWidget);
  });

  testWidgets('无待编排恢复：说明现在的状态，不给清理按钮', (WidgetTester tester) async {
    await pumpPage(tester);
    expect(find.textContaining('没有待编排的恢复'), findsOneWidget);
    expect(find.textContaining('重启应用才能生效'), findsWidgets);
    expect(find.text('删除旧数据目录'), findsNothing);
    expect(find.text('放弃这次恢复'), findsNothing);
  });

  testWidgets('待重启阶段：说明当前数据仍是原来的，只给「放弃」', (WidgetTester tester) async {
    final (
      TestBootstrap _,
      _FakeRestorePort _,
      RecordingFilePort _,
    ) = await pumpPage(
      tester,
      marker: RestoreMarker(
        phase: RestorePhase.pendingRestart,
        restoredDirectory: '/tmp/Flux-restored-1',
        restoredAt: DateTime.utc(2026, 9, 22),
      ),
    );
    expect(find.textContaining('重启应用后生效'), findsWidgets);
    expect(find.textContaining('当前数据目录仍是原来的那一份'), findsWidgets);
    expect(find.textContaining('/tmp/Flux-restored-1'), findsWidgets);
    expect(find.text('放弃这次恢复'), findsOneWidget);
    // 还没有停放目录 → 不该出现「删除旧数据目录」。
    expect(find.text('删除旧数据目录'), findsNothing);
  });

  testWidgets('已切换阶段：显示旧目录路径，确认后才删除', (WidgetTester tester) async {
    final (
      TestBootstrap _,
      _FakeRestorePort port,
      RecordingFilePort _,
    ) = await pumpPage(
      tester,
      marker: RestoreMarker(
        phase: RestorePhase.switched,
        restoredDirectory: '/tmp/Flux',
        supersededDirectory: '/tmp/Flux.superseded-9',
        restoredAt: DateTime.utc(2026, 9, 22),
      ),
    );
    expect(find.textContaining('恢复已生效'), findsOneWidget);
    expect(find.textContaining('/tmp/Flux.superseded-9'), findsWidgets);

    // 点清理：先出确认框，此时还没有删任何目录。
    await tester.tap(find.byKey(const ValueKey<String>('diagnostics-cleanup')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('diagnostics-cleanup-confirm')),
      findsOneWidget,
    );
    expect(port.deleted, isEmpty, reason: '确认之前不得删除旧目录');

    // 取消：仍然没删。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(port.deleted, isEmpty);

    // 确认：这次真的删了。
    await tester.tap(find.byKey(const ValueKey<String>('diagnostics-cleanup')));
    await tester.pumpAndSettle();
    // 标题、按钮与列表行三处文案同名（同一个动作在三处出现），因此按**对话框里的 FilledButton**
    // 定位：列表行是 ListTile、标题是 Text，只有确认按钮是 FilledButton。
    await tester.tap(find.widgetWithText(FilledButton, '删除旧数据目录'));
    await tester.pumpAndSettle();
    expect(port.deleted, <String>['/tmp/Flux.superseded-9']);
    expect(find.textContaining('已删除旧数据目录'), findsOneWidget);
  });
}

/// 诊断内容替身：只给一个最小的真实小节（导出路径不依赖真实数据库）。
final class _StubSource implements DiagnosticsExportSource {
  @override
  Future<Result<DiagnosticsSection>> systemSection() async =>
      const Ok<DiagnosticsSection>(
        DiagnosticsSection(
          title: 'system',
          fields: <DiagnosticsField>[
            DiagnosticsField(name: 'appVersion', value: '0.2.0+1'),
          ],
        ),
      );

  @override
  Future<Result<DiagnosticsSection>> storageSection() async =>
      const Ok<DiagnosticsSection>(
        DiagnosticsSection(title: 'storage', fields: <DiagnosticsField>[]),
      );

  @override
  Future<Result<DiagnosticsSection>> syncSection() async =>
      const Ok<DiagnosticsSection>(
        DiagnosticsSection(title: 'sync', fields: <DiagnosticsField>[]),
      );

  @override
  Future<Result<DiagnosticsSection>> logSection() async =>
      const Ok<DiagnosticsSection>(
        DiagnosticsSection(title: 'log', fields: <DiagnosticsField>[]),
      );
}
