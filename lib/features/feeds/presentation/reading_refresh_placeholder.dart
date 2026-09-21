// RSS 去向的刷新接线（T016）。
//
// 为什么 T016 要动这个页面：架构 4.1 的刷新调度如果没有任何可见入口，用户无法
// 判断它是否在工作——而「按钮点了没反应」与「后台默默跑了」在界面上长得一样。
// T016 因此在 RSS 去向提供一个**真实的**手动刷新按钮，以及一个真实的数据体现
// （订阅的未读文章计数），证明刷新链路确实通到了库里。
//
// 范围边界：文章列表、三态、收藏、筛选与批量操作属 T017，因此这里**不**画列表、
// 也不假装有筛选；它只显示「有多少篇未读」这一个来自数据库的真实数字，并明确
// 说明列表属 T017。T017 会用真正的阅读页替换本文件的使用点。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/feeds/application/feed_ports.dart';
import 'package:flux/features/feeds/application/refresh_providers.dart';
import 'package:flux/features/feeds/presentation/refresh_outcome_text.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

/// RSS 去向的刷新接线页。
class ReadingRefreshPlaceholder extends ConsumerWidget {
  /// 构造页面。
  const ReadingRefreshPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<RefreshStatus> refresh = ref.watch(
      refreshControllerProvider,
    );
    final bool running = refresh.value?.running ?? false;
    final AsyncValue<int> unread = ref.watch(unreadCountProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FluxSpacing.md,
            vertical: FluxSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              FilledButton.icon(
                onPressed: running ? null : () => _refresh(context, ref),
                icon: running
                    ? const FluxLoadingIndicator(size: 16)
                    : const Icon(Icons.refresh, size: 18),
                label: Text(
                  running ? l10n.readingRefreshing : l10n.readingRefresh,
                ),
              ),
              const SizedBox(width: FluxSpacing.md),
              Expanded(
                child: unread.when(
                  loading: () => Text(
                    l10n.readingPlaceholderCounting,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  error: (Object error, StackTrace stackTrace) => Text(
                    l10n.readingPlaceholderCountFailed,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  data: (int count) => Text(
                    l10n.readingPlaceholderUnread(count),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FluxEmptyState(
            title: l10n.navReading,
            body: l10n.readingPlaceholderBody,
            secondaryNote: l10n.placeholderPageBody('T017–T019'),
          ),
        ),
      ],
    );
  }

  /// 手动刷新并如实提示结果。
  static Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final RefreshStatus status = await ref
        .read(refreshControllerProvider.notifier)
        .refreshNow();
    if (!context.mounted) {
      return;
    }
    final String message = describeRefreshOutcome(
      AppLocalizations.of(context),
      status,
    );
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
    // 刷新可能写入了新文章，未读数要跟着变，而不是等用户切页重进。
    ref.invalidate(unreadCountProvider);
  }
}

/// 全部订阅的未读文章总数。
///
/// 用订阅端口已有的 unreadCounts 聚合（T014 交付），而不是新开一条查询路径：
/// 「未读」的口径已经在那里定义好了（只算 reading_state = 'unread'，不含 later），
/// 这里再写一遍会多出一个可能漂移的定义。
final FutureProvider<int> unreadCountProvider = FutureProvider<int>((
  Ref ref,
) async {
  final Result<Map<int, int>> counts = await ref
      .watch(feedCatalogProvider)
      .unreadCounts();
  if (counts.isErr) {
    throw counts.errorOrNull!;
  }
  return counts.valueOrNull!.values.fold<int>(
    0,
    (int sum, int value) => sum + value,
  );
});
