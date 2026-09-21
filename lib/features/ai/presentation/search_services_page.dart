// 设置 → 搜索服务页（T031；SET-038/039/040/041，SET-042 的搜索测试动作）。
//
// 这一页存在的理由是「让搜索配置真的可核对」，与 AI 服务页同一组要求：
//   - 列表按**服务选择顺序**展示，顺序可以调（SET-038 的排序）；
//   - 每条显示协议、端点、结果数/超时与凭据状态（凭据只显示状态，不回显）；
//   - 删除会先算引用并要求确认（引用不悬空）；
//   - 测试按钮先弹**费用与数据发送**确认，再发一次真实检索。
//
// 两个与 AI 服务页**不同**的界面事实，都来自搜索协议本身：
//   1) **没有凭据就不给点测试**：Tavily/Brave 没有 Key 必然 401，让按钮可点只会
//      换来一次无意义的失败；SearXNG 不要求凭据，因此它的按钮正常可用。
//   2) **私网端点要显式批准**（SET-041）：自建 SearXNG 常挂在局域网，勾选后才放行；
//      未勾选时界面直接说明「会被地址守卫拒绝」，而不是等请求失败才知道。
//
// 本页**不**做「看起来能用」的事：查询关键词列表（SET-052）、禁止查询词（SET-053）
// 与每日新闻的检索编排（T036/T037）都会在页面底部明确标注归属，而不是放一个无效开关。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';

import '../application/model_manager_controller.dart' show AiFailureReason;
import '../application/search_manager.dart';
import '../application/search_manager_controller.dart';
import '../domain/search_service.dart';
import 'ai_failure_text.dart';
import 'search_service_form.dart';

/// 搜索服务页。
class SearchServicesPage extends ConsumerWidget {
  /// 构造页面。
  const SearchServicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<SearchServicesState> state = ref.watch(
      searchManagerControllerProvider,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.searchPageTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_openForm(context, ref, null)),
        icon: const Icon(Icons.add),
        label: Text(l10n.searchAddService),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // 读取异常（编程错误）：不是空白页，给出可核对的状态。
        error: (Object error, StackTrace stackTrace) => _Body(
          state: const SearchServicesState(
            services: <SearchService>[],
            loadFailure: AiFailureReason.unknown,
          ),
          onEdit: (SearchService service) =>
              unawaited(_openForm(context, ref, service)),
          onDelete: (SearchService service) =>
              unawaited(_confirmDelete(context, ref, service)),
          onToggle: (SearchService service, bool enabled) =>
              unawaited(_toggle(context, ref, service, enabled)),
          onMove: (SearchService service, int delta) =>
              unawaited(_move(context, ref, service, delta)),
          onSetDefault: (SearchService service, bool value) =>
              unawaited(_setDefault(context, ref, service, value)),
          onTest: (SearchService service) =>
              unawaited(_confirmAndTest(context, ref, service)),
          hasCredential: (String identifier) => ref
              .read(searchManagerControllerProvider.notifier)
              .hasCredential(identifier),
        ),
        data: (SearchServicesState value) => _Body(
          state: value,
          onEdit: (SearchService service) =>
              unawaited(_openForm(context, ref, service)),
          onDelete: (SearchService service) =>
              unawaited(_confirmDelete(context, ref, service)),
          onToggle: (SearchService service, bool enabled) =>
              unawaited(_toggle(context, ref, service, enabled)),
          onMove: (SearchService service, int delta) =>
              unawaited(_move(context, ref, service, delta)),
          onSetDefault: (SearchService service, bool value) =>
              unawaited(_setDefault(context, ref, service, value)),
          onTest: (SearchService service) =>
              unawaited(_confirmAndTest(context, ref, service)),
          hasCredential: (String identifier) => ref
              .read(searchManagerControllerProvider.notifier)
              .hasCredential(identifier),
        ),
      ),
    );
  }
}

