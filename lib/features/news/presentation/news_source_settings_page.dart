// 设置 → 新闻生成页（T036；SET-050–055）。
//
// 这一页的三个界面承诺与 SET 条款一一对应：
//   * **逐源开关是三态**（参与 / 不参与 / 跟随）：把「跟随」折叠成布尔会让用户无法退回默认；
//   * **固定协议段单独展示且无编辑入口**：它不是「另一段用户可改文本」，而是下游引用校验的
//     输入契约（SET-054「不删除固定输出协议」）；
//   * **高级覆盖模式显示差异**：缺了哪些必访站逐个列出来（架构 4.4「不静默消失」）。
//
// 本页**不**做「看起来能用」的事：今日新闻的检索与初稿属 T037–T040，页面底部明确标注归属，
// 不放任何无效按钮。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/features/feeds/application/feed_ports.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import '../application/news_source_config.dart';
import '../application/news_source_providers.dart';

/// 新闻生成设置页。
class NewsSourceSettingsPage extends ConsumerStatefulWidget {
  /// 构造页面。
  const NewsSourceSettingsPage({super.key});

  @override
  ConsumerState<NewsSourceSettingsPage> createState() =>
      _NewsSourceSettingsPageState();
}

class _NewsSourceSettingsPageState
    extends ConsumerState<NewsSourceSettingsPage> {
  NewsConfigState _state = NewsConfigState.initial();
  bool _loading = true;
  bool _busy = false;

  /// 逐源开关（feedId → SET-050 的三态值）。
  Map<int, bool?> _feedSwitches = <int, bool?>{};

  /// 订阅列表（用于逐源小节）。
  List<FeedRecord> _feeds = <FeedRecord>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    // 注意：这里不能在最前面读 AppLocalizations（initState 期间读继承控件会抛断言）。
    // 首次 await 之后 context 已可用，因此 l10n 在真正需要它（下面 feeds 失败分支）时再取。
    final bool globalEnabled = await ref.read(newsGlobalEnabledProvider.future);
    final NewsPromptLanguage language = await ref.read(
      newsPromptLanguageProvider.future,
    );
    final NewsSourceConfigService service = ref.read(
      newsSourceConfigServiceProvider,
    );
    final Result<NewsConfigState> loaded = await service.load(
      globalEnabled: globalEnabled,
      language: language,
    );
    final Result<List<FeedRecord>> feeds = await ref
        .read(feedCatalogProvider)
        .listFeeds();
    if (!mounted) {
      return;
    }
    if (loaded.isErr) {
      setState(() {
        _state = NewsConfigState.initial(
          language: language,
          loadFailure: loaded.errorOrNull,
        );
        _loading = false;
      });
      return;
    }
    setState(() {
      _state = loaded.valueOrNull!;
      _feeds = feeds.valueOrNull ?? const <FeedRecord>[];
      _feedSwitches = <int, bool?>{
        for (final FeedRecord feed in _feeds) feed.id: feed.newsEnabled,
      };
      _loading = false;
    });
    // 订阅读取失败单独提示（不影响配置本身）。
    if (feeds.isErr) {
      _notify(
        AppLocalizations.of(context).newsLoadingFailed(feeds.errorOrNull!.kind),
      );
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 写 SET-050 的总开关。
  Future<void> _setGlobalEnabled(bool value) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Result<Object?> written = await ref
        .read(settingsStoreProvider)
        .writeSetting(SettingId.set050, <String, Object?>{
          'globalEnabled': value,
          'perFeedEnabled': true,
        });
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (written.isOk) {
        _state = _state.copyWith(globalEnabled: value);
      }
    });
    if (written.isErr) {
      _notify(l10n.newsRequiredSaveFailed(written.errorOrNull!.kind));
    }
  }

  /// 写一个源的新闻开关（三态）。
  Future<void> _setFeedNews(int feedId, bool? value) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Result<void> written = await ref
        .read(feedCatalogProvider)
        .setFeedNewsEnabled(feedId: feedId, newsEnabled: value);
    if (!mounted) {
      return;
    }
    if (written.isErr) {
      _notify(l10n.newsRequiredSaveFailed(written.errorOrNull!.kind));
      return;
    }
    setState(
      () => _feedSwitches = <int, bool?>{..._feedSwitches, feedId: value},
    );
  }

  /// 保存必访问网站列表（整体替换）。
  Future<void> _saveSites(List<NewsRequiredSite> sites) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Result<void> written = await ref
        .read(newsSourceConfigProvider)
        .replaceRequiredSites(sites);
    if (!mounted) {
      return;
    }
    setState(() {
      if (written.isOk) {
        _state = _state.copyWith(requiredSites: sites);
      }
    });
    _notify(
      written.isOk
          ? l10n.newsRequiredSaved
          : l10n.newsRequiredSaveFailed(written.errorOrNull!.kind),
    );
  }

  /// 保存一个有序字符串列表。
  Future<void> _saveList(String kind, List<String> values) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Result<void> written = await ref
        .read(newsSourceConfigProvider)
        .replaceList(kind, values);
    if (!mounted) {
      return;
    }
    if (written.isOk) {
      setState(() {
        _state = switch (kind) {
          NewsListCategory.keywords => _state.copyWith(keywords: values),
          NewsListCategory.blockedQueryTerms => _state.copyWith(
            blockedQueryTerms: values,
          ),
          _ => _state.copyWith(excludedTopics: values),
        };
      });
    }
    _notify(
      written.isOk
          ? l10n.newsListSaved
          : l10n.newsListSaveFailed(written.errorOrNull!.kind),
    );
  }

  /// 保存一个新的 prompt 版本。
  Future<void> _savePromptVersion() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NewsPromptSaveOutcome outcome = await ref
        .read(newsSourceConfigServiceProvider)
        .savePromptVersion(
          state: _state,
          mode: _state.mode,
          taskInstruction: _state.taskInstruction,
          outputSpec: _state.outputSpec,
          advancedPrompt: _state.advancedPrompt,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (outcome.version case final NewsPromptVersion version) {
        _state = _state.copyWith(
          versions: NewsSourceConfigService.withVersion(
            _state.versions,
            version,
          ),
        );
      }
    });
    if (outcome.version case final NewsPromptVersion version) {
      _notify(l10n.newsPromptVersionSaved(version.version));
    } else {
      _notify(l10n.newsPromptSaveFailed(outcome.error!.kind));
    }
  }

  /// 载入一个历史版本到编辑区（保存后才成为当前配置）。
  void _loadVersion(NewsPromptVersion version) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _state = _state.copyWith(
        mode: version.mode,
        taskInstruction: version.taskInstruction,
        outputSpec: version.outputSpec,
        advancedPrompt: version.advancedPrompt,
      );
    });
    _notify(l10n.newsPromptVersionLoaded(version.version));
  }

  Future<void> _deleteVersion(NewsPromptVersion version) async {
    final Result<void> removed = await ref
        .read(newsSourceConfigProvider)
        .deletePromptVersion(
          language: _state.language.code,
          version: version.version,
        );
    if (!mounted || removed.isErr) {
      return;
    }
    setState(() {
      _state = _state.copyWith(
        versions: <NewsPromptVersion>[
          for (final NewsPromptVersion v in _state.versions)
            if (v.version != version.version) v,
        ],
      );
    });
  }

  /// 恢复内置模板（**只改编辑区**；用户需显式保存才会成为当前配置）。
  void _restoreDefaults() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _state = _state.copyWith(
        taskInstruction: builtInTaskInstruction(_state.language),
        outputSpec: builtInOutputSpec(_state.language),
      );
    });
    _notify(l10n.newsPromptRestored);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.newsPageTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: FluxSpacing.md,
                vertical: FluxSpacing.md,
              ),
              children: <Widget>[
                if (_state.loadFailure case final AppError error)
                  StatusBanner(
                    severity: StatusBannerSeverity.warning,
                    message: l10n.newsLoadingFailed(error.kind),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _state.globalEnabled,
                  onChanged: _busy
                      ? null
                      : (bool v) => unawaited(_setGlobalEnabled(v)),
                  title: Text(l10n.newsGlobalSwitchLabel),
                  subtitle: Text(l10n.newsGlobalSwitchHint),
                ),
                const Divider(),
                _SectionTitle(
                  title: l10n.newsFeedSectionTitle,
                  hint: l10n.newsFeedSectionHint,
                ),
                if (_feeds.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FluxSpacing.md),
                    child: Text(l10n.newsFeedEmpty),
                  )
                else
                  for (final FeedRecord feed in _feeds)
                    _FeedNewsSwitch(
                      feed: feed,
                      value: _feedSwitches[feed.id],
                      onChanged: (bool? v) =>
                          unawaited(_setFeedNews(feed.id, v)),
                    ),
                const Divider(),
                _SectionTitle(
                  title: l10n.newsRequiredSectionTitle,
                  hint: l10n.newsRequiredSectionHint,
                ),
                _RequiredSitesEditor(
                  sites: _state.requiredSites,
                  onChanged: (List<NewsRequiredSite> sites) =>
                      unawaited(_saveSites(sites)),
                ),
                const Divider(),
                _StringListEditor(
                  title: l10n.newsListKeywordsTitle,
                  hint: l10n.newsListKeywordsHint,
                  values: _state.keywords,
                  onChanged: (List<String> values) =>
                      unawaited(_saveList(NewsListCategory.keywords, values)),
                ),
                _StringListEditor(
                  title: l10n.newsListBlockedTitle,
                  hint: l10n.newsListBlockedHint,
                  values: _state.blockedQueryTerms,
                  onChanged: (List<String> values) => unawaited(
                    _saveList(NewsListCategory.blockedQueryTerms, values),
                  ),
                ),
                _StringListEditor(
                  title: l10n.newsListTopicsTitle,
                  hint: l10n.newsListTopicsHint,
                  values: _state.excludedTopics,
                  onChanged: (List<String> values) => unawaited(
                    _saveList(NewsListCategory.excludedTopics, values),
                  ),
                ),
                const Divider(),
                _SectionTitle(title: l10n.newsPromptModeTitle),
                SegmentedButton<NewsPromptMode>(
                  segments: <ButtonSegment<NewsPromptMode>>[
                    ButtonSegment<NewsPromptMode>(
                      value: NewsPromptMode.composed,
                      label: Text(l10n.newsPromptModeComposed),
                    ),
                    ButtonSegment<NewsPromptMode>(
                      value: NewsPromptMode.advancedOverride,
                      label: Text(l10n.newsPromptModeAdvanced),
                    ),
                  ],
                  selected: <NewsPromptMode>{_state.mode},
                  onSelectionChanged: (Set<NewsPromptMode> selection) {
                    setState(
                      () => _state = _state.copyWith(mode: selection.first),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: FluxSpacing.xs),
                  child: Text(
                    _state.mode == NewsPromptMode.composed
                        ? l10n.newsPromptModeComposedHint
                        : l10n.newsPromptModeAdvancedHint,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                if (_state.mode == NewsPromptMode.advancedOverride)
                  _TextEditor(
                    label: l10n.newsPromptAdvancedField,
                    initial: _state.advancedPrompt,
                    minLines: 5,
                    onChanged: (String value) {
                      setState(
                        () => _state = _state.copyWith(advancedPrompt: value),
                      );
                    },
                  ),
                if (_state.mode == NewsPromptMode.composed) ...<Widget>[
                  _TextEditor(
                    label: l10n.newsPromptTaskField,
                    initial: _state.taskInstruction,
                    hint: builtInTaskInstruction(_state.language),
                    onChanged: (String value) {
                      setState(
                        () => _state = _state.copyWith(taskInstruction: value),
                      );
                    },
                  ),
                  _TextEditor(
                    label: l10n.newsPromptSpecField,
                    initial: _state.outputSpec,
                    hint: builtInOutputSpec(_state.language),
                    minLines: 4,
                    onChanged: (String value) {
                      setState(
                        () => _state = _state.copyWith(outputSpec: value),
                      );
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _restoreDefaults,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: Text(l10n.newsPromptRestoreDefaults),
                    ),
                  ),
                ],
                _FixedProtocolSection(
                  language: _state.language,
                  heading: l10n.newsPromptCitationFixed,
                ),
                if (_state.diff.hasWarning)
                  StatusBanner(
                    severity: StatusBannerSeverity.warning,
                    message: l10n.newsPromptDiffMissing(
                      _state.diff.missingSites
                          .map((NewsRequiredSite s) => s.name)
                          .join('、'),
                    ),
                  ),
                if (_state.mode == NewsPromptMode.advancedOverride &&
                    !_state.diff.hasCitationProtocol)
                  StatusBanner(
                    severity: StatusBannerSeverity.info,
                    message: l10n.newsPromptDiffCitationMissing,
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => unawaited(_savePromptVersion()),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(l10n.newsPromptSaveVersion),
                  ),
                ),
                const SizedBox(height: FluxSpacing.md),
                _SectionTitle(title: l10n.newsPromptVersionsTitle),
                if (_state.versions.isEmpty)
                  Text(l10n.newsPromptVersionNone)
                else
                  for (final NewsPromptVersion version in _state.versions)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        l10n.newsPromptVersionItem(
                          version.version,
                          version.mode == NewsPromptMode.composed
                              ? l10n.newsPromptModeComposed
                              : l10n.newsPromptModeAdvanced,
                        ),
                      ),
                      subtitle: version.note == null
                          ? null
                          : Text(version.note!),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          TextButton(
                            onPressed: () => _loadVersion(version),
                            child: Text(l10n.newsPromptVersionUse),
                          ),
                          IconButton(
                            tooltip: l10n.newsPromptVersionDelete,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => unawaited(_deleteVersion(version)),
                          ),
                        ],
                      ),
                    ),
                const Divider(),
                _SectionTitle(title: l10n.newsEffectiveQueriesTitle),
                if (_state.effectiveQueries.isEmpty)
                  Text(l10n.newsEffectiveQueriesEmpty)
                else
                  Wrap(
                    spacing: FluxSpacing.xs,
                    children: <Widget>[
                      for (final String query in _state.effectiveQueries)
                        Chip(label: Text(query)),
                    ],
                  ),
                const Divider(),
                _SectionTitle(title: l10n.newsPromptPreviewTitle),
                Text(
                  l10n.newsPromptPreviewHint,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: FluxSpacing.xs),
                Container(
                  padding: const EdgeInsets.all(FluxSpacing.sm),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(FluxRadius.card),
                  ),
                  child: SelectableText(_state.resolvedPrompt),
                ),
                const SizedBox(height: FluxSpacing.md),
                Text(
                  l10n.newsPlannedNotice,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: FluxSpacing.xl),
              ],
            ),
    );
  }
}

