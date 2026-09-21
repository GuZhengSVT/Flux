// 设置 → AI 服务页（T025；SET-030/031/032/033）。
//
// 这一页存在的理由是「让 AI 配置真的可核对」：
//   - 列表按**故障转移顺序**展示，顺序可以调（SET-032/035 的排序）；
//   - 每条记录显示协议、模型 ID、能力、上限与凭据是否已配置（凭据只显示状态，不回显）；
//   - 未实现的协议在选择项里就标注「适配器待实现」，不让用户选完才发现；
//   - 删除会先算引用并要求确认（引用不悬空）；
//   - 测试按钮先弹费用确认，再发一次真实调用，成功后显示耗时与 token。
//
// 本页**不**做「看起来能用」的事：故障转移的五次无响应计数（T029）与自动摘要开关
// （SET-037/T034）都会在页面底部明确标注归后续任务，而不是放一个无效开关。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';

import '../application/model_manager.dart';
import '../application/model_manager_controller.dart';
import '../domain/ai_model.dart';
import '../domain/ai_model_references.dart';
import 'ai_failure_text.dart';
import 'ai_model_form.dart';

/// AI 服务页。
class AiServicesPage extends ConsumerWidget {
  /// 构造页面。
  const AiServicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<AiModelsState> state = ref.watch(
      modelManagerControllerProvider,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiPageTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_openForm(context, ref, null)),
        icon: const Icon(Icons.add),
        label: Text(l10n.aiAddModel),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // 读取异常（编程错误）：不是空白页，给出可核对的状态。
        error: (Object error, StackTrace stackTrace) => _Body(
          state: const AiModelsState(
            models: <AiModel>[],
            loadFailure: AiFailureReason.unknown,
          ),
          onEdit: (AiModel model) => unawaited(_openForm(context, ref, model)),
          onDelete: (AiModel model) =>
              unawaited(_confirmDelete(context, ref, model)),
          onToggle: (AiModel model, bool enabled) =>
              unawaited(_toggle(context, ref, model, enabled)),
          onMove: (AiModel model, int delta) =>
              unawaited(_move(context, ref, model, delta)),
          onSetDefault: (AiModel model, bool value) =>
              unawaited(_setDefault(context, ref, model, value)),
        ),
        data: (AiModelsState value) => _Body(
          state: value,
          onEdit: (AiModel model) => unawaited(_openForm(context, ref, model)),
          onDelete: (AiModel model) =>
              unawaited(_confirmDelete(context, ref, model)),
          onToggle: (AiModel model, bool enabled) =>
              unawaited(_toggle(context, ref, model, enabled)),
          onMove: (AiModel model, int delta) =>
              unawaited(_move(context, ref, model, delta)),
          onSetDefault: (AiModel model, bool value) =>
              unawaited(_setDefault(context, ref, model, value)),
        ),
      ),
    );
  }
}

/// 打开新增/编辑对话框。
Future<void> _openForm(
  BuildContext context,
  WidgetRef ref,
  AiModel? initial,
) async {
  final ModelManagerController controller = ref.read(
    modelManagerControllerProvider.notifier,
  );
  final AiModelsState? current = ref.read(modelManagerControllerProvider).value;
  await showAiModelForm(
    context: context,
    initial: initial,
    credentialStoreAvailable: current?.credentialStoreAvailable ?? true,
    hasCredential: controller.hasCredential,
    saveCredential: controller.saveCredential,
    deleteCredential: controller.deleteCredential,
    onSave: controller.save,
    onTest: (AiModel model, CostConfirmation confirmation) =>
        controller.test(model, confirmation: confirmation),
  );
}

/// 启用/停用。
Future<void> _toggle(
  BuildContext context,
  WidgetRef ref,
  AiModel model,
  bool enabled,
) async {
  final Result<AiModel> result = await ref
      .read(modelManagerControllerProvider.notifier)
      .setEnabled(model, enabled);
  if (result.isErr && context.mounted) {
    _showFailure(context, result.errorOrNull!);
  }
}

/// 调整故障转移顺序（delta 为 -1 上移、+1 下移）。
Future<void> _move(
  BuildContext context,
  WidgetRef ref,
  AiModel model,
  int delta,
) async {
  final AiModelsState? state = ref.read(modelManagerControllerProvider).value;
  if (state == null) {
    return;
  }
  final List<AiModel> models = List<AiModel>.of(state.models);
  final int index = models.indexWhere(
    (AiModel candidate) => candidate.id == model.id,
  );
  final int target = index + delta;
  if (index < 0 || target < 0 || target >= models.length) {
    return;
  }
  // 交换后整体提交：顺序是一次整体事实，只改两条记录的序号会在中途失败时留下
  // 「两条相同序号」的状态。
  final AiModel moved = models.removeAt(index);
  models.insert(target, moved);
  final Result<void> result = await ref
      .read(modelManagerControllerProvider.notifier)
      .reorder(
        models
            .map((AiModel candidate) => candidate.id!)
            .toList(growable: false),
      );
  if (result.isErr && context.mounted) {
    _showFailure(context, result.errorOrNull!);
  }
}

/// 设为/取消任务默认模型。
Future<void> _setDefault(
  BuildContext context,
  WidgetRef ref,
  AiModel model,
  bool value,
) async {
  final int? id = model.id;
  if (id == null) {
    return;
  }
  final Result<void> result = await ref
      .read(modelManagerControllerProvider.notifier)
      .setDefaultForTasks(id, isDefault: value);
  if (result.isErr && context.mounted) {
    _showFailure(context, result.errorOrNull!);
  }
}

