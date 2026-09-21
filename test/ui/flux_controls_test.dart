// 共享控件状态与语义测试（T012 验收：八类状态 + 焦点 + 触控目标 + 语义标签）。
//
// 为什么用断言而不是逐状态截图：
//   手册 T012 明确「测试用 widget test 断言状态与回调，不逐个截图」。原因是截图
//   只能证明「某一时刻像素长这样」，无法证明「悬停时回调没被触发」「禁用时读屏仍
//   报告可点」这类**行为**；而这些恰恰是真实缺陷的所在。视觉证据由
//   test/ui/golden/controls_golden_test.dart 的精选组合提供。
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/ui/ui.dart';

import 'control_harness.dart';

void main() {
  group('状态解析（八类，纯函数）', () {
    test('优先级：禁用 > 反馈 > 按下 > 焦点 > 悬停 > 默认', () {
      // 禁用压过一切：这是权限事实，不能让「正在加载」把一个不可用控件画成可用。
      expect(
        resolveFluxControlStatus(
          enabled: false,
          hovered: true,
          pressed: true,
          focused: true,
          feedback: FluxControlFeedback.loading,
        ),
        FluxControlStatus.disabled,
      );
      // 反馈压过指针交互：手指还停在按钮上时不该把「正在发送」画成「悬停」。
      expect(
        resolveFluxControlStatus(
          enabled: true,
          hovered: true,
          pressed: true,
          focused: true,
          feedback: FluxControlFeedback.loading,
        ),
        FluxControlStatus.loading,
      );
      expect(
        resolveFluxControlStatus(
          enabled: true,
          hovered: true,
          pressed: true,
          focused: true,
          feedback: FluxControlFeedback.success,
        ),
        FluxControlStatus.success,
      );
      expect(
        resolveFluxControlStatus(
          enabled: true,
          hovered: true,
          pressed: true,
          focused: true,
          feedback: FluxControlFeedback.error,
        ),
        FluxControlStatus.error,
      );
      expect(
        resolveFluxControlStatus(
          enabled: true,
          hovered: true,
          pressed: true,
          focused: true,
        ),
        FluxControlStatus.pressed,
      );
      expect(
        resolveFluxControlStatus(
          enabled: true,
          hovered: true,
          focused: true,
          pressed: false,
        ),
        FluxControlStatus.focus,
      );
      expect(
        resolveFluxControlStatus(
          enabled: true,
          hovered: true,
          pressed: false,
          focused: false,
        ),
        FluxControlStatus.hover,
      );
      expect(
        resolveFluxControlStatus(
          enabled: true,
          hovered: false,
          pressed: false,
          focused: false,
        ),
        FluxControlStatus.normal,
      );
    });

    test('只有禁用与加载拦截交互；只有禁用向读屏报告不可用', () {
      for (final FluxControlStatus status in <FluxControlStatus>[
        FluxControlStatus.disabled,
        FluxControlStatus.loading,
      ]) {
        expect(
          status.allowsInteraction,
          isFalse,
          reason: 'status=${status.name} 应当拦截交互',
        );
      }
      for (final FluxControlStatus status in FluxControlStatus.values) {
        if (status == FluxControlStatus.disabled ||
            status == FluxControlStatus.loading) {
          continue;
        }
        expect(
          status.allowsInteraction,
          isTrue,
          reason: 'status=${status.name} 不应拦截交互',
        );
      }
      expect(FluxControlStatus.disabled.reportsDisabled, isTrue);
      for (final FluxControlStatus status in FluxControlStatus.values) {
        if (status == FluxControlStatus.disabled) {
          continue;
        }
        expect(status.reportsDisabled, isFalse);
      }
    });

    test('八类状态解析出的视觉取值各不相同（不会有两个状态看着一样）', () {
      for (final ThemeData theme in <ThemeData>[
        ThemeData.light(),
        ThemeData.dark(),
      ]) {
        final Map<String, String> signatures = <String, String>{};
        for (final FluxControlStatus status in FluxControlStatus.values) {
          final FluxControlVisuals visuals = FluxControlVisuals.resolve(
            status: status,
            scheme: theme.colorScheme,
          );
          // 用「前景/底色/边框/不透明/是否焦点环/是否指示器」组合成签名：
          // 任何两项完全相同就意味着用户分不清这两个状态。
          final String signature = <Object>[
            visuals.foreground,
            visuals.background,
            visuals.border,
            visuals.opacity,
            visuals.showsFocusRing,
            visuals.showsIndicator,
          ].join('|');
          for (final MapEntry<String, String> other in signatures.entries) {
            expect(
              signature,
              isNot(other.value),
              reason: '${status.name} 与 ${other.key} 的视觉完全相同',
            );
          }
          signatures[status.name] = signature;
        }
        expect(signatures, hasLength(8));
      }
    });

    test('焦点状态有焦点环，其余状态没有（键盘用户必须能定位）', () {
      for (final FluxControlStatus status in FluxControlStatus.values) {
        final FluxControlVisuals visuals = FluxControlVisuals.resolve(
          status: status,
          scheme: ThemeData.light().colorScheme,
        );
        expect(
          visuals.showsFocusRing,
          status == FluxControlStatus.focus,
          reason: 'status=${status.name} 的焦点环不符合预期',
        );
      }
    });

    test('加载状态显示指示器，其余不显示', () {
      for (final FluxControlStatus status in FluxControlStatus.values) {
        final FluxControlVisuals visuals = FluxControlVisuals.resolve(
          status: status,
          scheme: ThemeData.light().colorScheme,
        );
        expect(
          visuals.showsIndicator,
          status == FluxControlStatus.loading,
          reason: 'status=${status.name} 的指示器不符合预期',
        );
      }
    });
  });

  group('三态控件的状态与回调（ReadingStateControl）', () {
    testWidgets('默认态可点，点按推进到下一个状态', (WidgetTester tester) async {
      ReadingState? switched;
      await tester.pumpWidget(
        wrapControl(
          ReadingStateControl(
            state: ReadingState.unread,
            onChanged: (ReadingState value) => switched = value,
          ),
        ),
      );
      await tester.tap(find.byType(ReadingStateControl));
      await tester.pump();
      expect(switched, ReadingState.read);
    });

    testWidgets('悬停与默认视觉不同（桌面 hover 必须可见）', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapControl(
          ReadingStateControl(state: ReadingState.unread, onChanged: (_) {}),
        ),
      );
      final Color before = _tapDecoration(tester).color!;
      await hoverOver(tester, find.byType(ReadingStateControl));
      final Color after = _tapDecoration(tester).color!;
      expect(after, isNot(before), reason: '悬停没有产生视觉变化');
      expect(
        after.a,
        closeTo(FluxControlTokens.hoverOverlayOpacity, 0.01),
        reason: '悬停底色应使用 hover token 的不透明度',
      );
    });

    testWidgets('按下时回调仍未触发，抬起才触发（避免误触）', (WidgetTester tester) async {
      int calls = 0;
      await tester.pumpWidget(
        wrapControl(
          ReadingStateControl(
            state: ReadingState.unread,
            onChanged: (_) => calls++,
          ),
        ),
      );
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(ReadingStateControl)),
      );
      await tester.pump();
      expect(calls, 0, reason: '按下不应立即触发回调');
      await gesture.up();
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('按下态底色比悬停更深（点击反馈必须明显）', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapControl(
          ReadingStateControl(state: ReadingState.unread, onChanged: (_) {}),
        ),
      );
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(ReadingStateControl)),
      );
      // AnimatedContainer 有 160ms 过渡：只 pump 一帧读到的是动画起点（仍是
      // 默认底色），必须把动画推完才能观察到按下态的稳态颜色。
      await tester.pump(const Duration(milliseconds: 200));
      final double pressedAlpha = _tapDecoration(tester).color!.a;
      await gesture.up();
      await tester.pump();
      expect(
        pressedAlpha,
        closeTo(FluxControlTokens.pressedOverlayOpacity, 0.01),
      );
      expect(
        pressedAlpha,
        greaterThan(FluxControlTokens.hoverOverlayOpacity),
        reason: '按下的不强于悬停时，用户感觉不到点击被接受',
      );
    });

    testWidgets('键盘 Tab 可聚焦，回车推进状态（桌面键盘可用）', (WidgetTester tester) async {
      ReadingState? switched;
      await tester.pumpWidget(
        wrapControl(
          ReadingStateControl(
            state: ReadingState.later,
            onChanged: (ReadingState value) => switched = value,
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_tapDecoration(tester).border, isNotNull, reason: '获得焦点后必须出现焦点环');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      // later 的下一个是 unread（循环），证明循环顺序不是单向递增。
      expect(switched, ReadingState.unread);
    });

    testWidgets('空格同样触发（两种桌面习惯都支持）', (WidgetTester tester) async {
      int calls = 0;
      await tester.pumpWidget(
        wrapControl(
          ReadingStateControl(
            state: ReadingState.read,
            onChanged: (_) => calls++,
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('禁用态：不触发回调，且向读屏报告不可用', (WidgetTester tester) async {
      int calls = 0;
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrapControl(
          ReadingStateControl(
            state: ReadingState.unread,
            enabled: false,
            onChanged: (_) => calls++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ReadingStateControl), warnIfMissed: false);
      await tester.pump();
      expect(calls, 0, reason: '禁用后仍能触发回调是真实缺陷');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, 0, reason: '禁用后键盘也不得触发');

      final SemanticsNode node = _semanticsNode(tester, RegExp('阅读状态'));
      // Flutter 3.47 用 SemanticsFlags 结构体表达能力状态（旧的 hasFlag 位掩码已
      // 弃用）：isEnabled 是三态，isFalse 表示「明确报告为不可用」，而不是「未指定」。
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('禁用态视觉降低不透明度（不能看起来和可用时一样）', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapControl(
          const ReadingStateControl(state: ReadingState.unread, enabled: false),
        ),
      );
      final double opacity = tester
          .widget<Opacity>(
            find.descendant(
              of: find.byType(ReadingStateControl),
              matching: find.byType(Opacity),
            ),
          )
          .opacity;
      expect(opacity, closeTo(FluxControlTokens.disabledOpacity, 0.001));
    });

    testWidgets('加载态：显示加载指示器并拦截重复触发', (WidgetTester tester) async {
      int calls = 0;
      await tester.pumpWidget(
        wrapControl(
          ReadingStateControl(
            state: ReadingState.unread,
            feedback: FluxControlFeedback.loading,
            onChanged: (_) => calls++,
          ),
        ),
      );
      expect(
        find.byType(FluxLoadingIndicator),
        findsOneWidget,
        reason: '加载态必须显示指示器',
      );
      expect(find.byType(FluxSvgIcon), findsNothing, reason: '加载态应替换图标而不是叠加');
      await tester.tap(find.byType(ReadingStateControl), warnIfMissed: false);
      await tester.pump();
      expect(calls, 0, reason: '加载中重复点击会产生重复请求');
    });

    testWidgets('成功与失败态：可继续交互，且失败用错误色', (WidgetTester tester) async {
      int calls = 0;
      await tester.pumpWidget(
        wrapControl(
          ReadingStateControl(
            state: ReadingState.read,
            feedback: FluxControlFeedback.error,
            onChanged: (_) => calls++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        _iconColor(tester),
        Theme.of(tester.element(find.byType(ReadingStateControl)))
            .colorScheme
            .error,
        reason: '失败态必须用错误色，否则用户看不出失败',
      );
      await tester.tap(find.byType(ReadingStateControl));
      await tester.pump();
      expect(calls, 1, reason: '失败后必须允许重试');

      await tester.pumpWidget(
        wrapControl(
          ReadingStateControl(
            state: ReadingState.read,
            feedback: FluxControlFeedback.success,
            onChanged: (_) => calls++,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        _iconColor(tester),
        Theme.of(tester.element(find.byType(ReadingStateControl)))
            .colorScheme
            .primary,
        reason: '成功态用强调色反馈',
      );
    });

    testWidgets('三态各自渲染不同图标（不靠颜色区分状态）', (WidgetTester tester) async {
      for (final ReadingState state in ReadingState.values) {
        await tester.pumpWidget(
          wrapControl(ReadingStateControl(state: state, onChanged: (_) {})),
        );
        await tester.pumpAndSettle();
        final SvgPicture icon = tester.widget<SvgPicture>(
          find.byType(SvgPicture),
        );
        final String path = (icon.bytesLoader as SvgAssetLoader).assetName;
        expect(path, readingStateIcon(state).assetPath(FluxIconSize.regular));
      }
      // 三个状态必须是三条不同路径。
      final Set<String> paths = <String>{
        for (final ReadingState state in ReadingState.values)
          readingStateIcon(state).assetPath(FluxIconSize.regular),
      };
      expect(paths, hasLength(3));
    });
  });

  group('三态语义与循环规则', () {
    test('循环顺序是未读 → 已读 → 稍后再读 → 未读', () {
      expect(readingStateCycle, <ReadingState>[
        ReadingState.unread,
        ReadingState.read,
        ReadingState.later,
      ]);
      expect(nextReadingState(ReadingState.unread), ReadingState.read);
      expect(nextReadingState(ReadingState.read), ReadingState.later);
      expect(nextReadingState(ReadingState.later), ReadingState.unread);
    });

    test('循环覆盖全部三个取值且回到起点（不会漏掉某个状态）', () {
      final Set<ReadingState> visited = <ReadingState>{};
      ReadingState current = ReadingState.unread;
      for (int i = 0; i < 3; i++) {
        visited.add(current);
        current = nextReadingState(current);
      }
      expect(visited, ReadingState.values.toSet());
      expect(current, ReadingState.unread, reason: '三步后必须回到起点');
    });

    testWidgets('语义标签包含控件名与当前值，且有循环提示', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrapControl(
          ReadingStateControl(state: ReadingState.later, onChanged: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      final SemanticsNode node = _semanticsNode(tester, RegExp('阅读状态'));
      expect(node.label, contains('阅读状态'));
      expect(node.label, contains('稍后再读'));
      expect(node.hint, contains('循环'));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('未给回调时是只读展示态：读屏不报告可点', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrapControl(const ReadingStateControl(state: ReadingState.read)),
      );
      await tester.pumpAndSettle();
      final SemanticsNode node = _semanticsNode(tester, RegExp('阅读状态'));
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });

    testWidgets('通过语义的 tap 动作也能切换（读屏用户用双击）', (WidgetTester tester) async {
      ReadingState? switched;
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrapControl(
          ReadingStateControl(
            state: ReadingState.unread,
            onChanged: (ReadingState value) => switched = value,
          ),
        ),
      );
      // 走「读屏双击」的真实路径：用 semantics 控制器派发 tap 动作，
      // 而不是直接调用 widget 的回调。
      await tester.pumpAndSettle();
      tester.semantics.performAction(
        find.semantics.byLabel(RegExp('阅读状态')),
        SemanticsAction.tap,
      );
      await tester.pump();
      expect(switched, ReadingState.read);
      handle.dispose();
    });
  });

  group('触控目标（架构第 7 节：至少 48dp）', () {
    testWidgets('图标只有 20/24，但命中区域是 48', (WidgetTester tester) async {
      for (final FluxIconSize size in FluxIconSize.values) {
        await tester.pumpWidget(
          wrapControl(
            ReadingStateControl(
              state: ReadingState.unread,
              size: size,
              onChanged: (_) {},
            ),
          ),
        );
        final Size tapSize = tester.getSize(find.byType(ReadingStateControl));
        expect(
          tapSize.width,
          greaterThanOrEqualTo(FluxIconTokens.minTouchTarget),
        );
        expect(
          tapSize.height,
          greaterThanOrEqualTo(FluxIconTokens.minTouchTarget),
        );
      }
    });

    testWidgets('两种尺寸下图标本身仍然是 20 / 24', (WidgetTester tester) async {
      for (final FluxIconSize size in FluxIconSize.values) {
        await tester.pumpWidget(
          wrapControl(
            ReadingStateControl(
              state: ReadingState.unread,
              size: size,
              onChanged: (_) {},
            ),
          ),
        );
        final SvgPicture icon = tester.widget<SvgPicture>(
          find.byType(SvgPicture),
        );
        expect(icon.width, size.logicalSize);
        expect(icon.height, size.logicalSize);
      }
    });
  });

  group('收藏开关（FavoriteToggle，独立于三态）', () {
    testWidgets('点按切换布尔值，方向由当前值决定', (WidgetTester tester) async {
      bool? switched;
      await tester.pumpWidget(
        wrapControl(
          FavoriteToggle(favorite: false, onChanged: (bool v) => switched = v),
        ),
      );
      await tester.tap(find.byType(FavoriteToggle));
      await tester.pump();
      expect(switched, isTrue, reason: '未收藏时应改为收藏');

      switched = null;
      await tester.pumpWidget(
        wrapControl(
          FavoriteToggle(favorite: true, onChanged: (bool v) => switched = v),
        ),
      );
      await tester.tap(find.byType(FavoriteToggle));
      await tester.pump();
      expect(switched, isFalse, reason: '已收藏时应取消收藏');
    });

    testWidgets('已收藏用实心星形，未收藏用描边星形', (WidgetTester tester) async {
      for (final bool favorite in <bool>[false, true]) {
        await tester.pumpWidget(
          wrapControl(FavoriteToggle(favorite: favorite, onChanged: (_) {})),
        );
        await tester.pumpAndSettle();
        final SvgPicture icon = tester.widget<SvgPicture>(
          find.byType(SvgPicture),
        );
        final String path = (icon.bytesLoader as SvgAssetLoader).assetName;
        expect(
          path,
          (favorite ? FluxIcon.starFilled : FluxIcon.star).assetPath(
            FluxIconSize.regular,
          ),
        );
      }
    });

    testWidgets('语义标签说明当前动作，不报告三态', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrapControl(FavoriteToggle(favorite: false, onChanged: (_) {})),
      );
      await tester.pumpAndSettle();
      final SemanticsNode node = _semanticsNode(tester, RegExp('收藏'));
      expect(node.label, contains('收藏'));
      expect(node.label, contains('加入收藏'));
      expect(node.label, isNot(contains('阅读状态')), reason: '收藏控件不得暗示自己会改变阅读状态');
      handle.dispose();
    });

    testWidgets('禁用与加载同样被拦截', (WidgetTester tester) async {
      int calls = 0;
      await tester.pumpWidget(
        wrapControl(
          FavoriteToggle(
            favorite: false,
            enabled: false,
            onChanged: (_) => calls++,
          ),
        ),
      );
      await tester.tap(find.byType(FavoriteToggle), warnIfMissed: false);
      await tester.pump();
      expect(calls, 0);

      await tester.pumpWidget(
        wrapControl(
          FavoriteToggle(
            favorite: false,
            feedback: FluxControlFeedback.loading,
            onChanged: (_) => calls++,
          ),
        ),
      );
      await tester.tap(find.byType(FavoriteToggle), warnIfMissed: false);
      await tester.pump();
      expect(calls, 0);
    });
  });

  group('加精徽标（与收藏区分）', () {
    testWidgets('用盾形图标而不是星形，且不可交互', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapControl(const FeaturedBadge(showLabel: true)),
      );
      final SvgPicture icon = tester.widget<SvgPicture>(
        find.byType(SvgPicture),
      );
      final String path = (icon.bytesLoader as SvgAssetLoader).assetName;
      expect(path, contains('badge-featured'));
      expect(path, isNot(contains('star')), reason: '加精与收藏共用星形会让用户以为是同一件事');
      // ensureSemantics 必须在 pump 之前：语义树是 pump 时按当前开关状态构建的，
      // 先 pump 后开启会让查找落在一次没有语义树的帧上。
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pump();
      final SemanticsNode node = _semanticsNode(tester, '加精');
      expect(node.label, '加精');
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
        reason: '加精由订阅管理设置，列表里只做标记',
      );
      handle.dispose();
    });
  });
}

/// 取控件内部的状态底色容器装饰。
BoxDecoration _tapDecoration(WidgetTester tester) {
  final AnimatedContainer container = tester.widget<AnimatedContainer>(
    find
        .descendant(
          of: find.byType(FluxStatefulTap),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return container.decoration! as BoxDecoration;
}

/// 取控件图标的实际颜色（用于验证失败/成功态的用色）。
Color _iconColor(WidgetTester tester) {
  final SvgPicture icon = tester.widget<SvgPicture>(
    find
        .descendant(
          of: find.byType(FluxStatefulTap),
          matching: find.byType(SvgPicture),
        )
        .first,
  );
  // currentColor 由 FluxSvgIcon 写进 bytesLoader 的 SvgTheme，而不是 SvgPicture
  // 自身的字段。
  // FluxSvgIcon 一定传入 SvgTheme（见其 build），因此这里的 theme 非空。
  return (icon.bytesLoader as SvgAssetLoader).theme!.currentColor;
}

/// 按语义标签取节点。
///
/// 为什么按标签而不是按 widget 类型取：控件内部还有 Tooltip、Opacity 等会顺带
/// 产生语义节点的包装，`find.byType(...)` 取第一个拿到的可能是空节点（读出的标签
/// 是空串），那看起来像「读屏标签没生效」，实际是测试定位错了对象。
/// 语义树里控件的标签是唯一的，按它定位才与「读屏用户实际听到什么」一致。
SemanticsNode _semanticsNode(WidgetTester tester, Pattern label) =>
    find.semantics.byLabel(label).evaluate().single;
