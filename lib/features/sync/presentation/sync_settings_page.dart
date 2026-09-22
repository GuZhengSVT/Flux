// 设置 → 同步与备份 → WebDAV 页（T044；SET-070–075）。
//
// 界面承诺（每一条对应一个「不做就成了假功能」的点）：
//
//   1) **测试连接是只读探测**：它只做 PROPFIND 与一次 GET，**不写任何东西**（按钮下方写明）。
//   2) **密码只进 Keychain**：输入框不回显已存密码（只显示「已保存」状态），写完立刻清空输入。
//   3) **同步范围来自投影**：纳入/排除清单来自 T041 的 SyncProjection（从 SET 注册表派生），
//      页面只展示数量与说明，**不手抄清单**——手抄的清单会与文档第 6 节漂移，而漂移的后果是
//      「某个 C 类设置在新设备上永远是默认值」，界面上完全看不出来。
//   4) **状态可见**：最近同步时间、待同步数、冲突数、降级提示条。
//   5) **首次合并与冲突各自有落点**：首次预览给「远端有什么 / 差异多少 / 默认不覆盖本地」，
//      冲突给「字段 / 本机值 / 远端值 / 选择控件」。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/l10n/l10n.dart';

import '../application/sync_engine.dart';
import '../application/sync_manager.dart';
import '../application/sync_providers.dart';
import '../application/sync_settings.dart';
import 'sync_status_text.dart';

/// 同步与备份页（WebDAV 小节）。
class SyncSettingsPage extends ConsumerStatefulWidget {
  /// 构造页面。
  const SyncSettingsPage({super.key});

