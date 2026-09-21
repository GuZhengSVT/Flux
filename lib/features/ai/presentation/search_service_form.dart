// 搜索服务编辑对话框（T031；SET-038/039/040/041）。
//
// 与模型表单同一组刻意的界面决策：
//
//   1) **Key 是不可回显的一次性输入**。对话框只显示「已配置 / 尚未配置」，编辑框始终
//      为空，留空表示「不改」。这比回显掩码更安全：掩码长度会泄漏 Key 的长度，而
//      「显示」一次就把它带进了可能被截屏的界面（SET-039 要求遮盖）。
//
//   2) **协议切换会替换默认端点**，但**不代填 Key**：端点来自协议数据
//      （SearchProtocol.defaultBaseUrl），Key 只能由用户填。SearXNG 没有默认端点，
//      因此切换过去时保持用户已填的内容（那正是他唯一需要填的东西）。
//
//   3) **费用与数据发送确认是测试的前置条件**。测试按钮先弹确认框，确认后才构造
//      SearchSendConfirmation；没有它 SearchManager 直接拒绝。因此「忘了弹框」在
//      类型上不可能发生。
//
//   4) **私网批准是一等字段**（SET-041）。自建实例在局域网时，用户必须显式打开它；
//      对话框里直接说明「未批准时会被地址守卫拒绝」，不让用户靠试错发现。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';

import '../application/model_manager_controller.dart' show AiFailureReason;
import '../application/search_manager.dart';
import '../domain/search_protocol.dart';
import '../domain/search_service.dart';
import 'ai_failure_text.dart';

