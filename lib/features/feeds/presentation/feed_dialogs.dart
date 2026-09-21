// 订阅管理页的对话框（T014）：添加订阅、改名、移动分组、新建/改名/删除分组。
//
// 为什么对话框单独一个文件：它们共享同一套「输入 → 校验 → 提交 → 显示失败」流程，
// 而这条流程里最容易出错的是**失败后的状态**（提交中禁用按钮、失败后保留输入、
// 成功后关闭）。放在一起可以保证六个对话框的行为一致，而不是各写一遍。
//
// 文案全部走 l10n；错误提示按类型化类别（AddFeedFailureReason）选择，不显示底层
// 错误消息原文——那里面可能有地址里的秘密参数（架构第 8 节）。
library;

import 'package:flutter/material.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';

import '../application/add_feed.dart';
import '../application/manage_groups.dart';
import '../domain/feed_parser.dart';

/// 对话框宽度上限（桌面）；窄窗时自动收窄。
const double dialogMaxWidth = 520;

/// 把一个添加失败的类别翻译成用户文案。
String describeAddFeedFailure(
  AppLocalizations l10n,
  AddFeedFailureReason reason,
) => switch (reason) {
  AddFeedFailureReason.invalidUrl => l10n.subscriptionErrorInvalidUrl,
  AddFeedFailureReason.network => l10n.subscriptionErrorNetwork,
  AddFeedFailureReason.parse => l10n.subscriptionErrorParse,
  AddFeedFailureReason.storage => l10n.subscriptionErrorStorage,
};

/// 添加订阅对话框的结果；取消时为 null。
class AddFeedDialogResult {
  /// 构造结果。
  const AddFeedDialogResult({required this.outcome, required this.feedName});

  /// 用例结果。
  final AddFeedOutcome outcome;

  /// 落库时使用的名称（提示文案需要）。
  final String feedName;
}

/// 打开「添加订阅」对话框。
///
/// 三个回调分别对应「预览」「确认」「读取分组清单」；把它们作为参数传入而不是在
/// 对话框里直接读 Provider，是为了让对话框可以被独立测试（注入假实现即可），
/// 也让「对话框能做什么」在签名上就是明确的。
Future<AddFeedDialogResult?> showAddFeedDialog({
  required BuildContext context,
  required Future<Result<FeedPreview>> Function(String url) onPreview,
  required Future<Result<AddFeedOutcome>> Function({
    required FeedPreview preview,
    required String name,
    int? groupId,
  })
  onConfirm,
  required List<GroupOption> groups,
  int? initialGroupId,
}) {
  return showDialog<AddFeedDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => _AddFeedDialog(
      onPreview: onPreview,
      onConfirm: onConfirm,
      groups: groups,
      initialGroupId: initialGroupId,
    ),
  );
}

/// 分组下拉选项（对话框不依赖完整 GroupRecord，只需要 id 与名称）。
class GroupOption {
  /// 构造选项。
  const GroupOption({required this.id, required this.name});

  /// 分组本机 id；null 表示「不归入任何分组」。
  final int? id;

  /// 展示名。
  final String name;
}

/// 添加订阅对话框。
class _AddFeedDialog extends StatefulWidget {
  const _AddFeedDialog({
    required this.onPreview,
    required this.onConfirm,
    required this.groups,
    this.initialGroupId,
  });

  final Future<Result<FeedPreview>> Function(String url) onPreview;
  final Future<Result<AddFeedOutcome>> Function({
    required FeedPreview preview,
    required String name,
    int? groupId,
  })
  onConfirm;
  final List<GroupOption> groups;
  final int? initialGroupId;

  @override
  State<_AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends State<_AddFeedDialog> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _name = TextEditingController();