/// 小节标题 + 说明。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: FluxSpacing.sm,
        bottom: FluxSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleSmall),
          if (hint case final String value)
            Padding(
              padding: const EdgeInsets.only(top: FluxSpacing.xxs),
              child: Text(value, style: theme.textTheme.labelSmall),
            ),
        ],
      ),
    );
  }
}

/// 逐源新闻开关（三态）。
class _FeedNewsSwitch extends StatelessWidget {
  const _FeedNewsSwitch({
    required this.feed,
    required this.value,
    required this.onChanged,
  });

  final FeedRecord feed;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(feed.name),
      subtitle: Text(
        feed.enabled ? l10n.newsFeedSectionHint : l10n.newsFeedDisabledHint,
      ),
      trailing: SegmentedButton<int>(
        // 三态用 0/1/2 编码：null 不能直接进 Set<Object?> 的选中集合（相等性语义易错）。
        segments: <ButtonSegment<int>>[
          ButtonSegment<int>(value: 0, label: Text(l10n.newsFeedFollow)),
          ButtonSegment<int>(value: 1, label: Text(l10n.newsFeedInclude)),
          ButtonSegment<int>(value: 2, label: Text(l10n.newsFeedExclude)),
        ],
        selected: <int>{value == null ? 0 : (value! ? 1 : 2)},
        onSelectionChanged: (Set<int> selection) {
          final int picked = selection.first;
          onChanged(picked == 0 ? null : picked == 1);
        },
      ),
    );
  }
}