/// 打开搜索服务编辑对话框。
///
/// 返回保存后的服务（取消时为 null）。所有副作用都通过回调注入，因此对话框可以被
/// 独立测试（注入假实现即可），也让「这个对话框能做什么」在签名上就是明确的。
Future<SearchService?> showSearchServiceForm({
  required BuildContext context,
  required SearchService? initial,
  required Future<bool> Function(String identifier) hasCredential,
  required Future<Result<void>> Function(String identifier, String apiKey)
  saveCredential,
  required Future<Result<void>> Function(String identifier) deleteCredential,
  required Future<Result<SearchService>> Function(SearchService service) onSave,
  required Future<Result<SearchTestReport>> Function(
    SearchService service,
    SearchSendConfirmation confirmation,
  )
  onTest,
  required bool credentialStoreAvailable,
}) {
  return showDialog<SearchService>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => SearchServiceFormDialog(
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

/// 搜索服务编辑对话框。
class SearchServiceFormDialog extends StatefulWidget {
  /// 构造对话框。
  const SearchServiceFormDialog({
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
  final SearchService? initial;

  /// 查询某个服务名是否已有 Key。
  final Future<bool> Function(String identifier) hasCredential;

  /// 写入 Key。
  final Future<Result<void>> Function(String identifier, String apiKey)
  saveCredential;

  /// 删除 Key。
  final Future<Result<void>> Function(String identifier) deleteCredential;

  /// 保存服务记录。
  final Future<Result<SearchService>> Function(SearchService service) onSave;

  /// 发起最小检索测试。
  final Future<Result<SearchTestReport>> Function(
    SearchService service,
    SearchSendConfirmation confirmation,
  )
  onTest;

  /// 安全存储是否可用。
  final bool credentialStoreAvailable;

  @override
  State<SearchServiceFormDialog> createState() =>
      _SearchServiceFormDialogState();
}

class _SearchServiceFormDialogState extends State<SearchServiceFormDialog> {
  late final TextEditingController _label;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _maxResults;
  late final TextEditingController _timeoutSeconds;

  late SearchProtocol _protocol;
  bool _enabled = true;
  bool _allowPrivate = false;
  bool _isDefault = false;

  /// Key 是否已配置（null 表示尚未查询到）。
  bool? _keyPresent;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  /// 已保存的记录（保存成功后才可用它做测试，因为测试需要已落库的 id）。
  SearchService? _saved;

  @override
  void initState() {
    super.initState();
    final SearchService? initial = widget.initial;
    _saved = initial;
    _protocol = initial?.protocol ?? SearchProtocol.tavily;
    _label = TextEditingController(text: initial?.label ?? '');
    _baseUrl = TextEditingController(
      text: initial?.baseUrl ?? _protocol.defaultBaseUrl,
    );
    _apiKey = TextEditingController();
    _maxResults = TextEditingController(
      text: '${initial?.maxResults ?? kSearchDefaultMaxResults}',
    );
    _timeoutSeconds = TextEditingController(
      text: '${initial?.timeoutSeconds ?? kSearchDefaultTimeoutSeconds}',
    );
    _enabled = initial?.enabled ?? true;
    _allowPrivate = initial?.allowPrivateEndpoint ?? false;
    _isDefault = initial?.isDefaultForTasks ?? false;
    if (initial != null) {
      unawaited(_refreshKeyState(initial.credentialIdentifier));
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _maxResults.dispose();
    _timeoutSeconds.dispose();
    super.dispose();
  }

  Future<void> _refreshKeyState(String identifier) async {
    final bool present = await widget.hasCredential(identifier);
    if (mounted) {
      setState(() => _keyPresent = present);
    }
  }

  /// 构造一条记录（不入库）。
  ///
  /// 把「表单里的值」收成一个对象，让保存与测试走同一份构造逻辑：两处各写一遍
  /// 必然会出现「保存用 A、测试用 B」的偏差，而那类偏差在界面上看不出来。
  SearchService _build() => SearchService(
    id: _saved?.id,
    label: _label.text.trim(),
    protocol: _protocol,
    baseUrl: _baseUrl.text.trim(),
    enabled: _enabled,
    sortOrder: _saved?.sortOrder ?? 0,
    maxResults:
        int.tryParse(_maxResults.text.trim()) ?? kSearchDefaultMaxResults,
    timeoutSeconds:
        int.tryParse(_timeoutSeconds.text.trim()) ??
        kSearchDefaultTimeoutSeconds,
    allowPrivateEndpoint: _allowPrivate,
    isDefaultForTasks: _isDefault,
  );

  void _report(String message, {required bool isError}) {
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final SearchService candidate = _build();
    final Result<SearchService> saved = await widget.onSave(candidate);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (saved.isErr) {
      final AppError error = saved.errorOrNull!;
      _report(
        describeAiFailure(
          l10n,
          AiFailureReason.classify(error),
          detail: error.message,
        ),
        isError: true,
      );
      return;
    }
    _saved = saved.valueOrNull;
    // Key 单独写入：它与记录是两处存储（SET-039 只住 Keychain）。留空表示「不改」，
    // 因此不会因为「这次没填」而把已有 Key 清掉。
    final String typedKey = _apiKey.text;
    if (typedKey.isNotEmpty) {
      final Result<void> written = await widget.saveCredential(
        candidate.credentialIdentifier,
        typedKey,
      );
      if (!mounted) {
        return;
      }
      if (written.isErr) {
        _report(l10n.aiFailureStorage, isError: true);
        return;
      }
      _apiKey.clear();
      await _refreshKeyState(candidate.credentialIdentifier);
    }
    _report(l10n.aiSavedNotice, isError: false);
  }

  Future<void> _deleteKey() async {
    final SearchService? saved = _saved;
    if (saved == null) {
      return;
    }
    setState(() => _busy = true);
    final Result<void> deleted = await widget.deleteCredential(
      saved.credentialIdentifier,
    );
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (deleted.isErr) {
      _report(l10n.aiFailureStorage, isError: true);
      return;
    }
    await _refreshKeyState(saved.credentialIdentifier);
  }

  /// 测试：先保存（保证有 id），再弹确认，最后发请求。
  Future<void> _test() async {
    if (_saved == null) {
      await _save();
      // _save 里有 await（落库 + 可能写凭据），因此这里必须重新确认组件还在树上：
      // 对话框可能已经在保存期间被关掉。
      if (!mounted) {
        return;
      }
      if (_saved == null) {
        return;
      }
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final SearchService saved = _saved!;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.searchTestConfirmTitle),
        content: Text(
          l10n.searchTestConfirmBody(
            saved.protocol.label,
            saved.endpoint.toString(),
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
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    final Result<SearchTestReport> report = await widget.onTest(
      saved,
      SearchSendConfirmation(acknowledgedAtUtc: DateTime.now().toUtc()),
    );
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (report.isErr) {
      final AppError error = report.errorOrNull!;
      _report(
        describeAiFailure(
          l10n,
          AiFailureReason.classify(error),
          detail: error.message,
        ),
        isError: true,
      );
      return;
    }
    final SearchTestReport value = report.unwrap();
    _report(
      l10n.searchTestSuccess(value.elapsed.inMilliseconds, value.resultCount),
      isError: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        widget.initial == null ? l10n.searchAddService : l10n.searchEditService,
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _label,
                decoration: InputDecoration(labelText: l10n.searchLabelField),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: FluxSpacing.sm),
              DropdownButtonFormField<SearchProtocol>(
                initialValue: _protocol,
                decoration: InputDecoration(
                  labelText: l10n.searchProtocolField,
                ),
                items: <DropdownMenuItem<SearchProtocol>>[
                  for (final SearchProtocol protocol in SearchProtocol.values)
                    DropdownMenuItem<SearchProtocol>(
                      value: protocol,
                      child: Text(protocol.label),
                    ),
                ],
                onChanged: (SearchProtocol? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    final bool previousWasDefault =
                        _baseUrl.text.trim().isEmpty ||
                        _baseUrl.text.trim() == _protocol.defaultBaseUrl;
                    _protocol = value;
                    // 只在用户还没改过端点时替换默认值（见文件头说明）。
                    if (previousWasDefault && value.defaultBaseUrl.isNotEmpty) {
                      _baseUrl.text = value.defaultBaseUrl;
                    }
                  });
                },
              ),
              const SizedBox(height: FluxSpacing.sm),
              TextField(
                controller: _baseUrl,
                decoration: InputDecoration(
                  labelText: l10n.searchEndpointField,
                  helperText: _protocol.defaultBaseUrl.isEmpty
                      ? l10n.searchEndpointRequiredHint
                      : l10n.searchEndpointResolved(
                          _protocol
                              .endpointFor(_baseUrl.text.trim())
                              .toString(),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: FluxSpacing.sm),
              TextField(
                controller: _apiKey,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.searchKeyField,
                  helperText: _keyStatusText(l10n),
                ),
              ),
              if (_keyPresent == true && _saved != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : () => unawaited(_deleteKey()),
                    child: Text(l10n.searchDeleteKey),
                  ),
                ),
              const SizedBox(height: FluxSpacing.xs),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _maxResults,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.searchMaxResultsField,
                      ),
                    ),
                  ),
                  const SizedBox(width: FluxSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _timeoutSeconds,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.searchTimeoutField,
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                onChanged: (bool value) => setState(() => _enabled = value),
                title: Text(l10n.aiEnabledLabel),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isDefault,
                onChanged: (bool value) => setState(() => _isDefault = value),
                title: Text(l10n.searchDefaultLabel),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowPrivate,
                onChanged: (bool value) =>
                    setState(() => _allowPrivate = value),
                title: Text(l10n.searchAllowPrivateLabel),
                subtitle: Text(l10n.searchAllowPrivateHint),
              ),
              if (!widget.credentialStoreAvailable)
                Padding(
                  padding: const EdgeInsets.only(top: FluxSpacing.xs),
                  child: Text(
                    l10n.aiApiKeyUnavailable,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: FluxSpacing.sm),
                  child: Text(
                    _message!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _messageIsError
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(_saved),
          child: Text(l10n.aiDeleteCancel),
        ),
        TextButton(
          onPressed: _busy ? null : () => unawaited(_test()),
          child: Text(l10n.searchTestButton),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_save()),
          child: Text(l10n.searchSaveService),
        ),
      ],
    );
  }

  /// Key 状态文案（只显示「已配置 / 尚未配置」，不回显长度或内容）。
  String _keyStatusText(AppLocalizations l10n) {
    if (!_protocol.requiresCredential) {
      return l10n.searchKeyOptionalHint;
    }
    if (_saved == null) {
      return l10n.searchKeyNotConfigured;
    }
    return (_keyPresent ?? false)
        ? l10n.searchKeyConfigured
        : l10n.searchKeyNotConfigured;
  }
}