  FeedPreview? _preview;
  String? _errorText;
  int? _groupId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _groupId = widget.initialGroupId;
  }

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _runPreview() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _errorText = null;
      _preview = null;
    });
    final Result<FeedPreview> result = await widget.onPreview(_url.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (result.isOk) {
        _preview = result.unwrap();
        // 名称初值取预览标题（源自带名或主机名），用户可直接确认或改写。
        _name.text = _preview!.title;
      } else {
        _errorText = describeAddFeedFailure(
          l10n,
          AddFeedFailureReason.classify(result.errorOrNull!),
        );
      }
    });
  }

  Future<void> _confirm() async {
    final FeedPreview? preview = _preview;
    if (preview == null) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _errorText = null;
    });
    final Result<AddFeedOutcome> result = await widget.onConfirm(
      preview: preview,
      name: _name.text,
      groupId: _groupId,
    );
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() {
        _busy = false;
        _errorText = describeAddFeedFailure(
          l10n,
          AddFeedFailureReason.classify(result.errorOrNull!),
        );
      });
      return;
    }
    Navigator.of(context).pop(
      AddFeedDialogResult(
        outcome: result.unwrap(),
        feedName: _name.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final FeedPreview? preview = _preview;

    return AlertDialog(
      title: Text(l10n.subscriptionAddFeedTitle),
      content: SizedBox(
        width: dialogMaxWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _url,
                autofocus: true,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: l10n.subscriptionFeedUrlLabel,
                  helperText: l10n.subscriptionFeedUrlHint,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (String _) => _runPreview(),
              ),
              const SizedBox(height: FluxSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _runPreview,
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: Text(l10n.subscriptionPreviewAction),
                ),
              ),
              if (_errorText case final String message) ...<Widget>[
                const SizedBox(height: FluxSpacing.sm),
                _DialogError(message: message),
              ],
              if (preview != null) ...<Widget>[
                const SizedBox(height: FluxSpacing.md),
                Text(
                  l10n.subscriptionPreviewTitle,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: FluxSpacing.xs),
                if (preview.isDuplicate)
                  _DialogNotice(
                    title: l10n.subscriptionPreviewDuplicateTitle,
                    body: l10n.subscriptionPreviewDuplicateBody(
                      preview.duplicateOf!.name,
                    ),
                  )
                else ...<Widget>[
                  _PreviewRow(
                    label: l10n.subscriptionFeedNameLabel,
                    value: preview.title,
                  ),
                  _PreviewRow(
                    label: l10n.subscriptionPreviewFormat,
                    value: formatLabel(preview.format!),
                  ),
                  _PreviewRow(
                    label: l10n.subscriptionPreviewEntries(preview.entryCount),
                    value: preview.siteUrl ?? '',
                  ),
                  if (preview.rejectedEntries > 0)
                    _PreviewRow(
                      label: l10n.subscriptionPreviewRejected(
                        preview.rejectedEntries,
                      ),
                      value: '',
                    ),
                  // 规范化地址是**匹配与去重**的依据，用户看不到它就无法解释
                  // 「为什么这个地址说是重复」。因此它是预览的一部分。
                  _PreviewRow(
                    label: l10n.subscriptionPreviewNormalized,
                    value: preview.normalizedUrl,
                  ),
                  const SizedBox(height: FluxSpacing.sm),
                  TextField(
                    controller: _name,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: l10n.subscriptionFeedNameLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: FluxSpacing.sm),
                  DropdownButtonFormField<int?>(
                    initialValue: _groupId,
                    decoration: InputDecoration(
                      labelText: l10n.subscriptionFeedGroupLabel,
                      border: const OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<int?>>[
                      for (final GroupOption option in widget.groups)
                        DropdownMenuItem<int?>(
                          value: option.id,
                          child: Text(option.name),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (int? value) => setState(() => _groupId = value),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.subscriptionCancel),
        ),
        if (preview != null && !preview.isDuplicate)
          FilledButton(
            onPressed: _busy ? null : _confirm,
            child: Text(l10n.subscriptionConfirmAdd),
          )
        else if (preview != null)
          FilledButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.subscriptionClose),
          ),
      ],
    );
  }

  /// 源格式的展示文案（不是本地化文案：RSS/Atom 是协议名，各语言一致）。
  static String formatLabel(FeedFormat format) => switch (format) {
    FeedFormat.rss2 => 'RSS 2.0',
    FeedFormat.rss1 => 'RSS 1.0 / RDF',
    FeedFormat.atom => 'Atom 1.0',
  };
}

/// 预览里的一行。
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: FluxSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (value.isNotEmpty)
            SelectableText(value, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 对话框里的错误提示（红色，文字用 onSurface 保证对比度）。
class _DialogError extends StatelessWidget {
  const _DialogError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FluxSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(FluxRadius.card),
        border: Border.all(color: theme.colorScheme.error),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// 对话框里的中性提示（例如「该地址已订阅」）。
class _DialogNotice extends StatelessWidget {
  const _DialogNotice({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FluxSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(FluxRadius.card),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: FluxSpacing.xxs),
          Text(body, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 单行文本输入对话框（改名类共用）。
Future<String?> showNameDialog({
  required BuildContext context,
  required String title,
  required String label,
  String initialValue = '',
  String? emptyErrorMessage,
}) => showDialog<String>(
  context: context,
  // 用独立 StatefulWidget 而不是 StatefulBuilder + 外部 controller：controller
  // 必须由**对话框自己的 State** 持有并在它的 dispose 里释放。放在外面（调用方
  // 的 finally 里 dispose）会在对话框退场动画还没跑完时就被释放，Flutter 报
  // 「A TextEditingController was used after being disposed」——这是实测踩到的
  // 真实缺陷，不是理论风险。
  builder: (BuildContext context) => _NameDialog(
    title: title,
    label: label,
    initialValue: initialValue,
    emptyErrorMessage: emptyErrorMessage,
  ),
);

/// 单行名称输入对话框。
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    this.emptyErrorMessage,
  });

  final String title;
  final String label;
  final String initialValue;
  final String? emptyErrorMessage;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 提交；空名时给字段级错误而不关闭对话框。
  void _submit() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String value = _controller.text.trim();
    if (value.isEmpty) {
      // 空名在界面上先拦一次，给字段级错误；用例层仍会再校验（界面不可信，
      // 且用例要被其他调用方复用）。
      setState(
        () => _error =
            widget.emptyErrorMessage ?? l10n.subscriptionInvalidFeedName,
      );
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: dialogMaxWidth,
        child: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: widget.label,
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (String _) => _submit(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.subscriptionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.subscriptionSave)),
      ],
    );
  }
}