  @override
  ConsumerState<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends ConsumerState<SyncSettingsPage> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _deviceNameController = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  bool _hasPassword = false;
  bool _secretStoreAvailable = true;
  String _remoteDirectory = defaultWebDavRemoteRoot;
  SyncUrlProblem _urlProblem = SyncUrlProblem.empty;
  bool _enabled = false;
  bool _syncOnStart = true;
  bool _syncOnChange = true;
  bool _manualOnly = false;
  int _intervalMinutes = 30;
  bool _syncCommonSettings = true;
  bool _syncReadingState = true;
  String _notice = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final Result<SyncSettings> read = await SyncSettingsReader(
      ref.read(settingsStoreProvider),
    ).load();
    final Result<bool> hasPassword = await ref
        .read(syncSecretStoreProvider)
        .hasPassword();
    final bool available = await ref
        .read(syncSecretStoreProvider)
        .isAvailable();
    if (!mounted) {
      return;
    }
    final SyncSettings? settings = read.valueOrNull;
    setState(() {
      _loading = false;
      _secretStoreAvailable = available;
      if (settings != null) {
        _urlController.text = settings.url;
        _usernameController.text = settings.username;
        _passwordController.text = '';
        _deviceNameController.text = settings.deviceName;
        _remoteDirectory = settings.remoteDirectory;
        _urlProblem = validateSyncUrl(settings.url);
        _enabled = settings.enabled;
        _syncOnStart = settings.syncOnStart;
        _syncOnChange = settings.syncOnChange;
        _manualOnly = settings.manualOnly;
        _intervalMinutes = settings.intervalMinutes;
        _syncCommonSettings = settings.syncCommonSettings;
        _syncReadingState = settings.syncReadingState;
      }
      _hasPassword = hasPassword.valueOrNull ?? false;
    });
  }

  Future<void> _write(SettingId id, Object? value) async {
    final Result<Object?> written = await ref
        .read(settingsStoreProvider)
        .writeSetting(id, value);
    if (!mounted) {
      return;
    }
    if (written.isErr) {
      // 写入失败必须可见：静默失败会让界面显示一个并未保存的值。
      setState(() {
        _notice = AppLocalizations.of(context)
            .syncSaveFailed(written.errorOrNull!.kind);
      });
    }
  }

  /// 保存地址与用户名（SET-070）。远端目录与设备名一起写回，避免只写一半。
  Future<void> _saveEndpoint() async {
    setState(() {
      _busy = true;
      _notice = '';
    });
    await _write(SettingId.set070, <String, Object?>{
      'url': _urlController.text.trim(),
      'username': _usernameController.text.trim(),
      'remoteDirectory': _remoteDirectory,
      'deviceName': _deviceNameController.text.trim(),
    });
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _urlProblem = validateSyncUrl(_urlController.text);
    });
  }

  /// 保存密码（SET-071 → Keychain）。空输入表示「不改」，而不是「清空密码」。
  Future<void> _savePassword() async {
    final String password = _passwordController.text;
    if (password.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _notice = '';
    });
    final Result<void> saved = await ref
        .read(syncSecretStoreProvider)
        .writePassword(password);
    if (!mounted) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      // 写完立刻清空输入框：内存里也不留一份明文。
      _passwordController.text = '';
      _hasPassword = saved.isOk;
      _notice = saved.isErr
          ? l10n.syncPasswordSaveFailed
          : l10n.syncPasswordSaved;
    });
  }

  /// 只读探测（**不写任何远端内容**）。
  Future<void> _testConnection() async {
    setState(() {
      _busy = true;
      _notice = '';
    });
    final String password = _passwordController.text.isNotEmpty
        ? _passwordController.text
        : await _storedPassword();
    final Result<SyncConnectionProbe> probed = await ref
        .read(syncConnectionProberProvider)
        .probe(
          url: _urlController.text,
          username: _usernameController.text,
          password: password,
          remoteDirectory: _remoteDirectory,
        );
    if (!mounted) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      final AppError? error = probed.errorOrNull;
      final SyncConnectionProbe? probe = probed.valueOrNull;
      _notice = error != null
          ? l10n.syncProbeFailed(error.kind)
          : probe!.reachable
          ? l10n.syncProbeOk(
              probe.directoryExists
                  ? l10n.syncProbeDirExists
                  : l10n.syncProbeDirMissing,
            )
          : l10n.syncProbeFailed(probe.reason ?? 'unknown');
    });
  }

  Future<String> _storedPassword() async {
    final Result<String> read = await ref
        .read(syncSecretStoreProvider)
        .readPassword();
    return read.valueOrNull ?? '';
  }

  Future<void> _syncNow() async {
    setState(() {
      _busy = true;
      _notice = '';
    });
    final SyncRunResult? result = await ref
        .read(syncManagerProvider)
        .request(SyncTrigger.manual);
    if (!mounted) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _notice = result == null
          ? l10n.syncAlreadyRunning
          : describeSyncRun(result, l10n);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final SyncStatusSnapshot status = ref.watch(syncStatusProvider);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.syncSettingsTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncSettingsTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: FluxSpacing.md),
        children: <Widget>[
          if (status.degraded) _DegradedBanner(l10n: l10n),
          if (_notice.isNotEmpty) _InlineNotice(text: _notice),
          _SectionHeader(title: l10n.syncSectionServer),
          _SyncTextField(
            fieldKey: const ValueKey<String>('sync-url'),
            controller: _urlController,
            label: l10n.syncUrlLabel,
            hint: l10n.syncUrlHint,
            errorText: switch (_urlProblem) {
              SyncUrlProblem.empty || SyncUrlProblem.ok => null,
              SyncUrlProblem.malformed => l10n.syncUrlMalformed,
              SyncUrlProblem.scheme => l10n.syncUrlScheme,
              SyncUrlProblem.missingHost => l10n.syncUrlMissingHost,
            },
            onChanged: (String value) =>
                setState(() => _urlProblem = validateSyncUrl(value)),
            enabled: !_busy,
          ),
          _SyncTextField(
            fieldKey: const ValueKey<String>('sync-username'),
            controller: _usernameController,
            label: l10n.syncUsernameLabel,
            enabled: !_busy,
          ),
          _PasswordField(
            controller: _passwordController,
            label: l10n.syncPasswordLabel,
            hint: _hasPassword
                ? l10n.syncPasswordStored
                : l10n.syncPasswordNotStored,
            enabled: !_busy && _secretStoreAvailable,
            unsupportedNote: _secretStoreAvailable
                ? null
                : l10n.syncSecretStoreUnavailable,
          ),
          _SyncTextField(
            fieldKey: const ValueKey<String>('sync-device-name'),
            controller: _deviceNameController,
            label: l10n.syncDeviceNameLabel,
            hint: l10n.syncDeviceNameHint,
            enabled: !_busy,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluxSpacing.md,
              vertical: FluxSpacing.xs,
            ),
            child: Wrap(
              spacing: FluxSpacing.xs,
              runSpacing: FluxSpacing.xs,
              children: <Widget>[
                FilledButton(
                  onPressed: _busy ? null : () => unawaited(_saveEndpoint()),
                  child: Text(l10n.syncSaveEndpoint),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => unawaited(_savePassword()),
                  child: Text(l10n.syncSavePassword),
                ),
                TextButton(
                  key: const ValueKey<String>('sync-test-connection'),
                  onPressed: _busy ? null : () => unawaited(_testConnection()),
                  child: Text(l10n.syncTestConnection),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FluxSpacing.md),
            child: Text(
              l10n.syncTestConnectionHint,
              style: theme.textTheme.bodySmall,
            ),
          ),
          _SectionHeader(title: l10n.syncSectionTriggers),
          SwitchListTile(
            key: const ValueKey<String>('sync-enabled'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: FluxSpacing.md,
            ),
            value: _enabled,
            onChanged: _busy
                ? null
                : (bool value) {
                    setState(() => _enabled = value);
                    unawaited(_setTriggerEnabled(value));
                  },
            title: Text(l10n.syncEnableLabel),
            subtitle: Text(l10n.syncEnableHint),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: FluxSpacing.md,
            ),
            value: _syncOnStart,
            onChanged: _enabled && !_busy
                ? (bool value) {
                    setState(() => _syncOnStart = value);
                    unawaited(_writeTrigger());
                  }
                : null,
            title: Text(l10n.syncOnStartLabel),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: FluxSpacing.md,
            ),
            value: _syncOnChange,
            onChanged: _enabled && !_busy
                ? (bool value) {
                    setState(() => _syncOnChange = value);
                    unawaited(_writeTrigger());
                  }
                : null,
            title: Text(l10n.syncOnChangeLabel),
            subtitle: Text(l10n.syncOnChangeHint(5)),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: FluxSpacing.md,
            ),
            value: _manualOnly,
            onChanged: _enabled && !_busy
                ? (bool value) {
                    setState(() => _manualOnly = value);
                    unawaited(_writeInterval());
                  }
                : null,
            title: Text(l10n.syncManualOnlyLabel),
          ),
          if (!_manualOnly)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: FluxSpacing.md,
              ),
              title: Text(l10n.syncIntervalLabel),
              trailing: DropdownButton<int>(
                value: _intervalMinutes,
                onChanged: _enabled && !_busy
                    ? (int? value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => _intervalMinutes = value);
                        unawaited(_writeInterval());
                      }
                    : null,
                items: <DropdownMenuItem<int>>[
                  for (final int minutes in const <int>[
                    5,
                    15,
                    30,
                    60,
                    120,
                    360,
                  ])
                    DropdownMenuItem<int>(
                      value: minutes,
                      child: Text(l10n.syncIntervalOption(minutes)),
                    ),
                ],
              ),
            ),
          _SectionHeader(title: l10n.syncSectionScope),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FluxSpacing.md),
            child: Text(l10n.syncScopeNotice, style: theme.textTheme.bodySmall),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: FluxSpacing.md,
            ),
            value: _syncCommonSettings,
            onChanged: _enabled && !_busy
                ? (bool value) {
                    setState(() => _syncCommonSettings = value);
                    unawaited(_writeScope());
                  }
                : null,
            title: Text(l10n.syncScopeCommonSettings),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: FluxSpacing.md,
            ),
            value: _syncReadingState,
            onChanged: _enabled && !_busy
                ? (bool value) {
                    setState(() => _syncReadingState = value);
                    unawaited(_writeScope());
                  }
                : null,
            title: Text(l10n.syncScopeReadingState),
          ),
          _ScopeLists(theme: theme, l10n: l10n),
          _SectionHeader(title: l10n.syncSectionStatus),
          _StatusBlock(status: status, l10n: l10n),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluxSpacing.md,
              vertical: FluxSpacing.xs,
            ),
            child: FilledButton.icon(
              key: const ValueKey<String>('sync-now'),
              onPressed: _busy || !_enabled
                  ? null
                  : () => unawaited(_syncNow()),
              icon: const Icon(Icons.sync),
              label: Text(l10n.syncNowButton),
            ),
          ),
          if (status.firstMergePreview case final SyncFirstMergePreview preview)
            _FirstMergeCard(
              preview: preview,
              onConfirm: (SyncConflictPolicy policy) =>
                  unawaited(_confirmFirstMerge(policy)),
            ),
          if (status.conflicts.isNotEmpty)
            _ConflictCard(
              conflicts: status.conflicts,
              onResolve: (Map<String, SyncConflictChoice> choices) =>
                  unawaited(_resolveConflicts(choices)),
            ),
          if (status.pendingRemoteDeletions.isNotEmpty)
            _RemoteDeletionCard(
              deletions: status.pendingRemoteDeletions,
              l10n: l10n,
            ),
        ],
      ),
    );
  }

  Future<void> _writeTrigger() => _write(SettingId.set072, <String, Object?>{
    'enabled': _enabled,
    'syncOnStart': _syncOnStart,
    'syncOnChange': _syncOnChange,
    'changeDebounceSeconds': 5,
  });

  Future<void> _writeInterval() => _write(SettingId.set073, <String, Object?>{
    'intervalMinutes': _intervalMinutes,
    'manualOnly': _manualOnly,
  });

  Future<void> _writeScope() => _write(SettingId.set074, <String, Object?>{
    'commonSettings': _syncCommonSettings,
    'readingState': _syncReadingState,
  });

  /// 打开同步开关：写设置之后重新走一次启动路径（读初始状态 + 按需同步 + 起定时）。
  Future<void> _setTriggerEnabled(bool value) async {
    await _writeTrigger();
    unawaited(ref.read(syncManagerProvider).onLaunch());
  }

  Future<void> _confirmFirstMerge(SyncConflictPolicy policy) async {
    setState(() => _busy = true);
    final SyncRunResult? result = await ref
        .read(syncManagerProvider)
        .confirmFirstMerge(policy: policy);
    if (!mounted) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _notice = result == null
          ? l10n.syncAlreadyRunning
          : describeSyncRun(result, l10n);
    });
  }

  Future<void> _resolveConflicts(
    Map<String, SyncConflictChoice> choices,
  ) async {
    setState(() => _busy = true);
    final SyncRunResult? result = await ref
        .read(syncManagerProvider)
        .resolveConflicts(choices);
    if (!mounted) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _notice = result == null
          ? l10n.syncAlreadyRunning
          : describeSyncRun(result, l10n);
    });
  }
}