/// 删除前先算引用并要求确认。
Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  AiModel model,
) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final ModelManagerController controller = ref.read(
    modelManagerControllerProvider.notifier,
  );
  final Result<List<ModelReference>> references = await controller
      .describeReferences(model);
  if (!context.mounted) {
    return;
  }
  if (references.isErr) {
    // 引用读不出来时**不**放行删除：那会把「没查到」当成「没有引用」，
    // 静默地允许一次会让配置悬空的删除。
    _showFailure(context, references.errorOrNull!, wrap: l10n.aiDeleteFailed);
    return;
  }
  final List<ModelReference> list = references.valueOrNull!;
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(l10n.aiDeleteConfirmTitle(model.alias)),
      content: Text(
        list.isEmpty
            ? l10n.aiDeleteConfirmBody
            : '${l10n.aiDeleteConfirmBody}\n\n'
                  '${l10n.aiDeleteInUseBody(list.map((ModelReference reference) => describeModelReference(l10n, reference)).join('、'))}',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.aiDeleteCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.aiDeleteConfirmYes),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  // 已经展示过引用并且用户确认，因此带 force。
  final Result<void> deleted = await controller.delete(model, force: true);
  if (deleted.isErr && context.mounted) {
    _showFailure(context, deleted.errorOrNull!, wrap: l10n.aiDeleteFailed);
  }
}

void _showFailure(
  BuildContext context,
  AppError error, {
  String Function(String reason)? wrap,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
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
  });

  final AiModelsState state;
  final ValueChanged<AiModel> onEdit;
  final ValueChanged<AiModel> onDelete;
  final void Function(AiModel model, bool enabled) onToggle;
  final void Function(AiModel model, int delta) onMove;
  final void Function(AiModel model, bool value) onSetDefault;

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
            text: l10n.aiLoadFailed(
              describeAiFailure(l10n, state.loadFailure!),
            ),
            isError: true,
          ),
        if (!state.credentialStoreAvailable)
          _Banner(text: l10n.aiApiKeyUnavailable, isError: false),
        if (state.models.isEmpty && state.loadFailure == null)
          _Banner(text: l10n.aiEmptyNotice, isError: false),
        Text(l10n.aiModelsSection, style: theme.textTheme.titleSmall),
        const SizedBox(height: FluxSpacing.xxs),
        Text(l10n.aiSortHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: FluxSpacing.sm),
        for (int index = 0; index < state.models.length; index++)
          _ModelCard(
            model: state.models[index],
            canMoveUp: index > 0,
            canMoveDown: index < state.models.length - 1,
            onEdit: () => onEdit(state.models[index]),
            onDelete: () => onDelete(state.models[index]),
            onToggle: (bool enabled) => onToggle(state.models[index], enabled),
            onMoveUp: () => onMove(state.models[index], -1),
            onMoveDown: () => onMove(state.models[index], 1),
            onSetDefault: (bool value) =>
                onSetDefault(state.models[index], value),
          ),
        const SizedBox(height: FluxSpacing.md),
        Text(l10n.aiPlannedNotice, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// 一条模型记录的卡片。
class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onSetDefault,
  });

  final AiModel model;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final ValueChanged<bool> onSetDefault;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final List<String> capabilities = <String>[
      if (model.capability.text) l10n.aiCapabilityText,
      if (model.capability.vision) l10n.aiCapabilityVision,
      if (model.capability.streaming) l10n.aiCapabilityStreaming,
      if (model.capability.tools) l10n.aiCapabilityTools,
      if (model.capability.structured) l10n.aiCapabilityStructured,
    ];
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
                  child: Text(model.alias, style: theme.textTheme.titleMedium),
                ),
                if (model.isDefaultForTasks)
                  Padding(
                    padding: const EdgeInsets.only(right: FluxSpacing.xs),
                    child: Chip(
                      label: Text(l10n.aiDefaultForTasksBadge),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                IconButton(
                  tooltip: l10n.aiMoveUp,
                  onPressed: canMoveUp ? onMoveUp : null,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                IconButton(
                  tooltip: l10n.aiMoveDown,
                  onPressed: canMoveDown ? onMoveDown : null,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                ),
              ],
            ),
            Text(
              '${model.protocol.label} · ${model.modelId}',
              style: theme.textTheme.bodyMedium,
            ),
            // Base URL 原样展示：它不含凭据（凭据在 Keychain），用户需要核对地址。
            Text(model.baseUrl, style: theme.textTheme.bodySmall),
            const SizedBox(height: FluxSpacing.xxs),
            Text(
              capabilities.isEmpty ? '—' : capabilities.join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            Text(
              l10n.aiBudgetConservativeHint(
                model.capability.effectiveContextBudget,
                model.capability.effectiveOutputBudget,
              ),
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: FluxSpacing.xxs),
            Row(
              children: <Widget>[
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: model.enabled,
                    onChanged: onToggle,
                    title: Text(
                      l10n.aiEnabledLabel,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: model.isDefaultForTasks,
                    onChanged: onSetDefault,
                    title: Text(
                      l10n.aiDefaultForTasksLabel,
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
                  TextButton(onPressed: onEdit, child: Text(l10n.aiEditModel)),
                  TextButton(
                    onPressed: onDelete,
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