/// 必访问网站编辑器（增删改排序）。
class _RequiredSitesEditor extends StatefulWidget {
  const _RequiredSitesEditor({required this.sites, required this.onChanged});

  final List<NewsRequiredSite> sites;
  final ValueChanged<List<NewsRequiredSite>> onChanged;

  @override
  State<_RequiredSitesEditor> createState() => _RequiredSitesEditorState();
}

class _RequiredSitesEditorState extends State<_RequiredSitesEditor> {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.sites.isEmpty)
          Text(l10n.newsRequiredEmpty)
        else
          for (int i = 0; i < widget.sites.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Checkbox(
                value: widget.sites[i].enabled,
                onChanged: (bool? on) =>
                    _replace(i, widget.sites[i].copyWith(enabled: on ?? false)),
              ),
              title: Text(widget.sites[i].name),
              subtitle: Text(widget.sites[i].url),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: l10n.newsRequiredAdd,
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    onPressed: i == 0 ? null : () => _move(i, i - 1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    onPressed: i == widget.sites.length - 1
                        ? null
                        : () => _move(i, i + 1),
                  ),
                  IconButton(
                    tooltip: l10n.newsPromptVersionDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _remove(i),
                  ),
                ],
              ),
            ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => unawaited(_addDialog()),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.newsRequiredAdd),
          ),
        ),
      ],
    );
  }

  void _replace(int index, NewsRequiredSite site) {
    final List<NewsRequiredSite> next = List<NewsRequiredSite>.of(widget.sites);
    next[index] = site;
    widget.onChanged(next);
  }

  void _remove(int index) {
    final List<NewsRequiredSite> next = List<NewsRequiredSite>.of(widget.sites)
      ..removeAt(index);
    widget.onChanged(next);
  }

  void _move(int from, int to) {
    final List<NewsRequiredSite> next = List<NewsRequiredSite>.of(widget.sites);
    final NewsRequiredSite item = next.removeAt(from);
    next.insert(to, item);
    widget.onChanged(next);
  }

  Future<void> _addDialog() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextEditingController name = TextEditingController();
    final TextEditingController url = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.newsRequiredAdd),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: l10n.newsRequiredNameField,
              ),
            ),
            TextField(
              controller: url,
              decoration: InputDecoration(labelText: l10n.newsRequiredUrlField),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.searchDeleteCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.searchSaveService),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final String nameText = name.text.trim();
    final String urlText = url.text.trim();
    if (nameText.isEmpty || urlText.isEmpty) {
      return;
    }
    widget.onChanged(<NewsRequiredSite>[
      ...widget.sites,
      NewsRequiredSite(
        name: nameText,
        url: urlText,
        sortOrder: widget.sites.length,
      ),
    ]);
  }
}