/// 降级提示条（架构 5.2：不支持可靠条件写 → 只读拉取）。
class _DegradedBanner extends StatelessWidget {
  const _DegradedBanner({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey<String>('sync-degraded-banner'),
      margin: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xs,
      ),
      padding: const EdgeInsets.all(FluxSpacing.sm),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(FluxRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.lock_outline, color: colors.onTertiaryContainer, size: 18),
          const SizedBox(width: FluxSpacing.xs),
          Expanded(
            child: Text(
              l10n.syncDegradedBanner,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: FluxSpacing.md,
      vertical: FluxSpacing.xs,
    ),
    child: Container(
      padding: const EdgeInsets.all(FluxSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(FluxRadius.card),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FluxSpacing.md,
        FluxSpacing.md,
        FluxSpacing.md,
        FluxSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: FluxSpacing.xxs),
          Divider(color: colors.outline),
        ],
      ),
    );
  }
}

class _SyncTextField extends StatelessWidget {
  const _SyncTextField({
    required this.controller,
    required this.label,
    required this.fieldKey,
    this.hint,
    this.errorText,
    this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final Key fieldKey;
  final String? hint;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: FluxSpacing.md,
      vertical: FluxSpacing.xs,
    ),
    child: TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        errorText: errorText,
      ),
    ),
  );
}

