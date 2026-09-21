// 应用壳（T011）：导航、响应式布局与启动状态。
//
// 三个职责，按可测试性拆开：
//   1) 导航模式（侧边 NavigationRail / 底部 NavigationBar）由**窗口逻辑宽度**
//      决定，断点 600（架构第 7 节）；
//   2) 内容区按断点呈现 1 / 2 / 3 栏占位结构；
//   3) 启动降级（数据库不可用）显示明确说明，而不是假装一切正常。
//
// 为什么用 LayoutBuilder 而不是 MediaQuery.sizeOf：桌面窗口可以被用户拖到任意
// 尺寸，LayoutBuilder 给的是**本组件实际可用宽度**（已扣掉侧边导航），与断点
// 的语义（内容区分栏）一致；MediaQuery 给的是整块屏幕/窗口宽度，在有侧栏时
// 会把 600 断点判早。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 把 StateProvider 归入 legacy 入口；它只是「一个可变值」，
// 语义上够用（当前去向），因此不为此引入 Notifier 样板。
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';

import '../app_providers.dart';
import '../theme/flux_theme.dart';
import 'app_destination.dart';
import 'placeholder_page.dart';

/// 当前选中的去向。
///
/// 用 StateProvider 而不是页面内 State：返回位置（架构第 7 节 SET-009 的
/// 「返回位置按页面保留」）在后续任务中需要跨页面重建保持，放在容器里能让
/// 它天然满足这一点。
final StateProvider<AppDestination> selectedDestinationProvider =
    StateProvider<AppDestination>((Ref ref) => AppDestination.today);

/// 应用壳。
class AppShell extends ConsumerWidget {
  /// 构造应用壳。
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppDestination selected = ref.watch(selectedDestinationProvider);
    final AppBootstrapStatus status = ref.watch(appBootstrapStatusProvider);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 导航位置按**整体窗口宽度**判断：侧栏本身占用宽度，若用内容区宽度判断，
        // 侧栏会在临界点附近与自己竞争空间，出现「切到侧栏后立刻又切回底栏」。
        final bool useRail = constraints.maxWidth >= FluxBreakpoints.twoColumn;
        return Scaffold(
          body: useRail
              ? Row(
                  children: <Widget>[
                    _ShellNavigationRail(selected: selected),
                    const VerticalDivider(width: 1),
                    Expanded(child: _ShellBody(status: status)),
                  ],
                )
              : _ShellBody(status: status),
          bottomNavigationBar: useRail
              ? null
              : NavigationBar(
                  selectedIndex: appDestinations.indexOf(selected),
                  onDestinationSelected: (int index) => _select(ref, index),
                  destinations: <Widget>[
                    for (final AppDestination destination in appDestinations)
                      NavigationDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: destination.label(AppLocalizations.of(context)),
                      ),
                  ],
                ),
        );
      },
    );
  }

  /// 切换去向。
  static void _select(WidgetRef ref, int index) {
    ref.read(selectedDestinationProvider.notifier).state =
        appDestinations[index];
  }
}

/// 侧边导航（宽窗）。
class _ShellNavigationRail extends ConsumerWidget {
  const _ShellNavigationRail({required this.selected});

  final AppDestination selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return NavigationRail(
      selectedIndex: appDestinations.indexOf(selected),
      onDestinationSelected: (int index) => AppShell._select(ref, index),
      // 三个去向都带文字标签：只有图标时用户无法确认「我的」里是设置，
      // 而架构第 3 节把该去向定义为「我的/设置」，标签是必要信息。
      labelType: NavigationRailLabelType.all,
      groupAlignment: -1,
      destinations: <NavigationRailDestination>[
        for (final AppDestination destination in appDestinations)
          NavigationRailDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon),
            label: Text(destination.label(l10n)),
          ),
      ],
    );
  }
}

/// 内容区：把当前去向渲染成页面，并在顶部保留壳层说明。
class _ShellBody extends ConsumerWidget {
  const _ShellBody({required this.status});

  final AppBootstrapStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppDestination selected = ref.watch(selectedDestinationProvider);
    return Column(
      children: <Widget>[
        if (status.degraded) const DegradedBanner(),
        Expanded(child: PlaceholderDestinationPage(destination: selected)),
      ],
    );
  }
}

/// 启动降级横幅：数据库不可用时明确说明「改动不会保存」。
class DegradedBanner extends StatelessWidget {
  /// 构造降级横幅。
  const DegradedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final FluxColors colors = FluxColors.of(context);
    return Material(
      // 用 surface 而不是 warning 作为底色：warning 色在白字/深字对比度上
      // 需要单独校准，而这里是长期可见的说明条，优先保证文字可读。
      color: colors.selectedSurface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FluxSpacing.md,
          vertical: FluxSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, size: 20, color: colors.warning),
            const SizedBox(width: FluxSpacing.xs),
            Expanded(
              child: Text(
                '${l10n.shellDatabaseFailedTitle}：${l10n.shellDatabaseFailedBody}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