/// 删除分组对话框的结果。
class DeleteGroupChoice {
  /// 构造选择。
  const DeleteGroupChoice(this.mode);

  /// 用户选择的处理方式。
  final GroupDeletionMode mode;
}

/// 打开删除分组确认框；返回 null 表示取消。
Future<DeleteGroupChoice?> showDeleteGroupDialog({
  required BuildContext context,
  required String groupName,
  required int feedCount,
}) {
  return showDialog<DeleteGroupChoice>(
    context: context,
    builder: (BuildContext context) {
      final AppLocalizations l10n = AppLocalizations.of(context);
      final ThemeData theme = Theme.of(context);
      return AlertDialog(
        title: Text(l10n.subscriptionGroupDeleteTitle(groupName)),
        content: SizedBox(
          width: dialogMaxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(l10n.subscriptionGroupDeleteBody(feedCount)),
              const SizedBox(height: FluxSpacing.sm),
              _DeleteOption(
                icon: Icons.drive_file_move_outline,
                title: l10n.subscriptionGroupDeleteMoveOption,
                hint: l10n.subscriptionGroupDeleteMoveHint,
                onTap: () => Navigator.of(context).pop(
                  const DeleteGroupChoice(
                    GroupDeletionMode.moveToUncategorized,
                  ),
                ),
              ),
              const SizedBox(height: FluxSpacing.xs),
              // 第二个分支**如实标注**本期不删除：一个看起来能删、实际只记录
              // 的选项必须在按下之前就说清楚，而不是在结果里才告知。
              _DeleteOption(
                icon: Icons.delete_outline,
                title: l10n.subscriptionGroupDeleteFeedsOption,
                hint: l10n.subscriptionGroupDeleteFeedsHint,
                destructive: true,
                onTap: () => Navigator.of(
                  context,
                ).pop(const DeleteGroupChoice(GroupDeletionMode.deleteFeeds)),
              ),
              const SizedBox(height: FluxSpacing.sm),
              Text(
                l10n.subscriptionManagerNotice,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.subscriptionCancel),
          ),
        ],
      );
    },
  );
}

/// 删除分组对话框里的一个分支选项。
class _DeleteOption extends StatelessWidget {
  const _DeleteOption({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FluxRadius.card),
        child: Container(
          padding: const EdgeInsets.all(FluxSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FluxRadius.card),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: FluxSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: FluxSpacing.xxs),
                    Text(hint, style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 选择目标分组对话框；返回 (是否取消, 目标分组 id)。
///
/// 「不归入任何分组」也是一个合法选择（[GroupOption.id] 为 null），因此不能用
/// 「返回 null 表示取消」的约定——那会让用户无法表达「移出分组」。
class MoveFeedChoice {
  /// 构造选择。
  const MoveFeedChoice(this.groupId);

  /// 目标分组 id；null 表示不归入任何分组。
  final int? groupId;
}

/// 打开「移动到分组」对话框。
Future<MoveFeedChoice?> showMoveFeedDialog({
  required BuildContext context,
  required String feedName,
  required List<GroupOption> groups,
  int? currentGroupId,
}) {
  return showDialog<MoveFeedChoice>(
    context: context,
    builder: (BuildContext context) {
      final AppLocalizations l10n = AppLocalizations.of(context);
      return SimpleDialog(
        title: Text(l10n.subscriptionMoveToGroupTitle(feedName)),
        children: <Widget>[
          for (final GroupOption option in groups)
            // 用 ListTile + 勾选图标而不是 RadioListTile：后者在 Flutter 3.47 里
            // 的 groupValue/onChanged 已废弃（需要 RadioGroup 祖先），而这个选择
            // 是**一次性动作**（点一下就关闭对话框并提交），不是需要保持挂载状态的
            // 表单控件，因此不需要引入 RadioGroup 的额外状态层。
            ListTile(
              leading: Icon(
                option.id == currentGroupId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
              ),
              title: Text(option.name),
              selected: option.id == currentGroupId,
              onTap: () => Navigator.of(context).pop(MoveFeedChoice(option.id)),
            ),
        ],
      );
    },
  );
}