/// 打开新增/编辑对话框。
Future<void> _openForm(
  BuildContext context,
  WidgetRef ref,
  SearchService? initial,
) async {
  final SearchManagerController controller = ref.read(
    searchManagerControllerProvider.notifier,
  );
  final SearchServicesState? current = ref
      .read(searchManagerControllerProvider)
      .value;
  await showSearchServiceForm(
    context: context,
    initial: initial,
    credentialStoreAvailable: current?.credentialStoreAvailable ?? true,
    hasCredential: controller.hasCredential,
    saveCredential: controller.saveCredential,
    deleteCredential: controller.deleteCredential,
    onSave: controller.save,
    onTest: (SearchService service, SearchSendConfirmation confirmation) =>
        controller.test(service, confirmation: confirmation),
  );
}

/// 启用/停用。
Future<void> _toggle(
  BuildContext context,
  WidgetRef ref,
  SearchService service,
  bool enabled,
) async {
  final Result<SearchService> result = await ref
      .read(searchManagerControllerProvider.notifier)
      .setEnabled(service, enabled);
  if (result.isErr && context.mounted) {
    _showFailure(context, result.errorOrNull!);
  }
}

/// 调整服务选择顺序（delta 为 -1 上移、+1 下移）。
Future<void> _move(
  BuildContext context,
  WidgetRef ref,
  SearchService service,
  int delta,
) async {
  final SearchServicesState? state = ref
      .read(searchManagerControllerProvider)
      .value;
  if (state == null) {
    return;
  }
  final List<SearchService> services = List<SearchService>.of(state.services);
  final int index = services.indexWhere(
    (SearchService candidate) => candidate.id == service.id,
  );
  final int target = index + delta;
  if (index < 0 || target < 0 || target >= services.length) {
    return;
  }
  // 交换后整体提交：顺序是一次整体事实，只改两条记录的序号会在中途失败时留下
  // 「两条相同序号」的状态。
  final SearchService moved = services.removeAt(index);
  services.insert(target, moved);
  final Result<void> result = await ref
      .read(searchManagerControllerProvider.notifier)
      .reorder(
        services.map((SearchService s) => s.id!).toList(growable: false),
      );
  if (result.isErr && context.mounted) {
    _showFailure(context, result.errorOrNull!);
  }
}

/// 设为/取消任务默认搜索服务。
Future<void> _setDefault(
  BuildContext context,
  WidgetRef ref,
  SearchService service,
  bool value,
) async {
  final int? id = service.id;
  if (id == null) {
    return;
  }
  final Result<void> result = await ref
      .read(searchManagerControllerProvider.notifier)
      .setDefaultForTasks(id, isDefault: value);
  if (result.isErr && context.mounted) {
    _showFailure(context, result.errorOrNull!);
  }
}

/// 删除前先算引用并要求确认。
Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  SearchService service,
) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final SearchManagerController controller = ref.read(
    searchManagerControllerProvider.notifier,
  );
  final Result<List<String>> references = await controller.describeReferences(
    service,
  );
  if (!context.mounted) {
    return;
  }
  if (references.isErr) {
    // 引用读不出来时**不**放行删除：那会把「没查到」当成「没有引用」，
    // 静默地允许一次会让配置悬空的删除。
    _showFailure(
      context,
      references.errorOrNull!,
      wrap: l10n.searchDeleteFailed,
    );
    return;
  }
  final List<String> list = references.valueOrNull!;
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(l10n.searchDeleteConfirmTitle(service.label)),
      content: Text(
        list.isEmpty
            ? l10n.searchDeleteConfirmBody
            : '${l10n.searchDeleteConfirmBody}\n\n'
                  '${l10n.searchDeleteInUseBody(list.join('、'))}',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.searchDeleteCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.searchDeleteConfirmYes),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  // 已经展示过引用并且用户确认，因此带 force。
  final Result<void> deleted = await controller.delete(service, force: true);
  if (deleted.isErr && context.mounted) {
    _showFailure(context, deleted.errorOrNull!, wrap: l10n.searchDeleteFailed);
  }
}

