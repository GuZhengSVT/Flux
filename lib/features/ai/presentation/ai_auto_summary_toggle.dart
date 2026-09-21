// 「缺摘要时自动 AI 摘要」（SET-037）的开关（T034）。
//
// 为什么把开关放在 AI 服务页而不是设置页的「即将推出」列表里：这一项直接决定**会不会
// 自动产生费用**（每次列表刷新补齐缺摘要的文章，每篇一次模型调用）。把它放在「AI 服务」
// 这一页，用户配置模型时就会看到它；放在一个被禁用占位项里等于没有入口。
//
// 三条界面行为：
//   1) **默认关**：首个 build 读到 false 之前开关是关的，不出现「看起来开着但其实没生效」；
//   2) 开关旁边写清代价（每篇单独计费、当天上限、关闭时截取正文兜底）；
//   3) 写入失败如实提示，不显示一个已经打开但没落盘的开关。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/features/settings/application/settings_store.dart';
import 'package:flux/l10n/l10n.dart';

/// SET-037 的开关控件。
class AiAutoSummaryToggle extends ConsumerStatefulWidget {
  /// 构造控件。
  const AiAutoSummaryToggle({super.key});

  @override
  ConsumerState<AiAutoSummaryToggle> createState() =>
      _AiAutoSummaryToggleState();
}

class _AiAutoSummaryToggleState extends ConsumerState<AiAutoSummaryToggle> {
  /// 当前开关值；null 表示尚未读到。
  bool? _enabled;

  /// 是否正在写入。
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final SettingsStore store = ref.read(settingsStoreProvider);
    final Result<Object?> read = await store.readSetting(SettingId.set037);
    if (!mounted) {
      return;
    }
    // 读不到时按**注册表默认值（关）**处理，而不是按 true：默认开会让一次读取失败变成
    // 一连串计费调用。
    final Object? raw = read.isOk ? read.valueOrNull : null;
    setState(() => _enabled = raw is bool ? raw : false);
  }

  Future<void> _toggle(bool value) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final SettingsStore store = ref.read(settingsStoreProvider);
    final Result<Object?> written = await store.writeSetting(
      SettingId.set037,
      value,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      // 写成功才更新界面：写失败时显示旧的（真实的）值，而不是一个没落盘的新值。
      if (written.isOk) {
        _enabled = value;
      }
    });
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            written.isErr
                ? l10n.readingSummaryFailed(written.errorOrNull!.kind)
                : (value
                      ? l10n.readingSummaryAutoToggleDone
                      : l10n.readingSummaryCancelled),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _enabled ?? false,
          onChanged: _busy ? null : _toggle,
          title: Text(l10n.readingSummaryAutoToggleLabel),
          subtitle: Text(l10n.readingSummaryAutoToggleHint),
        ),
      ],
    );
  }
}