/// 有序字符串列表编辑器。
class _StringListEditor extends StatefulWidget {
  const _StringListEditor({
    required this.title,
    required this.hint,
    required this.values,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_StringListEditor> createState() => _StringListEditorState();
}

class _StringListEditorState extends State<_StringListEditor> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionTitle(title: widget.title, hint: widget.hint),
        if (widget.values.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: FluxSpacing.xs),
            child: Text(l10n.newsListEmpty),
          )
        else
          Wrap(
            spacing: FluxSpacing.xs,
            children: <Widget>[
              for (int i = 0; i < widget.values.length; i++)
                InputChip(
                  label: Text(widget.values[i]),
                  onDeleted: () {
                    final List<String> next = List<String>.of(widget.values)
                      ..removeAt(i);
                    widget.onChanged(next);
                  },
                ),
            ],
          ),
        TextField(
          controller: _controller,
          decoration: InputDecoration(hintText: l10n.newsListAddHint),
          onSubmitted: (String value) {
            final String text = value.trim();
            if (text.isEmpty) {
              return;
            }
            widget.onChanged(<String>[...widget.values, text]);
            _controller.clear();
          },
        ),
      ],
    );
  }
}

/// 固定协议段（只读展示）。
class _FixedProtocolSection extends StatelessWidget {
  const _FixedProtocolSection({required this.language, required this.heading});