/// 密码输入框：**不回显**已存密码，只由 [hint] 说明是否已保存。
class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.enabled,
    this.unsupportedNote,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool enabled;
  final String? unsupportedNote;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: FluxSpacing.md,
      vertical: FluxSpacing.xs,
    ),
    child: TextField(
      key: const ValueKey<String>('sync-password'),
      controller: controller,
      enabled: enabled,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        helperText: unsupportedNote ?? hint,
      ),
    ),
  );
}

/// 同步范围清单（纳入 = 从 T041 的投影派生；排除 = S 类秘密与 D 类设备项）。
class _ScopeLists extends StatelessWidget {
  const _ScopeLists({required this.theme, required this.l10n});

  final ThemeData theme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final int included = SyncProjection.settingCodes.length;
    final int excluded = SyncProjection.excludedSettingCodes.length;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.syncScopeIncludedTitle, style: theme.textTheme.titleSmall),
          Text(
            l10n.syncScopeIncludedCount(included),
            style: theme.textTheme.bodySmall,
          ),
          Text(l10n.syncScopeFeedNote, style: theme.textTheme.bodySmall),
          const SizedBox(height: FluxSpacing.sm),
          Text(l10n.syncScopeExcludedTitle, style: theme.textTheme.titleSmall),
          Text(
            l10n.syncScopeExcludedCount(excluded),
            style: theme.textTheme.bodySmall,
          ),
          Text(l10n.syncScopeExcludedNote, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 当前状态块。
class _StatusBlock extends StatelessWidget {
  const _StatusBlock({required this.status, required this.l10n});

  final SyncStatusSnapshot status;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      key: const ValueKey<String>('sync-status-block'),
      padding: const EdgeInsets.symmetric(horizontal: FluxSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            describeLastSynced(status.lastSyncedAt, l10n),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: FluxSpacing.xxs),
          Text(
            l10n.syncPendingCount(status.pendingChangeCount),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l10n.syncConflictCount(status.conflicts.length),
            style: theme.textTheme.bodySmall,
          ),
          if (status.capability == WebDavWriteCapability.unknown)
            Text(l10n.syncCapabilityUnknown, style: theme.textTheme.bodySmall),
          if (status.lastErrorReason case final String reason)
            Text(l10n.syncLastError(reason), style: theme.textTheme.bodySmall),
          if (status.running)
            Text(l10n.syncRunning, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 首次合并预览卡片（SET-075：首次预览合并，**默认不覆盖本地**）。
class _FirstMergeCard extends StatelessWidget {
  const _FirstMergeCard({required this.preview, required this.onConfirm});

  final SyncFirstMergePreview preview;
  final void Function(SyncConflictPolicy policy) onConfirm;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey<String>('sync-first-merge-card'),
      margin: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xs,
      ),
      padding: const EdgeInsets.all(FluxSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(FluxRadius.card),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.syncFirstMergeTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: FluxSpacing.xxs),
          Text(
            l10n.syncFirstMergeCounts(
              preview.remoteEntityCount,
              preview.localEntityCount,
            ),
          ),
          Text(l10n.syncFirstMergeDifferences(preview.differenceCount)),
          if (preview.remoteDeletionCount > 0)
            Text(
              l10n.syncFirstMergeRemoteDeletions(preview.remoteDeletionCount),
            ),
          const SizedBox(height: FluxSpacing.xxs),
          Text(
            l10n.syncFirstMergePolicyNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: FluxSpacing.sm),
          Wrap(
            spacing: FluxSpacing.xs,
            runSpacing: FluxSpacing.xs,
            children: <Widget>[
              // 主按钮是「保留本机」（不覆盖本地）：SET-075 明确要求首次不默认覆盖。
              FilledButton(
                key: const ValueKey<String>('sync-first-merge-keep-local'),
                onPressed: () => onConfirm(SyncConflictPolicy.preferLocal),
                child: Text(l10n.syncFirstMergeKeepLocal),
              ),
              OutlinedButton(
                key: const ValueKey<String>('sync-first-merge-use-remote'),
                onPressed: () => onConfirm(SyncConflictPolicy.preferRemote),
                child: Text(l10n.syncFirstMergeUseRemote),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 冲突选版卡片（SET-075：同字段并发人工选版）。
class _ConflictCard extends StatefulWidget {
  const _ConflictCard({required this.conflicts, required this.onResolve});

  final List<SyncMergeConflict> conflicts;
  final void Function(Map<String, SyncConflictChoice> choices) onResolve;

  @override
  State<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends State<_ConflictCard> {
  final Map<String, SyncConflictChoice> _choices =
      <String, SyncConflictChoice>{};

  @override
  void initState() {
    super.initState();
    _seed();
  }

  @override
  void didUpdateWidget(_ConflictCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _seed();
  }

  /// 默认选本机（manual 的语义是「保留本机有效值」），用户可逐条改。
  void _seed() {
    for (final SyncMergeConflict conflict in widget.conflicts) {
      _choices.putIfAbsent(conflict.mapKey, () => SyncConflictChoice.local);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey<String>('sync-conflict-card'),
      margin: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xs,
      ),
      padding: const EdgeInsets.all(FluxSpacing.sm),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(FluxRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.syncConflictTitle(widget.conflicts.length),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: FluxSpacing.xxs),
          Text(l10n.syncConflictNote),
          const SizedBox(height: FluxSpacing.sm),
          for (final SyncMergeConflict conflict in widget.conflicts)
            Padding(
              padding: const EdgeInsets.only(bottom: FluxSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    describeConflictField(conflict),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    l10n.syncConflictBaseValue(
                      describeSyncValue(conflict.baseValue),
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  SegmentedButton<SyncConflictChoice>(
                    segments: <ButtonSegment<SyncConflictChoice>>[
                      ButtonSegment<SyncConflictChoice>(
                        value: SyncConflictChoice.local,
                        label: Text(
                          l10n.syncConflictLocalValue(
                            describeSyncValue(conflict.localValue),
                          ),
                        ),
                      ),
                      ButtonSegment<SyncConflictChoice>(
                        value: SyncConflictChoice.remote,
                        label: Text(
                          l10n.syncConflictRemoteValue(
                            describeSyncValue(conflict.remoteValue),
                          ),
                        ),
                      ),
                    ],
                    selected: <SyncConflictChoice>{
                      _choices[conflict.mapKey] ?? SyncConflictChoice.local,
                    },
                    showSelectedIcon: false,
                    onSelectionChanged: (Set<SyncConflictChoice> selection) {
                      if (selection.isEmpty) {
                        return;
                      }
                      setState(() {
                        _choices[conflict.mapKey] = selection.first;
                      });
                    },
                  ),
                ],
              ),
            ),
          FilledButton(
            key: const ValueKey<String>('sync-conflict-apply'),
            onPressed: () =>
                widget.onResolve(Map<String, SyncConflictChoice>.of(_choices)),
            child: Text(l10n.syncConflictApply),
          ),
        ],
      ),
    );
  }
}

/// 远端破坏性删除的待确认卡片（架构 5.2「未批准不自动清除本地内容」）。
class _RemoteDeletionCard extends StatelessWidget {
  const _RemoteDeletionCard({required this.deletions, required this.l10n});

  final List<SyncDeletion> deletions;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey<String>('sync-remote-deletion-card'),
      margin: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xs,
      ),
      padding: const EdgeInsets.all(FluxSpacing.sm),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(FluxRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.syncRemoteDeletionTitle(deletions.length),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: FluxSpacing.xxs),
          // 本条**没有**确认按钮：应用远端删除属 T045 的跨设备删除集成范围，
          // 这里如实说明「本机数据未清除」，而不是放一个点了没用的按钮。
          Text(l10n.syncRemoteDeletionNote),
          for (final SyncDeletion deletion in deletions)
            Text(
              describeRemoteDeletion(deletion),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
