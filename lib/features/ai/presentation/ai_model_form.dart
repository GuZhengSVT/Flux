// 模型编辑对话框（T025；SET-030/031/032/033）。
//
// 三个刻意的界面决策：
//
//   1) **Key 是不可回显的一次性输入**。对话框只显示「已配置 / 尚未配置」，编辑框始终
//      为空，留空表示「不改」。这比回显掩码更安全：掩码长度会泄漏 Key 的长度，而
//      「显示」一次就把它带进了可能被截屏的界面（SET-031 要求遮盖）。
//
//   2) **未实现的协议在选择项里就标注**。Anthropic Messages 在 T025 期间没有适配器，
//      因此它的选项带「（适配器待实现）」。用户可以配置并保存（提前准备没问题），
//      但不会在点测试时才发现。
//
//   3) **费用确认是测试的前置条件**。测试按钮先弹确认框，确认后才构造
//      [CostConfirmation]；没有它 [ModelManager.runMinimalGeneration] 直接拒绝。
//      因此「忘了弹框」在类型上不可能发生。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';

import '../application/model_manager.dart';
import '../application/model_manager_controller.dart';
import '../domain/ai_message.dart';
import '../domain/ai_model.dart';
import '../domain/ai_protocol.dart';
import '../domain/model_capability.dart';
import 'ai_failure_text.dart';

/// 对话框宽度上限（桌面）；窄窗时自动收窄。
const double aiDialogMaxWidth = 560;

/// 打开模型编辑对话框。
///
/// 返回保存后的模型（取消时为 null）。所有副作用都通过回调注入，因此对话框可以被
/// 独立测试（注入假实现即可），也让「这个对话框能做什么」在签名上就是明确的。
Future<AiModel?> showAiModelForm({
  required BuildContext context,
  required AiModel? initial,
  required Future<bool> Function(String alias) hasCredential,
  required Future<Result<void>> Function(String alias, String apiKey)
  saveCredential,
  required Future<Result<void>> Function(String alias) deleteCredential,
  required Future<Result<AiModel>> Function(AiModel model) onSave,
  required Future<Result<ModelTestReport>> Function(
    AiModel model,
    CostConfirmation confirmation,
  )
  onTest,
  required bool credentialStoreAvailable,
}) {
  return showDialog<AiModel>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => AiModelFormDialog(
      initial: initial,
      hasCredential: hasCredential,
      saveCredential: saveCredential,
      deleteCredential: deleteCredential,
      onSave: onSave,
      onTest: onTest,
      credentialStoreAvailable: credentialStoreAvailable,
    ),
  );
}

/// 模型编辑对话框。
class AiModelFormDialog extends StatefulWidget {
  /// 构造对话框。
  const AiModelFormDialog({
    super.key,
    required this.initial,
    required this.hasCredential,
    required this.saveCredential,
    required this.deleteCredential,
    required this.onSave,
    required this.onTest,
    required this.credentialStoreAvailable,
  });

  /// 编辑对象；新增时为 null。
  final AiModel? initial;

  /// 查询某个别名是否已有 Key。
  final Future<bool> Function(String alias) hasCredential;

  /// 写入 Key。
  final Future<Result<void>> Function(String alias, String apiKey)
  saveCredential;

  /// 删除 Key。
  final Future<Result<void>> Function(String alias) deleteCredential;

  /// 保存模型记录。
  final Future<Result<AiModel>> Function(AiModel model) onSave;

  /// 发起最小生成测试。
  final Future<Result<ModelTestReport>> Function(
    AiModel model,
    CostConfirmation confirmation,
  )
  onTest;

  /// 安全存储是否可用（false 时提示本次会话可用但不保存）。
  final bool credentialStoreAvailable;

  @override
  State<AiModelFormDialog> createState() => _AiModelFormDialogState();
}

class _AiModelFormDialogState extends State<AiModelFormDialog> {
  late final TextEditingController _alias;
  late final TextEditingController _baseUrl;
  late final TextEditingController _modelId;
  late final TextEditingController _contextWindow;
  late final TextEditingController _outputBudget;
  final TextEditingController _apiKey = TextEditingController();

  late AiProtocol _protocol;
  late bool _text;
  late bool _vision;
  late bool _streaming;
  late bool _tools;
  late bool _structured;
  late bool _enabled;
  late bool _defaultForTasks;

  /// 当前别名是否已有 Key（随别名输入变化而重新查询）。
  bool _credentialPresent = false;

  /// 保存/测试进行中：禁用按钮，避免重复提交产生重复计费或重复写入。
  bool _busy = false;

  /// 一条待显示的失败提示（已翻译成用户文案）。
  String? _notice;

  /// 上一次测试结果（成功时显示耗时与 token）。
  String? _testSummary;

