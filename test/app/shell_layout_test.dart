// 壳层布局决策的纯函数测试（T011，架构第 7 节）。
//
// 组件测试覆盖「给定窗口宽度渲染出什么」，这里覆盖「临界宽度如何判定」。
// 两者互补：组件测试跑真实布局（含侧栏占宽），纯函数测试把边界值逐点钉住，
// 例如 599/600 与 1099/1100。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/app/shell/shell_layout.dart';
import 'package:flux/core/design/design_tokens.dart';

void main() {
  group('分栏判定', () {
    test('599 及以下为单栏', () {
      for (final double width in <double>[0, 320, 599]) {
        expect(
          resolvePaneLayout(width),
          ShellPaneLayout.single,
          reason: 'width=$width',
        );
      }
    });

    test('600 起为双栏（600 是含端点的边界）', () {
      for (final double width in <double>[600, 601, 800, 1099]) {
        expect(
          resolvePaneLayout(width),
          ShellPaneLayout.double,
          reason: 'width=$width',
        );
      }
    });

    test('1100 起为三栏（标准栏宽下正文余量 580 >= 560）', () {
      for (final double width in <double>[1100, 1200, 1600]) {
        expect(
          resolvePaneLayout(width),
          ShellPaneLayout.triple,
          reason: 'width=$width',
        );
      }
    });

    test('宽度达标但正文余量不足时退回双栏', () {
      // 用更宽的来源栏模拟「将来调整栏宽」：1100-320-300=480 < 560。
      expect(
        resolvePaneLayout(1100, sourcePaneWidth: 320, listPaneWidth: 300),
        ShellPaneLayout.double,
      );
      // 列表栏变宽同理：1100-220-400=480 < 560。
      expect(
        resolvePaneLayout(1100, sourcePaneWidth: 220, listPaneWidth: 400),
        ShellPaneLayout.double,
      );
    });

    test('刚好满足余量时为三栏（1100-220-300 = 580）', () {
      expect(
        resolvePaneLayout(
          1080,
          sourcePaneWidth: 220,
          listPaneWidth: 300,
          bodyPaneMin: 560,
        ),
        ShellPaneLayout.double,
        reason: '1080 未达 1100 断点',
      );
      expect(
        resolvePaneLayout(
          1100,
          sourcePaneWidth: 220,
          listPaneWidth: 320,
          bodyPaneMin: 560,
        ),
        ShellPaneLayout.triple,
        reason: '1100-220-320 = 560，恰好等于下界，应视为满足',
      );
    });
  });

  group('双栏来源栏宽度', () {
    test('单栏时不占用来源栏', () {
      expect(resolveSourcePaneWidth(500), 0);
    });

    test('常规宽度取 240 上界', () {
      expect(resolveSourcePaneWidth(900), FluxBreakpoints.sourcePaneMax);
    });

    test('极窄双栏时按三分之一压缩，避免把列表挤没', () {
      // 600 内容宽：三分之一为 200，小于 240 上界。
      expect(resolveSourcePaneWidth(600), closeTo(200, 1e-9));
    });
  });
}