  final NewsPromptLanguage language;
  final String heading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            top: FluxSpacing.sm,
            bottom: FluxSpacing.xxs,
          ),
          child: Text(heading, style: theme.textTheme.titleSmall),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(FluxSpacing.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(FluxRadius.card),
          ),
          // SelectableText 而不是 TextField：这一段没有编辑入口，用户能做的只有核对与复制。
          child: SelectableText(newsCitationProtocol(language)),
        ),
      ],
    );
  }
}

/// 多行文本编辑（带内置模板提示）。
class _TextEditor extends StatefulWidget {
  const _TextEditor({
    required this.label,
    required this.initial,
    required this.onChanged,
    this.hint,
    this.minLines = 3,
  });

  final String label;
  final String initial;
  final String? hint;
  final int minLines;
  final ValueChanged<String> onChanged;

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void didUpdateWidget(_TextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（载入版本 / 恢复默认）改了值时同步到输入框：否则用户看到的还是旧文本，
    // 而状态里已经是新值——两者不一致会让「保存」保存下他看不到的内容。
    if (widget.initial != oldWidget.initial &&
        _controller.text != widget.initial) {
      _controller.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FluxSpacing.sm),
      child: TextField(
        controller: _controller,
        minLines: widget.minLines,
        maxLines: widget.minLines + 4,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}