/// 弹「费用与数据发送」确认，确认后发一次真实检索。
///
/// 确认框里写清两件事（SET-042 的口径）：
///   - **查询词会离开设备**，发送到哪个端点（用户需要知道数据去向）；
///   - 这次调用**可能产生费用**（Tavily/Brave 均按调用计费）。
Future<void> _confirmAndTest(
  BuildContext context,
  WidgetRef ref,
  SearchService service,
) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(l10n.searchTestConfirmTitle),
      content: Text(
        l10n.searchTestConfirmBody(
          service.protocol.label,
          service.endpoint.toString(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.searchTestConfirmCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.searchTestConfirmYes),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  final Result<SearchTestReport> report = await ref
      .read(searchManagerControllerProvider.notifier)
      .test(
        service,
        confirmation: SearchSendConfirmation(
          acknowledgedAtUtc: DateTime.now().toUtc(),
        ),
      );
  if (!context.mounted) {
    return;
  }
  if (report.isErr) {
    _showFailure(context, report.errorOrNull!);
    return;
  }
  final SearchTestReport value = report.unwrap();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        l10n.searchTestSuccess(value.elapsed.inMilliseconds, value.resultCount),
      ),
    ),
  );
}

void _showFailure(
  BuildContext context,
  AppError error, {
  String Function(String reason)? wrap,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  // ModelInUseError 的文案里带引用清单，因此单独走一条（与 AI 侧同一处理）。
  if (error is ModelInUseError) {
    final String text = l10n.searchDeleteInUseBody(
      error.referenceDescriptions.join('、'),
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    return;
  }
  final String described = describeAiFailure(
    l10n,
    AiFailureReason.classify(error),
    detail: error.message,
  );
  final String text = wrap == null ? described : wrap(described);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// 页面正文。
class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onMove,
    required this.onSetDefault,
    required this.onTest,
    required this.hasCredential,
  });

  final SearchServicesState state;
  final ValueChanged<SearchService> onEdit;
  final ValueChanged<SearchService> onDelete;
  final void Function(SearchService service, bool enabled) onToggle;
  final void Function(SearchService service, int delta) onMove;
  final void Function(SearchService service, bool value) onSetDefault;
  final ValueChanged<SearchService> onTest;
  final Future<bool> Function(String identifier) hasCredential;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        FluxSpacing.md,
        FluxSpacing.md,
        FluxSpacing.md,
        FluxSpacing.xxl,
      ),
      children: <Widget>[
        if (state.loadFailure != null)
          _Banner(
            text: l10n.searchLoadFailed(
              describeAiFailure(l10n, state.loadFailure!),
            ),
            isError: true,
          ),
        if (!state.credentialStoreAvailable)
          _Banner(text: l10n.aiApiKeyUnavailable, isError: false),
        if (state.services.isEmpty && state.loadFailure == null)
          _Banner(text: l10n.searchEmptyNotice, isError: false),
        Text(l10n.searchServicesSection, style: theme.textTheme.titleSmall),
        const SizedBox(height: FluxSpacing.xxs),
        Text(l10n.searchSortHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: FluxSpacing.sm),
        for (int index = 0; index < state.services.length; index++)
          _ServiceCard(
            service: state.services[index],
            // 凭据变更计数参与 key：保存/删除凭据后卡片会被重建，从而重新查询
            // 「这个服务有没有 Key」（凭据不在记录里，见 SearchServicesState 的说明）。
            key: ValueKey<String>(
              '${state.services[index].id}-${state.credentialEpoch}',
            ),
            canMoveUp: index > 0,
            canMoveDown: index < state.services.length - 1,
            onEdit: () => onEdit(state.services[index]),
            onDelete: () => onDelete(state.services[index]),
            onToggle: (bool enabled) =>
                onToggle(state.services[index], enabled),
            onMoveUp: () => onMove(state.services[index], -1),
            onMoveDown: () => onMove(state.services[index], 1),
            onSetDefault: (bool value) =>
                onSetDefault(state.services[index], value),
            onTest: () => onTest(state.services[index]),
            hasCredential: hasCredential,
          ),
        const SizedBox(height: FluxSpacing.md),
        Text(l10n.searchPlannedNotice, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// 一条搜索服务记录的卡片。
class _ServiceCard extends StatefulWidget {
  const _ServiceCard({
    super.key,
    required this.service,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onSetDefault,
    required this.onTest,
    required this.hasCredential,
  });

  final SearchService service;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final ValueChanged<bool> onSetDefault;
  final VoidCallback onTest;
  final Future<bool> Function(String identifier) hasCredential;

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  bool? _hasCredential;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshCredentialState());
  }

  @override
  void didUpdateWidget(_ServiceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service.credentialIdentifier !=
        widget.service.credentialIdentifier) {
      unawaited(_refreshCredentialState());
    }
  }

  Future<void> _refreshCredentialState() async {
    final bool present = await widget.hasCredential(
      widget.service.credentialIdentifier,
    );
    if (mounted) {
      setState(() => _hasCredential = present);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final SearchService service = widget.service;
    // 「可以测试」的判据 = 协议不要求凭据 **或** 凭据已配置。
    // 无凭据时按钮禁用并给出原因，而不是让用户点一次换来必然的 401。
    final bool credentialReady =
        !service.protocol.requiresCredential || (_hasCredential ?? false);
    return Card(
      margin: const EdgeInsets.only(bottom: FluxSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(FluxSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    service.label,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (service.isDefaultForTasks)
                  Padding(
                    padding: const EdgeInsets.only(right: FluxSpacing.xs),
                    child: Chip(
                      label: Text(l10n.searchDefaultBadge),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                IconButton(
                  tooltip: l10n.aiMoveUp,
                  onPressed: widget.canMoveUp ? widget.onMoveUp : null,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                IconButton(
                  tooltip: l10n.aiMoveDown,
                  onPressed: widget.canMoveDown ? widget.onMoveDown : null,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                ),
              ],
            ),
            Text(service.protocol.label, style: theme.textTheme.bodyMedium),
            // 端点地址原样展示：它不含凭据（凭据在 Keychain），用户需要核对地址。
            Text(service.endpoint.toString(), style: theme.textTheme.bodySmall),
            const SizedBox(height: FluxSpacing.xxs),
            Text(
              l10n.searchBudgetHint(service.maxResults, service.timeoutSeconds),
              style: theme.textTheme.labelSmall,
            ),
            if (service.allowPrivateEndpoint)
              Text(
                l10n.searchPrivateApproved,
                style: theme.textTheme.labelSmall,
              ),
            if (service.protocol.requiresCredential &&
                !(_hasCredential ?? false))
              Text(
                l10n.searchCredentialMissingHint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.error,
                ),
              ),
            const SizedBox(height: FluxSpacing.xxs),
            Row(
              children: <Widget>[
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: service.enabled,
                    onChanged: widget.onToggle,
                    title: Text(
                      l10n.aiEnabledLabel,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: service.isDefaultForTasks,
                    onChanged: widget.onSetDefault,
                    title: Text(
                      l10n.searchDefaultLabel,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 无凭据时按钮**禁用**并提示原因（见下方 tooltip 与卡片上的
                  // 提示行）：Tavily/Brave 没有 Key 必然 401，让按钮可点只会换来
                  // 一次无意义的失败。SearXNG 不要求凭据，因此它始终可点。
                  Tooltip(
                    message: credentialReady
                        ? l10n.searchTestButton
                        : l10n.searchTestDisabledNoCredential,
                    child: TextButton(
                      onPressed: credentialReady ? widget.onTest : null,
                      child: Text(l10n.searchTestButton),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onEdit,
                    child: Text(l10n.aiEditModel),
                  ),
                  TextButton(
                    onPressed: widget.onDelete,
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                    child: Text(l10n.aiDeleteModel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一段说明/错误条。
class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: FluxSpacing.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(FluxSpacing.sm),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(FluxRadius.card),
          border: Border.all(color: isError ? colors.error : colors.outline),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: isError ? colors.error : colors.onSurface),
        ),
      ),
    );
  }
}