  @override
  void initState() {
    super.initState();
    final AiModel? initial = widget.initial;
    _alias = TextEditingController(text: initial?.alias ?? '');
    _baseUrl = TextEditingController(text: initial?.baseUrl ?? '');
    _modelId = TextEditingController(text: initial?.modelId ?? '');
    _contextWindow = TextEditingController(
      text: initial?.capability.contextWindow?.toString() ?? '',
    );
    _outputBudget = TextEditingController(
      text: initial?.capability.maxOutput?.toString() ?? '',
    );
    _protocol = initial?.protocol ?? AiProtocol.openAiChatCompletions;
    final ModelCapability capability =
        initial?.capability ?? const ModelCapability();
    _text = capability.text;
    _vision = capability.vision;
    _streaming = capability.streaming;
    _tools = capability.tools;
    _structured = capability.structured;
    _enabled = initial?.enabled ?? true;
    _defaultForTasks = initial?.isDefaultForTasks ?? false;
    // 打开即查一次：编辑既有模型时用户需要马上看到「Key 是否已配置」。
    unawaited(_refreshCredentialState());
  }

  @override
  void dispose() {
    _alias.dispose();
    _baseUrl.dispose();
    _modelId.dispose();
    _contextWindow.dispose();
    _outputBudget.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.initial == null ? l10n.aiAddModel : l10n.aiEditModel),
      content: SizedBox(
        width: aiDialogMaxWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_notice != null) ...<Widget>[
                _Notice(text: _notice!, isError: true),
                const SizedBox(height: FluxSpacing.sm),
              ],
              if (_testSummary != null) ...<Widget>[
                _Notice(text: _testSummary!, isError: false),
                const SizedBox(height: FluxSpacing.sm),
              ],
              // ---- SET-030：协议 / 别名 / Base URL --------------------
              Text(l10n.aiProtocolLabel, style: theme.textTheme.labelLarge),
              const SizedBox(height: FluxSpacing.xxs),
              DropdownButtonFormField<AiProtocol>(
                initialValue: _protocol,
                isExpanded: true,
                items: <DropdownMenuItem<AiProtocol>>[
                  for (final AiProtocol protocol in AiProtocol.values)
                    DropdownMenuItem<AiProtocol>(
                      value: protocol,
                      child: Text(
                        protocol.hasAdapter
                            ? protocol.label
                            : '${protocol.label}${l10n.aiProtocolPendingSuffix}',
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (AiProtocol? value) {
                        if (value != null) {
                          setState(() => _protocol = value);
                        }
                      },
              ),
              const SizedBox(height: FluxSpacing.xxs),
              Text(l10n.aiProtocolHint, style: theme.textTheme.bodySmall),
              const SizedBox(height: FluxSpacing.sm),
              TextField(
                controller: _alias,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: l10n.aiAliasLabel,
                  helperText: l10n.aiAliasHint,
                ),
                onChanged: (String _) => unawaited(_refreshCredentialState()),
              ),
              const SizedBox(height: FluxSpacing.sm),
              TextField(
                controller: _baseUrl,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: l10n.aiBaseUrlLabel,
                  helperText: l10n.aiBaseUrlHint,
                ),
              ),
              const SizedBox(height: FluxSpacing.sm),
              TextField(
                controller: _modelId,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: l10n.aiModelIdLabel,
                  helperText: l10n.aiModelIdHint,
                ),
              ),
              const Divider(height: FluxSpacing.lg),
              // ---- SET-031：Key ---------------------------------------
              Text(l10n.aiApiKeyLabel, style: theme.textTheme.labelLarge),
              const SizedBox(height: FluxSpacing.xxs),
              Text(
                _credentialPresent
                    ? l10n.aiApiKeyConfigured(aiKeyMask)
                    : l10n.aiApiKeyNotConfigured,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: FluxSpacing.xxs),
              TextField(
                controller: _apiKey,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.aiApiKeyReplace,
                  helperText: l10n.aiApiKeyHint,
                ),
              ),
              if (!widget.credentialStoreAvailable) ...<Widget>[
                const SizedBox(height: FluxSpacing.xxs),
                Text(
                  l10n.aiApiKeyUnavailable,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (_credentialPresent) ...<Widget>[
                const SizedBox(height: FluxSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy ? null : () => unawaited(_clearKey()),
                    child: Text(l10n.aiApiKeyClear),
                  ),
                ),
              ],
              const Divider(height: FluxSpacing.lg),
              // ---- SET-033：能力与预算 ---------------------------------
              Text(l10n.aiCapabilitySection, style: theme.textTheme.labelLarge),
              const SizedBox(height: FluxSpacing.xxs),
              Text(l10n.aiCapabilityHint, style: theme.textTheme.bodySmall),
              const SizedBox(height: FluxSpacing.xs),
              Wrap(
                spacing: FluxSpacing.sm,
                children: <Widget>[
                  _capabilityChip(
                    label: l10n.aiCapabilityText,
                    value: _text,
                    onChange: (bool v) => setState(() => _text = v),
                  ),
                  _capabilityChip(
                    label: l10n.aiCapabilityVision,
                    value: _vision,
                    onChange: (bool v) => setState(() => _vision = v),
                  ),
                  _capabilityChip(
                    label: l10n.aiCapabilityStreaming,
                    value: _streaming,
                    onChange: (bool v) => setState(() => _streaming = v),
                  ),
                  _capabilityChip(
                    label: l10n.aiCapabilityTools,
                    value: _tools,
                    onChange: (bool v) => setState(() => _tools = v),
                  ),
                  _capabilityChip(
                    label: l10n.aiCapabilityStructured,
                    value: _structured,
                    onChange: (bool v) => setState(() => _structured = v),
                  ),
                ],
              ),
              const SizedBox(height: FluxSpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _contextWindow,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.aiContextWindowLabel,
                      ),
                    ),
                  ),
                  const SizedBox(width: FluxSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _outputBudget,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.aiOutputBudgetLabel,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluxSpacing.xxs),
              Text(
                l10n.aiBudgetConservativeHint(
                  ModelCapability.conservativeContextBudget,
                  ModelCapability.conservativeOutputBudget,
                ),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: FluxSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                onChanged: _busy
                    ? null
                    : (bool value) => setState(() => _enabled = value),
                title: Text(l10n.aiEnabledLabel),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _defaultForTasks,
                onChanged: _busy
                    ? null
                    : (bool value) => setState(() => _defaultForTasks = value),
                title: Text(l10n.aiDefaultForTasksLabel),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.aiCancelAction),
        ),
        TextButton(
          onPressed: _busy ? null : () => unawaited(_runTest()),
          child: Text(_busy ? l10n.aiTestRunning : l10n.aiTestButton),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_save()),
          child: Text(l10n.aiSaveAction),
        ),
      ],
    );
  }

  Widget _capabilityChip({
    required String label,
    required bool value,
    required ValueChanged<bool> onChange,
  }) => FilterChip(
    label: Text(label),
    selected: value,
    onSelected: _busy ? null : onChange,
  );

  /// 查询当前别名的 Key 状态；别名为空时不显示「已配置」。
  Future<void> _refreshCredentialState() async {
    final String alias = _alias.text.trim();
    if (alias.isEmpty) {
      if (mounted && _credentialPresent) {
        setState(() => _credentialPresent = false);
      }
      return;
    }
    final bool present = await widget.hasCredential(alias);
    if (!mounted) {
      return;
    }
    if (present != _credentialPresent) {
      setState(() => _credentialPresent = present);
    }
    // hasCredential 为异步：别名可能在等待期间被改掉，此时结果属于旧别名。
    if (_alias.text.trim() != alias) {
      unawaited(_refreshCredentialState());
    }
  }

  Future<void> _clearKey() async {
    final String alias = _alias.text.trim();
    final Result<void> deleted = await widget.deleteCredential(alias);
    if (!mounted) {
      return;
    }
    setState(() {
      if (deleted.isErr) {
        _notice = describeAiFailure(
          AppLocalizations.of(context),
          AiFailureReason.classify(deleted.errorOrNull!),
        );
      } else {
        _credentialPresent = false;
        _notice = null;
      }
    });
  }

  /// 提交表单：先写 Key（若有输入），再保存记录。
  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AiModel? draft = _buildDraft();
    if (draft == null) {
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
      _testSummary = null;
    });
    try {
      // 顺序：先写 Key。若记录先保存成功而 Key 写入失败，用户会看到「已保存」但
      // 实际上没有凭据；反过来则只是「Key 写了但记录没保存」，而 Key 在同一个别名下
      // 是幂等可复用的，下一次保存记录即可生效。
      final String typedKey = _apiKey.text;
      if (typedKey.isNotEmpty) {
        final Result<void> written = await widget.saveCredential(
          draft.alias,
          typedKey,
        );
        if (written.isErr) {
          if (mounted) {
            setState(() {
              _notice = describeAiFailure(
                l10n,
                AiFailureReason.classify(written.errorOrNull!),
              );
              _busy = false;
            });
          }
          return;
        }
      }
      final Result<AiModel> saved = await widget.onSave(draft);
      if (!mounted) {
        return;
      }
      if (saved.isErr) {
        setState(() {
          _notice = describeAiFailure(
            l10n,
            AiFailureReason.classify(saved.errorOrNull!),
            detail: saved.errorOrNull!.message,
          );
          _busy = false;
        });
        return;
      }
      Navigator.of(context).pop(saved.valueOrNull);
    } finally {
      if (mounted && _busy) {
        setState(() => _busy = false);
      }
    }
  }

  /// 由表单构造一条待保存的记录；输入非法时设置提示并返回 null。
  AiModel? _buildDraft() {
    final AiModel? initial = widget.initial;
    final (bool, int?) contextBudget = _parseOptionalInt(
      _contextWindow.text,
      AppLocalizations.of(context).aiContextWindowLabel,
    );
    if (!contextBudget.$1) {
      return null;
    }
    final (bool, int?) outputBudget = _parseOptionalInt(
      _outputBudget.text,
      AppLocalizations.of(context).aiOutputBudgetLabel,
    );
    if (!outputBudget.$1) {
      return null;
    }
    final AiModel draft = AiModel(
      id: initial?.id,
      alias: _alias.text.trim(),
      preset: initial?.preset,
      protocol: _protocol,
      baseUrl: _baseUrl.text.trim(),
      modelId: _modelId.text.trim(),
      enabled: _enabled,
      sortOrder: initial?.sortOrder ?? 0,
      isDefaultForTasks: _defaultForTasks,
      capability: ModelCapability(
        text: _text,
        vision: _vision,
        streaming: _streaming,
        tools: _tools,
        structured: _structured,
        contextWindow: contextBudget.$2,
        maxOutput: outputBudget.$2,
      ),
    );
    final Result<void> valid = validateAiModel(draft);
    if (valid.isErr) {
      final ValidationError error = valid.errorOrNull! as ValidationError;
      setState(() {
        _notice = AppLocalizations.of(context)
            .aiFormInvalid('${error.field}：${error.reason}');
      });
      return null;
    }
    return draft;
  }

  /// 解析可留空的整数输入。
  ///
  /// 返回 `(是否合法, 值)`：用记录而不是「哨兵值 + null 双关」——留空（null）与
  /// 「填了但非法」必须区分开，否则 `-1` 这种哨兵会被当成合法整数继续往下走。
  (bool, int?) _parseOptionalInt(String raw, String fieldLabel) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return (true, null);
    }
    final int? value = int.tryParse(trimmed);
    if (value == null || value <= 0) {
      setState(() {
        _notice = AppLocalizations.of(context)
            .aiFormInvalid('$fieldLabel：必须是正整数');
      });
      return (false, null);
    }
    return (true, value);
  }

  /// 测试按钮：先把「会产生费用」说清楚，用户确认后才发请求。
  Future<void> _runTest() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AiModel? draft = _buildDraft();
    if (draft == null) {
      return;
    }
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(l10n.aiTestCostTitle),
            content: Text(
              l10n.aiTestCostBody(
                draft.alias,
                ModelManager.minimalTestMaxTokens,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.aiCancelAction),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.aiTestCostConfirm),
              ),
            ],
          ),
        ) ??
        // 关掉对话框（点遮罩/ESC）按「不确认」处理：一次可能计费的调用必须显式确认。
        false;
    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
      _notice = null;
      _testSummary = null;
    });
    try {
      final String typedKey = _apiKey.text;
      if (typedKey.isNotEmpty) {
        final Result<void> written = await widget.saveCredential(
          draft.alias,
          typedKey,
        );
        if (written.isErr) {
          if (mounted) {
            setState(() {
              _notice = describeAiFailure(
                l10n,
                AiFailureReason.classify(written.errorOrNull!),
              );
            });
          }
          return;
        }
      }
      final Result<ModelTestReport> result = await widget.onTest(
        draft,
        CostConfirmation(acknowledgedAtUtc: DateTime.now().toUtc()),
      );
      if (!mounted) {
        return;
      }
      if (result.isErr) {
        setState(() {
          _notice = l10n.aiTestFailed(
            describeAiFailure(
              l10n,
              AiFailureReason.classify(result.errorOrNull!),
            ),
          );
        });
        return;
      }
      final ModelTestReport report = result.valueOrNull!;
      final AiUsage? usage = report.usage;
      setState(() {
        _testSummary = usage == null
            ? l10n.aiTestSuccess(
                report.elapsed.inMilliseconds,
                report.textLength,
              )
            : l10n.aiTestSuccessWithUsage(
                report.elapsed.inMilliseconds,
                usage.inputTokens,
                usage.outputTokens,
                report.textLength,
              );
      });
    } finally {
      if (mounted && _busy) {
        setState(() => _busy = false);
      }
    }
  }
}

/// 固定长度的 Key 掩码。
///
/// 刻意**不**按真实长度生成：长度本身是一点信息（有些服务商的 Key 长度固定），
/// 而「已配置」这个事实已经足够用户判断下一步该做什么。
const String aiKeyMask = '••••••••';

/// 只渲染一段提示的控件。
class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FluxSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(FluxRadius.button),
        border: Border.all(color: isError ? colors.error : colors.outline),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: isError ? colors.error : colors.onSurface),
      ),
    );
  }
}
