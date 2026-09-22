// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'Flux';

  @override
  String get appTagline => '本地优先的新闻与 RSS 阅读器';

  @override
  String placeholderPageBody(String tasks) {
    return '本页目前只有应用壳占位，没有接入数据与交互。计划任务：$tasks。';
  }

  @override
  String get navToday => '今日新闻';

  @override
  String get navReading => 'RSS 阅读';

  @override
  String get navMine => '我的';

  @override
  String get emptyNoFeedsTitle => '还没有订阅';

  @override
  String get emptyNoFeedsBody =>
      '添加订阅或导入 OPML 之后，文章会出现在这里。订阅相关的界面与用例由 T013–T016 交付。';

  @override
  String get emptyAllReadTitle => '所有文章已读';

  @override
  String get emptyAllReadBody => '当前筛选条件下没有未读文章。可以切到稍后再读或收藏查看已处理的内容。';

  @override
  String get emptyNoResultsTitle => '没有匹配结果';

  @override
  String get emptyNoResultsBody => '换个关键词，或调整搜索范围与筛选条件后重试。本地全文检索由 T022 交付。';

  @override
  String get shellDatabaseFailedTitle => '本地数据库打不开';

  @override
  String get shellDatabaseFailedBody =>
      '本次运行只能显示壳层：语言与主题改动不会被保存。原始数据库文件保持不动，请检查磁盘空间与文件权限后重启。';

  @override
  String onboardingStepIndicator(int current, int total) {
    return '第 $current 步 / 共 $total 步';
  }

  @override
  String get onboardingSkip => '跳过';

  @override
  String get onboardingBack => '上一步';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingStart => '开始使用';

  @override
  String get onboardingWelcomeTitle => '欢迎使用 Flux';

  @override
  String get onboardingWelcomeBody =>
      '订阅、正文、阅读状态和总结都保存在你自己的设备上。Flux 没有账号，也没有业务后端；AI、联网搜索和 WebDAV 由你自行配置并自行承担费用。首次向某个服务发送数据前，都会逐项告知接收者与允许的能力。';

  @override
  String get onboardingOfflineNote => '离线阅读与本地搜索不依赖 AI，可以长期离线使用。';

  @override
  String get onboardingFeedsTitle => '添加订阅';

  @override
  String get onboardingFeedsBody =>
      '单条添加、编辑、分组与 OPML 批量导入由 T013–T016 交付。现在还没有可用的导入界面，因此本步骤不创建任何订阅，也不会伪造示例数据；你可以直接跳过，进入应用后再添加。';

  @override
  String get onboardingFeedsSkipNote => '跳过不会影响后续功能，也不会写入任何订阅。';

  @override
  String get onboardingAiTitle => 'AI 与搜索（可选）';

  @override
  String get onboardingAiBody =>
      '未配置 AI 与搜索服务也能完整使用离线阅读、本地搜索和阅读统计。提供商协议、模型管理、凭据、连通性测试与费用提醒由 T025/T031 交付；在此之前本步骤不请求任何凭据，也不发起任何请求。';

  @override
  String get onboardingAiSkipNote => '没有配置 AI 也可以直接开始使用：所有本地功能都不受影响。';

  @override
  String get onboardingAppearanceNote =>
      '界面语言与主题可以随时在「我的 → 阅读与外观」修改；切换语言不会改写已经生成的 AI 输出。';

  @override
  String get settingsTitle => '我的';

  @override
  String get settingsSectionShell => '阅读与外观';

  @override
  String get settingsSectionAppearancePlanned => '尚未实现的阅读与外观设置';

  @override
  String get settingsSectionAbout => '关于';

  @override
  String get settingsLanguageLabel => '界面语言';

  @override
  String get settingsLanguageId => 'SET-001';

  @override
  String get settingsLanguageHint => '跟随系统时按各设备的系统语言解析，无匹配时回退英文。文章不会自动翻译。';

  @override
  String get settingsThemeLabel => '主题';

  @override
  String get settingsThemeId => 'SET-002';

  @override
  String get settingsThemeHint => '浅色、深色与跟随系统；跟随系统时各设备独立解析。';

  @override
  String get settingsOptionFollowSystem => '跟随系统';

  @override
  String get settingsOptionChinese => '简体中文';

  @override
  String get settingsOptionEnglish => 'English';

  @override
  String get settingsOptionLight => '浅色';

  @override
  String get settingsOptionDark => '深色';

  @override
  String get settingsWriteFailed => '改动没有保存（写入失败或值被拒绝）。当前显示的仍是已保存的值。';

  @override
  String get settingsPlannedNotice =>
      '以下设置项尚未实现。为避免做成假的可用开关，这里只列出名称、编号与分类，不能修改；对应界面在各自任务中交付。';

  @override
  String get settingsPlannedBadge => '即将推出';

  @override
  String get settingsClassificationCommon => '共通·可同步';

  @override
  String get settingsClassificationDevice => '设备专属';

  @override
  String get settingsClassificationSecret => '秘密·仅本机';

  @override
  String get settingsItemSet003 => '主题背景图';

  @override
  String get settingsItemSet004 => '背景不透明度、模糊与亮度';

  @override
  String get settingsItemSet005 => '界面、正文与新闻字体';

  @override
  String get settingsItemSet006 => '界面、正文与新闻字号';

  @override
  String get settingsItemSet007 => '纸张背景、阅读字体与字号倍率';

  @override
  String get settingsItemSet008 => '列表视图与桌面栏宽';

  @override
  String get settingsItemSet009 => '列表排序、筛选与返回位置';

  @override
  String get settingsItemSet010 => '显示正文后自动标为已读';

  @override
  String get settingsItemSet011 => '翻译目标语言与生成语言';

  @override
  String get settingsItemSet012 => '自动加载远程图片';

  @override
  String get settingsItemSet013 => '允许在计费网络下载媒体';

  @override
  String get settingsItemSet014 => '减少动态效果';

  @override
  String get settingsItemSet015 => '阅读统计与空闲暂停时间';

  @override
  String get settingsItemSet016 => '专注阅读布局';

  @override
  String settingsItemPlannedTask(String task) {
    return '计划任务 $task';
  }

  @override
  String get aboutVersionLabel => '版本';

  @override
  String aboutVersionValue(String version) {
    return '$version（M0 骨架版本号占位，发行版本在 T054 确定）';
  }

  @override
  String get aboutLicenseLabel => '许可';

  @override
  String get aboutLicenseValue => 'MIT License';

  @override
  String get aboutLicenseNote => '仓库内的 LICENSE 为 MIT；第三方依赖与原创素材的完整声明在 T054 落地。';

  @override
  String get aboutRepositoryLabel => 'GitHub 仓库';

  @override
  String get aboutRepositoryValue => 'https://github.com/GuZhengSVT/Flux';

  @override
  String get aboutIssueLabel => '问题反馈';

  @override
  String get aboutIssueValue => 'https://github.com/GuZhengSVT/Flux/issues';

  @override
  String get aboutDeveloperLabel => '开发者';

  @override
  String get aboutDeveloperValue => 'GuZhengSVT';

  @override
  String get aboutNotConfigured => '未配置';

  @override
  String get aboutReadOnlyNote =>
      '关于信息为只读发布元数据（SET-084）。仓库与 Issue 地址尚未在本机配置，因此显示「未配置」，不提供猜测的地址；检查更新由 T053 交付。';

  @override
  String get aboutUnverifiedNote =>
      '仓库与 Issue 地址取自本机内置的发布元数据，并在 2026-09-21 用 GitHub 公开接口核实存在、未归档且已开启 Issue；地址为空时显示「未配置」，不猜测。检查更新与 Release 链接由 T053 交付。';

  @override
  String get readingStateLabel => '阅读状态';

  @override
  String get readingStateUnread => '未读';

  @override
  String get readingStateRead => '已读';

  @override
  String get readingStateLater => '稍后再读';

  @override
  String get readingStateControlHint => '点按或按回车循环切换未读、已读、稍后再读';

  @override
  String readingStateSwitched(String state) {
    return '阅读状态已切换为$state';
  }

  @override
  String get favoriteToggleLabel => '收藏';

  @override
  String get favoriteAddLabel => '加入收藏';

  @override
  String get favoriteRemoveLabel => '取消收藏';

  @override
  String get favoriteToggleHint => '收藏独立于阅读状态，不改变未读、已读或稍后再读';

  @override
  String get featuredBadgeLabel => '加精';

  @override
  String get controlLoadingLabel => '正在加载';

  @override
  String get controlSuccessLabel => '操作成功';

  @override
  String get controlErrorLabel => '操作失败';

  @override
  String get controlDisabledLabelSuffix => '不可用';

  @override
  String get subscriptionManagerTitle => '订阅管理';

  @override
  String get subscriptionManagerNotice => '本页管理订阅与分组；文章列表与批量状态操作属 T017–T019。';

  @override
  String get subscriptionGroupsSection => '分组与订阅';

  @override
  String get subscriptionAddFeed => '添加订阅';

  @override
  String get subscriptionAddFeedTitle => '添加订阅';

  @override
  String get subscriptionFeedUrlLabel => '订阅地址';

  @override
  String get subscriptionFeedUrlHint =>
      '完整的 http/https 地址，例如 https://example.com/feed.xml';

  @override
  String get subscriptionPreviewAction => '预览';

  @override
  String get subscriptionPreviewTitle => '预览结果';

  @override
  String get subscriptionPreviewFormat => '格式';

  @override
  String subscriptionPreviewEntries(int count) {
    return '$count 篇文章';
  }

  @override
  String subscriptionPreviewRejected(int count) {
    return '$count 条被跳过';
  }

  @override
  String get subscriptionPreviewNormalized => '规范化地址';

  @override
  String get subscriptionPreviewDuplicateTitle => '该地址已订阅';

  @override
  String subscriptionPreviewDuplicateBody(String name) {
    return '已存在该地址的订阅「$name」。原有的分组、加精与刷新设置都保留，没有做任何改动。';
  }

  @override
  String get subscriptionConfirmAdd => '确认添加';

  @override
  String get subscriptionCancel => '取消';

  @override
  String get subscriptionSave => '保存';

  @override
  String get subscriptionClose => '关闭';

  @override
  String get subscriptionFeedNameLabel => '显示名称';

  @override
  String get subscriptionFeedGroupLabel => '归属分组';

  @override
  String subscriptionAddSuccess(String name, int count) {
    return '已添加「$name」，导入 $count 篇文章';
  }

  @override
  String subscriptionAddSuccessEmpty(String name) {
    return '已添加「$name」，源里暂时没有可导入的文章';
  }

  @override
  String get subscriptionErrorInvalidUrl => '地址不合法：请输入完整的 http/https 订阅地址';

  @override
  String get subscriptionErrorNetwork => '抓取失败：请检查网络后重试';

  @override
  String get subscriptionErrorParse => '解析失败：该地址的内容不是可解析的 RSS/Atom';

  @override
  String get subscriptionErrorStorage => '本地存储失败，本次改动没有保存';

  @override
  String get subscriptionNewGroup => '新建分组';

  @override
  String get subscriptionGroupNameLabel => '分组名称';

  @override
  String get subscriptionGroupRename => '重命名';

  @override
  String get subscriptionGroupDelete => '删除分组';

  @override
  String get subscriptionGroupPin => '置顶分组';

  @override
  String get subscriptionGroupUnpin => '取消置顶';

  @override
  String get subscriptionPinnedBadge => '置顶';

  @override
  String get subscriptionReservedGroupNote => '保留分组：不能删除或改名，其中订阅可移动';

  @override
  String subscriptionGroupDeleteTitle(String name) {
    return '删除分组「$name」';
  }

  @override
  String subscriptionGroupDeleteBody(int count) {
    return '该分组下有 $count 个订阅。请选择处理方式：';
  }

  @override
  String get subscriptionGroupDeleteMoveOption => '移动到未分类';

  @override
  String get subscriptionGroupDeleteMoveHint => '订阅与文章都保留，只改归属';

  @override
  String get subscriptionGroupDeleteFeedsOption => '删除其中的订阅';

  @override
  String get subscriptionGroupDeleteFeedsHint => '保留收藏选项在 T018 生效；本期只记录，不会真正删除';

  @override
  String subscriptionGroupDeleteFeedsPending(int count) {
    return '已记录 $count 个待处理订阅；保留收藏规则在 T018 生效，本期没有删除任何数据';
  }

  @override
  String subscriptionGroupDeleted(String name, int count) {
    return '已删除分组「$name」，$count 个订阅已移动到未分类';
  }

  @override
  String get subscriptionFeedMenu => '订阅操作';

  @override
  String get subscriptionGroupMenu => '分组操作';

  @override
  String get subscriptionFeedRename => '重命名订阅';

  @override
  String get subscriptionFeedEdit => '编辑订阅';

  @override
  String get subscriptionFeedMove => '移动到分组';

  @override
  String get subscriptionFeedEnable => '启用自动刷新';

  @override
  String get subscriptionFeedDisable => '停用自动刷新';

  @override
  String get subscriptionFeedDisabledBadge => '已停用';

  @override
  String get subscriptionFeedFavorite => '加精';

  @override
  String get subscriptionFeedUnfavorite => '取消加精';

  @override
  String subscriptionUnreadCount(int count) {
    return '$count 未读';
  }

  @override
  String get subscriptionEmptyTitle => '还没有订阅';

  @override
  String get subscriptionEmptyBody => '点击「添加订阅」输入 RSS/Atom 地址；批量导入与导出属 T015。';

  @override
  String get subscriptionRefreshPolicyTitle => '刷新策略';

  @override
  String get subscriptionRefreshPolicyNote =>
      '这里只保存设置；后台定时调度在 T016 落地，本期不会自动联网。';

  @override
  String get subscriptionGlobalRefreshLabel => '全局自动刷新';

  @override
  String get subscriptionGlobalIntervalLabel => '刷新间隔';

  @override
  String get subscriptionStartupRefreshLabel => '启动时刷新';

  @override
  String get subscriptionIntervalInherit => '继承全局';

  @override
  String get subscriptionIntervalManual => '手动';

  @override
  String subscriptionIntervalMinutes(String minutes) {
    return '$minutes 分钟';
  }

  @override
  String get subscriptionFeedIntervalLabel => '该源刷新间隔';

  @override
  String subscriptionMoveToGroupTitle(String name) {
    return '把「$name」移动到分组';
  }

  @override
  String get subscriptionReorderHint => '拖动把手排序；聚焦把手后用上下方向键也能移动';

  @override
  String subscriptionCollapsedCount(int count) {
    return '$count 个订阅（已折叠）';
  }

  @override
  String subscriptionGroupHeaderLabel(String name, int count) {
    return '$name，$count 个订阅';
  }

  @override
  String subscriptionFeedRowLabel(String name, int count) {
    return '$name，$count 未读';
  }

  @override
  String get subscriptionEnabledNote => '已停用：自动刷新会跳过该源（SET-022）';

  @override
  String get subscriptionFavoriteNote => '加精只影响显示，不参与新闻选材（SET-023）';

  @override
  String get subscriptionDragHandleLabel => '拖动或按上下方向键调整顺序';

  @override
  String get subscriptionMoveUp => '上移';

  @override
  String get subscriptionMoveDown => '下移';

  @override
  String get subscriptionFeedRenameTitle => '重命名订阅';

  @override
  String get subscriptionGroupRenameTitle => '重命名分组';

  @override
  String get subscriptionNewGroupTitle => '新建分组';

  @override
  String get subscriptionInvalidGroupName => '分组名称不能为空';

  @override
  String get subscriptionInvalidFeedName => '订阅名称不能为空';

  @override
  String get subscriptionUngrouped => '未分组';

  @override
  String get subscriptionReservedGroupName => '未分类';

  @override
  String get opmlPageTitle => '导入与导出 OPML';

  @override
  String get opmlPageNotice => '导入与导出只交换标准订阅地址、名称与分组；不含 Flux 内部 ID、加精或阅读状态。';

  @override
  String get opmlPickFile => '选择 OPML 文件';

  @override
  String get opmlRepick => '换一个文件';

  @override
  String opmlFileName(String name) {
    return '文件：$name';
  }

  @override
  String get opmlPreviewTitle => '导入预览';

  @override
  String opmlPreviewSummary(int total, int added, int duplicate, int invalid) {
    return '共 $total 项：新增 $added、重复 $duplicate、无效 $invalid';
  }

  @override
  String get opmlStrategyLabel => '分组处理';

  @override
  String get opmlStrategyUncategorized => '全部放入未分类';

  @override
  String get opmlStrategyKeepGroups => '保留文件分组';

  @override
  String get opmlStrategyHint => '默认全部放入未分类；保留文件分组会按文件里的层级新建分组。';

  @override
  String get opmlStatusAdded => '新增';

  @override
  String get opmlStatusDuplicate => '重复';

  @override
  String get opmlStatusInvalid => '无效';

  @override
  String get opmlStatusImported => '已导入';

  @override
  String get opmlStatusFailed => '失败';

  @override
  String get opmlDuplicatesNote => '重复项已存在，导入时会保留它们原有的分组、加精与刷新设置（不重置状态）。';

  @override
  String get opmlInvalidNote => '无效项无法导入：地址缺失或不是可用的 http/https 地址。';

  @override
  String get opmlNothingToImport => '这份文件没有可导入的订阅。';

  @override
  String get opmlStartImport => '开始导入';

  @override
  String get opmlImporting => '正在导入…';

  @override
  String get opmlResultTitle => '导入结果';

  @override
  String opmlResultSummary(
    int imported,
    int duplicate,
    int failed,
    int invalid,
    int articles,
  ) {
    return '成功 $imported、重复 $duplicate、失败 $failed、无效 $invalid；导入文章 $articles 篇';
  }

  @override
  String opmlRetryFailed(int count) {
    return '重试失败项（$count）';
  }

  @override
  String get opmlRetryHint => '只重跑失败的条目；已成功的不会被重新请求，也不会新建重复订阅。';

  @override
  String get opmlRetryNone => '没有可重试的失败项';

  @override
  String get opmlExportTitle => '导出 OPML';

  @override
  String get opmlExportBody => '把全部订阅导出为标准 OPML 文件，可在其他阅读器里导入。';

  @override
  String get opmlExportAction => '导出为 OPML';

  @override
  String opmlExportDone(int count, String path) {
    return '已导出 $count 个订阅到 $path';
  }

  @override
  String get opmlExportEmpty => '当前没有任何订阅，导出的文件只含空的 body。';

  @override
  String get opmlExportSecretNote =>
      '导出会移除地址里明确的秘密参数（token、api_key、password 等）与账号密码；这些订阅在目标设备上需要重新填写凭据。';

  @override
  String opmlExportSecretRemoved(int count, String names) {
    return '已从 $count 处地址移除秘密参数（$names）；这些订阅在其它设备上需要补填凭据。';
  }

  @override
  String opmlExportError(String reason) {
    return '导出失败：$reason';
  }

  @override
  String opmlImportError(String reason) {
    return '导入失败：$reason';
  }

  @override
  String get opmlCancel => '取消';

  @override
  String opmlEntryIndex(int index) {
    return '第 $index 项';
  }

  @override
  String opmlEntryGroup(String path) {
    return '分组：$path';
  }

  @override
  String get opmlMenuEntry => '导入 / 导出 OPML';

  @override
  String get readingRefresh => '刷新';

  @override
  String get readingRefreshing => '正在刷新…';

  @override
  String readingRefreshDone(int inserted, int checked) {
    return '刷新完成：新增 $inserted 篇（检查 $checked 个源）';
  }

  @override
  String readingRefreshNotModified(int checked) {
    return '刷新完成：源暂无更新（检查 $checked 个源）';
  }

  @override
  String readingRefreshPartial(int inserted, int failed) {
    return '刷新完成：新增 $inserted 篇，$failed 个源失败（旧内容已保留）';
  }

  @override
  String get readingRefreshOffline => '当前无网络，未发起刷新；网络恢复后会自动重试';

  @override
  String get readingRefreshMetered => '当前是计费网络，已在设置中关闭计费网络请求，因此未刷新';

  @override
  String readingRefreshFailed(String reason) {
    return '刷新失败：$reason';
  }

  @override
  String get readingFilterAll => '全部';

  @override
  String get readingFilterUnread => '未读';

  @override
  String get readingFilterLater => '稍后再读';

  @override
  String get readingFilterFavorite => '收藏';

  @override
  String get readingFeedFilterAll => '全部来源';

  @override
  String get readingEmptyTitle => '这里还没有文章';

  @override
  String get readingEmptyBody => '在「我的 → 订阅管理」添加订阅，或在顶部点「刷新」抓取内容。';

  @override
  String get readingEmptyFilteredTitle => '当前筛选下没有文章';

  @override
  String get readingEmptyFilteredBody => '换一个筛选条件，或有新文章后再回来看看。';

  @override
  String readingPageIndicator(int page, int pages, int total) {
    return '第 $page / $pages 页（共 $total 篇）';
  }

  @override
  String get readingPreviousPage => '上一页';

  @override
  String get readingNextPage => '下一页';

  @override
  String readingLoadedCount(int loaded, int total) {
    return '已加载 $loaded / $total 篇';
  }

  @override
  String get readingLoadMore => '加载更多';

  @override
  String get readingPublishedUnknown => '时间未知（按抓取时间排序）';

  @override
  String get readingBatchEnter => '批量选择';

  @override
  String get readingBatchExit => '退出批量';

  @override
  String get readingBatchSelectPage => '选择本页';

  @override
  String readingBatchSelectedCount(int count) {
    return '已选 $count 篇';
  }

  @override
  String get readingBatchScopeLabel => '作用范围';

  @override
  String get readingBatchScopeAll => '全部文章';

  @override
  String get readingBatchScopeFiltered => '当前筛选结果';

  @override
  String readingBatchScopeSelected(int count) {
    return '已选 $count 篇';
  }

  @override
  String get readingBatchMarkRead => '标为已读';

  @override
  String get readingBatchMarkUnread => '标为未读';

  @override
  String get readingBatchMarkLater => '标为稍后读';

  @override
  String get readingBatchFavorite => '加入收藏';

  @override
  String get readingBatchUnfavorite => '取消收藏';

  @override
  String get readingBatchEmptyScope => '这个范围里没有文章可操作';

  @override
  String readingBatchDone(int count) {
    return '已处理 $count 篇';
  }

  @override
  String get readingItemMenu => '文章操作';

  @override
  String get readingOpenArticle => '打开正文';

  @override
  String get readingDetailPlaceholderNotice =>
      '正文阅读器（标题排版、代码、公式、目录与上下篇）属 T019；当前是最简占位，只显示标题与纯文本正文。';

  @override
  String get readingDetailNoBody => '这篇文章没有可显示的正文（源只提供了摘要）。';

  @override
  String readingActionError(String reason) {
    return '操作失败：$reason';
  }

  @override
  String readingLoadFailed(String reason) {
    return '文章列表读取失败：$reason';
  }

  @override
  String readingUndoMessage(int count, String action) {
    return '已处理 $count 篇（$action）';
  }

  @override
  String get readingUndoAction => '撤销';

  @override
  String readingUndoDone(int count) {
    return '已撤销 $count 篇';
  }

  @override
  String readingUndoFailed(String reason) {
    return '撤销失败：$reason';
  }

  @override
  String get readingActionMarkRead => '标为已读';

  @override
  String get readingActionMarkUnread => '标为未读';

  @override
  String get readingActionMarkLater => '标为稍后读';

  @override
  String get readingActionFavorite => '加入收藏';

  @override
  String get readingActionUnfavorite => '取消收藏';

  @override
  String get deleteFeedMenuEntry => '删除订阅…';

  @override
  String deleteFeedDialogTitle(String name) {
    return '删除订阅「$name」';
  }

  @override
  String deleteFeedDialogIntro(int total) {
    return '这个订阅下有 $total 篇文章，其中：';
  }

  @override
  String deleteFeedDialogFavoriteLine(int count) {
    return '收藏 $count 篇';
  }

  @override
  String get deleteFeedDialogFavoriteHint => '勾选后这些文章会脱离订阅，留在资料库里继续可读';

  @override
  String deleteFeedDialogOtherLine(int count, int later) {
    return '其他 $count 篇（含稍后再读 $later 篇）';
  }

  @override
  String get deleteFeedDialogOtherHint => '无论是否保留收藏，这些文章都会被清理（稍后再读不会例外）';

  @override
  String get deleteFeedDialogNoArticles => '这个订阅还没有文章，删除后不会清理任何内容。';

  @override
  String get deleteFeedKeepFavoritesOption => '保留收藏文章';

  @override
  String get deleteFeedKeepFavoritesHint => '收藏会脱离订阅并保存来源快照；其余文章会被清理';

  @override
  String get deleteFeedConfirm => '删除';

  @override
  String deleteFeedDone(String name, int deleted, int kept) {
    return '已删除订阅「$name」：清理 $deleted 篇，保留收藏 $kept 篇';
  }

  @override
  String deleteFeedDoneNoArticles(String name) {
    return '已删除订阅「$name」';
  }

  @override
  String deleteFeedPreviewFailed(String name, String reason) {
    return '无法读取「$name」的影响范围：$reason';
  }

  @override
  String deleteGroupDialogImpact(
    int feeds,
    int articles,
    int favorites,
    int later,
  ) {
    return '该分组下有 $feeds 个订阅、$articles 篇文章（收藏 $favorites 篇、含稍后再读 $later 篇）。';
  }

  @override
  String get deleteGroupDialogNoFeeds => '该分组下还没有订阅。';

  @override
  String get deleteGroupKeepFavoritesOption => '保留这些订阅中的收藏文章';

  @override
  String deleteGroupDoneDeleted(String name, int feeds, int deleted, int kept) {
    return '已删除分组「$name」及其 $feeds 个订阅：清理 $deleted 篇，保留收藏 $kept 篇';
  }

  @override
  String get detachedFeedLabel => '已脱离订阅';

  @override
  String get readingCompletenessSourceBody => '来源全文';

  @override
  String get readingCompletenessSummaryOnly => '仅摘要';

  @override
  String get readingCompletenessExtracted => '本机提取';

  @override
  String get readingCompletenessUnknown => '完整性未知';

  @override
  String get readingCompletenessSummaryOnlyNotice => '来源只提供了摘要，这不是全文。';

  @override
  String get readingTocTitle => '目录';

  @override
  String get readingTocEmpty => '这篇文章没有小节标题';

  @override
  String get readingPrevArticle => '上一篇';

  @override
  String get readingNextArticle => '下一篇';

  @override
  String get readingNoPrev => '已是筛选结果的第一篇';

  @override
  String get readingNoNext => '已是筛选结果的最后一篇';

  @override
  String get readingNeighborOrderNote => '上一篇／下一篇按进入时的筛选与排序快照';

  @override
  String get readingFindOpen => '页内查找';

  @override
  String get readingFindHint => '在本文中查找';

  @override
  String get readingFindClose => '关闭查找';

  @override
  String get readingFindNoMatch => '没有匹配';

  @override
  String readingFindMatchCount(int index, int total) {
    return '第 $index / $total 个匹配';
  }

  @override
  String get readingFindNext => '下一个匹配';

  @override
  String get readingFindPrevious => '上一个匹配';

  @override
  String get readingCodeCopy => '复制代码';

  @override
  String get readingCodeCopied => '代码已复制';

  @override
  String get readingCodePlainText => '纯文本';

  @override
  String get readingCodeCollapse => '折叠';

  @override
  String readingCodeExpand(int lines) {
    return '展开（共 $lines 行）';
  }

  @override
  String get readingMathUnsupported => '公式无法渲染，已显示原式';

  @override
  String readingMathUnsupportedReason(String reason) {
    return '原因：$reason';
  }

  @override
  String get readingImagePlaceholder => '图片占位';

  @override
  String get readingImageNotice => '远程图片按需加载并缓存在本机（SET-080 上限）；点击可打开查看器。';

  @override
  String get readingImageRetry => '重新加载这张图片';

  @override
  String get readingImageBlockedPrivate => '已拦截：这个图片地址指向本机或私有网络。';

  @override
  String get readingImageTooLarge => '这张图片超过单图上限，未下载。';

  @override
  String readingLinkBlocked(String reason) {
    return '已拦截：$reason';
  }

  @override
  String get readingLinkCopy => '复制链接';

  @override
  String get readingLinkCopied => '链接已复制';

  @override
  String get readingLinkOpenHint => '外链打开属 T020，当前可复制地址。';

  @override
  String get readingCopyAll => '复制全文';

  @override
  String readingCopyAllDone(int characters) {
    return '全文已复制（$characters 字）';
  }

  @override
  String get readingCopyAllEmpty => '这篇没有可复制的正文。';

  @override
  String get readingSelectionExplain => '解释';

  @override
  String get readingSelectionExplainNoAiTitle => '尚未配置 AI 服务';

  @override
  String readingSelectionExplainNoAiBody(int limit) {
    return '解释需要 AI 服务。将只发送选中的文字与前后各一段的最少上下文（不超过 $limit 字）。';
  }

  @override
  String get readingSelectionExplainGoSettings => '去设置';

  @override
  String get readingSelectionExplainPending =>
      '选词解释需要 AI 服务，调用本身属 T034；本轮只做入口与提示，不会发出请求。';

  @override
  String get readingImageAnalyzeAction => '分析这张图';

  @override
  String get visionConsentTitle => '首次向该服务发送图片';

  @override
  String visionConsentBody(String endpoint) {
    return '这张图片将被发送至 $endpoint 进行分析。图片会离开本机，发送后无法撤回；分析结果由对方模型生成，可能有误。确认记录只保存在本机，端点变化时会再次询问。';
  }

  @override
  String get visionConsentConfirm => '同意并分析';

  @override
  String get visionConsentCancel => '取消';

  @override
  String get visionAnalysisTitle => '图像分析';

  @override
  String get visionAnalysisRunning => '正在分析这张图…';

  @override
  String get visionAnalysisDownsampled => '（这张图超过单图上传上限，已降采样后发送：细节可能已经丢失。）';

  @override
  String visionAnalysisSentTo(String endpoint) {
    return '发送至 $endpoint';
  }

  @override
  String get visionAnalysisNoModel =>
      '本机没有声明视觉能力的模型，已跳过图像分析；正文与文本任务不受影响。可在设置中为某个模型打开视觉能力。';

  @override
  String get visionAnalysisDisabled => '图像分析开关当前是关闭的，且这次没能写回设置；请在设置中打开后再试。';

  @override
  String get visionAnalysisImageUnavailable => '这张图片无法加载或未通过校验，因此没有送去分析。';

  @override
  String visionAnalysisFailed(String reason) {
    return '图像分析失败：$reason';
  }

  @override
  String get visionAnalysisClose => '关闭';

  @override
  String get visionAnalysisCancelAction => '取消分析';

  @override
  String get visionAnalysisCancelled => '已取消图像分析，正文没有改动。';

  @override
  String get aiVisionSettingHint =>
      '图像分析的开关、单张上限与专用视觉模型在设置中；未配置视觉模型时会跳过图像分析，正文与文本任务照常。';

  @override
  String get readingSummaryAction => '摘要';

  @override
  String get readingSummaryTitle => 'AI 摘要';

  @override
  String get readingSummaryRunning => '正在生成摘要…';

  @override
  String get readingSummaryCancelAction => '取消摘要';

  @override
  String get readingSummaryCancelled => '已取消摘要生成，正文没有改动。';

  @override
  String readingAiSummaryLabel(String model, String date) {
    return 'AI 摘要 · $model · $date';
  }

  @override
  String get readingSummaryTruncatedNotice =>
      '正文超过单篇预算（SET-061 的 8000 字符），摘要只依据前一部分生成。';

  @override
  String get readingSummarySourceKept => '源摘要仍然保留，未被 AI 摘要覆盖。';

  @override
  String get readingSummaryNoBody => '这篇文章没有正文可总结（源只提供了摘要）；已保留源摘要。';

  @override
  String get readingSummaryNoModelBody =>
      '摘要需要 AI 服务。请先配置至少一个已启用的模型；未配置时列表会退回到截取正文。';

  @override
  String readingSummaryFailed(String reason) {
    return '摘要生成失败：$reason';
  }

  @override
  String get readingSummaryAutoToggleLabel => '缺摘要时自动生成 AI 摘要';

  @override
  String get readingSummaryAutoToggleHint =>
      '默认关闭。开启后只在**列表刷新**时补齐缺摘要的文章，每篇摘要单独计费，并受当天上限（SET-064，默认 50）约束；关闭时列表会截取正文作为兜底。';

  @override
  String get readingSummaryAutoToggleDone => '自动摘要已开启；下次刷新时会补齐缺摘要的文章。';

  @override
  String readingSummaryAutoBatchReport(
    int succeeded,
    int failed,
    int cached,
    int limit,
  ) {
    return '自动摘要：成功 $succeeded 篇，失败 $failed 篇，缓存命中 $cached 篇（当天上限 $limit）。';
  }

  @override
  String readingSummaryAutoQuotaReached(int limit) {
    return '当天的自动摘要额度已用尽（$limit 篇），手动摘要不受此限制。';
  }

  @override
  String readingSelectionExplainTitle(String selection) {
    return '解释「$selection」';
  }

  @override
  String get readingSelectionExplainRunning => '正在解释…';

  @override
  String readingSelectionExplainSent(int characters) {
    return '已发送选区与前后上下文共 $characters 字；原文未被修改。';
  }

  @override
  String readingSelectionExplainSentTruncated(int characters) {
    return '已发送选区与前后上下文共 $characters 字（上下文已截断）；原文未被修改。';
  }

  @override
  String get readingSelectionExplainFailedUnknown => '解释失败，请稍后重试；原文未被修改。';

  @override
  String get readingSelectionCopy => '复制';

  @override
  String get readingLinkPanelTitle => '外部链接';

  @override
  String get readingLinkCopyAction => '复制地址';

  @override
  String get readingLinkOpenAction => '用浏览器打开';

  @override
  String readingLinkOpenFailed(String reason) {
    return '无法打开这个地址：$reason';
  }

  @override
  String get readingImageViewerTitle => '图片';

  @override
  String get readingImageCloseAction => '关闭（Esc）';

  @override
  String get readingImageSaveAction => '保存图片';

  @override
  String get readingImageShareAction => '分享';

  @override
  String readingImageSavedTo(String path) {
    return '图片已保存到 $path';
  }

  @override
  String readingImageSaveFailed(String reason) {
    return '保存失败：$reason';
  }

  @override
  String get readingImageLoadFailed => '图片加载失败。';

  @override
  String get readingImageTapToDownload => '点击下载这张图片';

  @override
  String get readingImageAutoLoadOff => '自动加载远程图片已关闭（SET-012）；点击图片可单独下载。';

  @override
  String get readingShareUnavailable => '系统分享不可用，已改为复制。';

  @override
  String get readingShareDone => '已打开系统分享。';

  @override
  String get readingShareFailed => '分享未完成，已复制到剪贴板。';

  @override
  String get readingRichBodyUnavailable => '这篇正文只能按纯文本显示（缺少可渲染的受控文档结构）。';

  @override
  String readingRichBodyBlockReason(String reason) {
    return '未能解析的内容（已按原文显示）：$reason';
  }

  @override
  String readingByAuthor(String author, String feed) {
    return '$author · $feed';
  }

  @override
  String readingFindScopeNote(String query) {
    return '已高亮「$query」的匹配位置；目录与上下篇仍可用。';
  }

  @override
  String get readingBackToList => '返回列表';

  @override
  String get searchFieldHint => '搜索全部文章';

  @override
  String get searchFieldLabel => '搜索';

  @override
  String get searchClear => '清除搜索';

  @override
  String get searchClose => '关闭搜索';

  @override
  String get searchOpen => '搜索文章';

  @override
  String get searchIdleTitle => '输入关键词开始检索';

  @override
  String get searchIdleBody => '搜索范围包括标题、作者、来源、摘要与已存正文。中文与英文都按子串匹配（大小写不敏感）。';

  @override
  String get searchEmptyTitle => '没有匹配的文章';

  @override
  String get searchEmptyBody => '试试更短的关键词。检索只在本地已收录的文章里进行，不会访问网页。';

  @override
  String searchFailed(String reason) {
    return '检索失败：$reason';
  }

  @override
  String get searchRetry => '重试';

  @override
  String searchResultsCount(int count) {
    return '命中 $count 篇';
  }

  @override
  String get searchScopeAll => '全部文章';

  @override
  String get searchScopeFiltered => '当前筛选';

  @override
  String get searchScopeLabel => '范围';

  @override
  String get statsPageTitle => '阅读统计';

  @override
  String get statsHeatmapTitle => '年度热力图';

  @override
  String get statsHeatmapLegendLess => '少';

  @override
  String get statsHeatmapLegendMore => '多';

  @override
  String statsHeatmapCellTooltip(Object date, Object minutes) {
    return '$date：$minutes 分钟';
  }

  @override
  String get statsHeatmapEmpty => '这一年还没有阅读记录。';

  @override
  String get statsWeeklyTitle => '近七日';

  @override
  String get statsWeeklyEmpty => '近七日还没有阅读记录。';

  @override
  String get statsYearLabel => '年份';

  @override
  String statsYearTotal(Object minutes) {
    return '这一年累计 $minutes 分钟';
  }

  @override
  String statsActiveDays(Object days) {
    return '有记录 $days 天';
  }

  @override
  String get statsWeekdayMon => '周一';

  @override
  String get statsWeekdayTue => '周二';

  @override
  String get statsWeekdayWed => '周三';

  @override
  String get statsWeekdayThu => '周四';

  @override
  String get statsWeekdayFri => '周五';

  @override
  String get statsWeekdaySat => '周六';

  @override
  String get statsWeekdaySun => '周日';

  @override
  String get statsTodayLabel => '今天';

  @override
  String statsDateLabel(Object day, Object month) {
    return '$month/$day';
  }

  @override
  String get statsClearAction => '清空统计';

  @override
  String get statsClearConfirmTitle => '清空阅读统计？';

  @override
  String get statsClearConfirmBody =>
      '将删除本机记录的全部阅读会话与时长，历史年份与热力图都会清空。文章、阅读状态与收藏不受影响。此操作不可撤销。';

  @override
  String get statsClearConfirmYes => '清空';

  @override
  String get statsClearCancel => '取消';

  @override
  String statsClearDone(Object count) {
    return '已清空 $count 条阅读会话。';
  }

  @override
  String statsClearFailed(Object reason) {
    return '清空失败：$reason';
  }

  @override
  String get statsRecordToggleLabel => '记录阅读时间';

  @override
  String get statsRecordToggleHint => '关闭后不再记录新的阅读时间；已有历史仍保留，可随时清空。';

  @override
  String statsIdlePauseLabel(Object minutes) {
    return '空闲 $minutes 分钟后暂停累计';
  }

  @override
  String get statsDisabledNotice => '阅读统计已关闭（SET-015），本页显示的是已有历史记录。';

  @override
  String statsLoadFailed(Object reason) {
    return '读取统计失败：$reason';
  }

  @override
  String get statsRetry => '重试';

  @override
  String get statsEstimateNote => '统计是本机的估计值：只在前台可见且活跃时累计，不跨设备相加。';

  @override
  String get settingsStatsEntryTitle => '阅读统计';

  @override
  String get settingsStatsEntrySubtitle => '年度热力图与近七日阅读时长';

  @override
  String get readingFetchFullTextAction => '获取原站全文';

  @override
  String get readingFetchFullTextLoading => '正在获取原站正文…';

  @override
  String readingFetchFullTextDone(Object chars) {
    return '已提取原站正文（$chars 字）';
  }

  @override
  String readingFetchFullTextFailed(Object reason) {
    return '未能获取原站正文：$reason';
  }

  @override
  String get readingFetchFullTextViewOriginal => '查看原文';

  @override
  String get readingFetchFullTextViewExtracted => '查看提取正文';

  @override
  String get readingFetchFullTextPaywall => '原站可能要求付费或登录，可能拿不到全文。';

  @override
  String get readingFetchFullTextShort => '提取到的正文很短，原站可能需要脚本渲染。';

  @override
  String get readingFetchFullTextOpenExternal => '在浏览器打开';

  @override
  String get readingFetchFullTextNoUrl => '这篇文章没有可访问的原站地址。';

  @override
  String get readingFetchFullTextNoScript =>
      '只做 HTTP 抓取与静态解析：不执行脚本，也不绕过付费墙或登录。';

  @override
  String get readingFetchFullTextButtonHint => '仅在点击时抓取原站，不会自动或后台执行。';

  @override
  String get settingsAiEntryTitle => 'AI 服务';

  @override
  String get settingsAiEntrySubtitle => '提供商、模型、能力与凭据（SET-030–033）';

  @override
  String get aiPageTitle => 'AI 服务';

  @override
  String get aiModelsSection => '模型与提供商';

  @override
  String get aiEmptyNotice => '还没有配置任何模型。添加一个提供商与模型 ID 之后，AI 功能才可用。';

  @override
  String get aiAddModel => '添加模型';

  @override
  String get aiEditModel => '编辑';

  @override
  String get aiDeleteModel => '删除';

  @override
  String get aiProtocolLabel => '协议';

  @override
  String get aiProtocolHint => '协议决定请求与事件流的形状；同名域名下不同路径的协议并不通用。';

  @override
  String get aiProtocolPendingSuffix => '（适配器待实现）';

  @override
  String get aiPresetLabel => '提供商预设';

  @override
  String get aiPresetCustom => '自定义（不套预设）';

  @override
  String get aiPresetHint => '预设只填协议与 Base URL，不代填 Key；Key 始终手填，只保存在安全存储里。';

  @override
  String get aiPresetEndpointLabel => '将请求';

  @override
  String get aiPresetStatusLive => '实测';

  @override
  String get aiPresetStatusFixture => 'fixture 通过';

  @override
  String get aiPresetStatusUnverified => '待验证';

  @override
  String get aiPresetStatusLiveHint => '本机真的对真实端点发起过调用并成功（见手册轮次记录）。';

  @override
  String get aiPresetStatusFixtureHint => '该协议的适配器有完整夹具级证据，但本轮没有对真实端点发起过调用。';

  @override
  String get aiPresetStatusUnverifiedHint =>
      '本端点尚未做任何真实调用（通常是没有凭据）；不要把它当成已验证可用。';

  @override
  String get aiPresetMatrixTitle => '预设验证状态';

  @override
  String get aiPresetMatrixHint => '「已支持」只写实测过的范围；fixture 通过不等于真实可用。';

  @override
  String get aiPresetNoLiveNotice => '本机尚无任何实测通过的预设。';

  @override
  String get aiAliasLabel => '提供商别名';

  @override
  String get aiAliasHint => '本机唯一，用于标识这份凭据；模型列表与故障转移顺序按它显示。';

  @override
  String get aiBaseUrlLabel => 'Base URL';

  @override
  String get aiBaseUrlHint =>
      '只填到主机或公共前缀即可，例如 https://api.deepseek.com；协议路径由适配器追加。';

  @override
  String get aiModelIdLabel => '模型 ID';

  @override
  String get aiModelIdHint => '列表接口不可用时可以手填；必须与服务商的模型名完全一致。';

  @override
  String get aiApiKeyLabel => 'API Key（SET-031）';

  @override
  String aiApiKeyConfigured(String preview) {
    return '已配置：$preview';
  }

  @override
  String get aiApiKeyNotConfigured => '尚未配置';

  @override
  String get aiApiKeyHint => '只写入系统安全存储（钥匙串），不进数据库、不进日志、不随同步或备份外传。';

  @override
  String get aiApiKeyReplace => '替换 Key';

  @override
  String get aiApiKeyClear => '删除 Key';

  @override
  String get aiApiKeyUnavailable => '本机安全存储不可用，本次会话可以填 Key 但不会保存。';

  @override
  String get aiCapabilitySection => '能力（SET-033）';

  @override
  String get aiCapabilityHint => '能力由你声明，不由模型名推断。未声明视觉能力的模型不会收到图片。';

  @override
  String get aiCapabilityText => '文本';

  @override
  String get aiCapabilityVision => '视觉';

  @override
  String get aiCapabilityStreaming => '流式';

  @override
  String get aiCapabilityTools => '工具调用';

  @override
  String get aiCapabilityStructured => '结构化输出';

  @override
  String get aiContextWindowLabel => '上下文上限（token）';

  @override
  String get aiOutputBudgetLabel => '输出上限（token）';

  @override
  String aiBudgetConservativeHint(int context, int output) {
    return '留空表示未声明：按保守预算使用（上下文 $context、输出 $output），这不是真实能力扩容。';
  }

  @override
  String get aiEnabledLabel => '启用';

  @override
  String get aiDefaultForTasksLabel => '设为任务默认模型';

  @override
  String get aiDefaultForTasksBadge => '默认';

  @override
  String get aiMoveUp => '上移（故障转移顺序）';

  @override
  String get aiMoveDown => '下移（故障转移顺序）';

  @override
  String get aiSortHint => '顺序决定故障转移的先后（SET-032/035）；停用的模型不参与。';

  @override
  String get aiSaveAction => '保存';

  @override
  String get aiCancelAction => '取消';

  @override
  String aiFormInvalid(String detail) {
    return '请检查：$detail';
  }

  @override
  String get aiTestButton => '测试连接与最小生成';

  @override
  String get aiTestCostTitle => '这次测试会产生费用';

  @override
  String aiTestCostBody(String provider, int tokens) {
    return '测试会向 $provider 发起一次真实生成调用（输出上限 $tokens token），可能产生费用，且不支持幂等键的协议无法保证只计费一次。是否继续？';
  }

  @override
  String get aiTestCostConfirm => '确认并测试';

  @override
  String get aiTestRunning => '正在测试…';

  @override
  String aiTestSuccess(int elapsedMs, int chars) {
    return '测试成功：耗时 $elapsedMs 毫秒，返回 $chars 字符';
  }

  @override
  String aiTestSuccessWithUsage(
    int elapsedMs,
    int inputTokens,
    int outputTokens,
    int chars,
  ) {
    return '测试成功：耗时 $elapsedMs 毫秒，输入 $inputTokens / 输出 $outputTokens token，返回 $chars 字符';
  }

  @override
  String aiTestFailed(String reason) {
    return '测试失败：$reason';
  }

  @override
  String get aiFailureAuth => '认证失败：Key 可能不正确，或账号余额不足。';

  @override
  String get aiFailureRateLimited => '被服务商限流，请稍后再试。';

  @override
  String get aiFailureContentFiltered => '内容被服务商拒绝。这不是网络问题，换一家服务商重试也不能规避。';

  @override
  String aiFailureNetwork(String reason) {
    return '网络请求失败：$reason';
  }

  @override
  String get aiFailureTimeout => '请求超时。';

  @override
  String get aiFailureCancelled => '已取消。';

  @override
  String get aiFailureAdapterMissing => '该协议的适配器尚未实现，当前无法调用。';

  @override
  String get aiFailureCredentialMissing => '尚未配置 API Key。';

  @override
  String get aiFailureDisabled => '这个模型当前是停用状态。';

  @override
  String aiFailureValidation(String reason) {
    return '配置无效：$reason';
  }

  @override
  String get aiFailureStorage => '本地存储写入失败，本次改动没有保存。';

  @override
  String aiFailureUnknown(String reason) {
    return '调用失败：$reason';
  }

  @override
  String aiDeleteConfirmTitle(String alias) {
    return '删除模型「$alias」？';
  }

  @override
  String get aiDeleteConfirmBody => '删除后这条模型记录不再可用。它使用的 API Key 不会被删除。';

  @override
  String aiDeleteInUseBody(String references) {
    return '这个模型仍被以下配置引用：$references。删除后这些配置会指向不存在的模型，需要你随后手动修正。';
  }

  @override
  String get aiReferenceDefaultForTasks => '任务默认模型';

  @override
  String get aiReferenceVisionModel => 'SET-034 专用视觉模型';

  @override
  String get aiReferenceFailover => 'SET-035 故障转移允许列表';

  @override
  String get aiDeleteConfirmYes => '仍然删除';

  @override
  String get aiDeleteCancel => '取消';

  @override
  String aiDeleteFailed(String reason) {
    return '删除失败：$reason';
  }

  @override
  String get aiSavedNotice => '已保存。';

  @override
  String aiLoadFailed(String reason) {
    return '读取模型列表失败：$reason';
  }

  @override
  String get aiPlannedNotice =>
      '自动摘要开关（SET-037）属 T034，本页只做提供商与模型配置；故障转移的五次无响应、总时限与 Token 预算已由 T029 落地（见设置 → AI 任务记录）。';

  @override
  String get aiTaskListTitle => 'AI 任务记录';

  @override
  String get settingsAiTasksEntryTitle => 'AI 任务记录';

  @override
  String get settingsAiTasksEntrySubtitle => '查看历史任务与中断记录，可手动重新开始';

  @override
  String get aiTaskListEmpty => '还没有 AI 任务记录。';

  @override
  String aiTaskListLoadFailed(String reason) {
    return '读取 AI 任务列表失败：$reason';
  }

  @override
  String get aiTaskRestart => '重新开始';

  @override
  String get aiTaskRestartBlocked => '任务仍在进行中，不能重复发起';

  @override
  String get aiTaskRestartSuccess => '已创建新任务并完成，原任务记录保持不变';

  @override
  String get aiTaskFromCache => '命中缓存（未发请求）';

  @override
  String aiTaskMeta(int tokens, int attempts) {
    return '累计 $tokens token · $attempts 次尝试';
  }

  @override
  String get aiTaskStatusQueued => '排队中';

  @override
  String get aiTaskStatusRunning => '进行中';

  @override
  String get aiTaskStatusWaitingConfiguration => '等待配置';

  @override
  String get aiTaskStatusWaitingNetwork => '等待网络';

  @override
  String get aiTaskStatusSucceeded => '成功';

  @override
  String get aiTaskStatusPartial => '部分完成';

  @override
  String get aiTaskStatusFailed => '失败';

  @override
  String get aiTaskStatusCancelled => '已取消';

  @override
  String get aiTaskStatusInterrupted => '已中断（未自动重发）';

  @override
  String get aiTaskKindSummary => '每日总结';

  @override
  String get aiTaskKindExplain => '选词解释';

  @override
  String get aiTaskKindTranslate => '全文翻译';

  @override
  String get aiTaskKindNews => '今日新闻';

  @override
  String get aiTaskKindOther => '其它任务';

  @override
  String get searchPageTitle => '搜索服务';

  @override
  String get settingsSearchEntryTitle => '搜索服务';

  @override
  String get settingsSearchEntrySubtitle =>
      'Tavily / Brave / 自建 SearXNG 的端点与凭据';

  @override
  String get searchAddService => '添加搜索服务';

  @override
  String get searchEditService => '编辑搜索服务';

  @override
  String get searchServicesSection => '搜索服务列表';

  @override
  String get searchSortHint => '顺序即工具执行器选择服务的顺序；停用后不参与选择。';

  @override
  String get searchEmptyNotice =>
      '还没有配置任何搜索服务。没有搜索服务时，联网检索类任务会明确提示缺少配置，而不是静默跳过。';

  @override
  String searchLoadFailed(String reason) {
    return '读取搜索服务列表失败：$reason';
  }

  @override
  String get searchDefaultBadge => '任务默认';

  @override
  String get searchDefaultLabel => '任务默认搜索';

  @override
  String searchBudgetHint(int maxResults, int timeoutSeconds) {
    return '每次取 $maxResults 条 · 超时 $timeoutSeconds 秒（SET-040）';
  }

  @override
  String get searchPrivateApproved => '已显式批准内网/HTTP 端点（SET-041）';

  @override
  String get searchCredentialMissingHint => '尚未配置凭据：该协议没有 Key 一定失败，因此测试按钮已禁用。';

  @override
  String get searchTestDisabledNoCredential => '请先填写并保存凭据，本协议没有 Key 无法调用';

  @override
  String get searchTestButton => '测试';

  @override
  String get searchTestConfirmTitle => '发送一次真实检索？';

  @override
  String searchTestConfirmBody(String protocol, String endpoint) {
    return '这次会把查询词发送到 $protocol 的端点 $endpoint，并可能产生费用。查询词会离开本机。';
  }

  @override
  String get searchTestConfirmYes => '发送';

  @override
  String get searchTestConfirmCancel => '取消';

  @override
  String searchTestSuccess(int elapsedMs, int count) {
    return '检索成功：$elapsedMs ms，返回 $count 条';
  }

  @override
  String searchDeleteConfirmTitle(String label) {
    return '删除搜索服务「$label」？';
  }

  @override
  String get searchDeleteConfirmBody => '删除后这条搜索服务不再可用。它使用的 Key 不会被删除。';

  @override
  String searchDeleteInUseBody(String references) {
    return '这个搜索服务仍被以下配置引用：$references。删除后这些配置会指向不存在的服务，需要你随后手动修正。';
  }

  @override
  String get searchDeleteConfirmYes => '仍然删除';

  @override
  String get searchDeleteCancel => '取消';

  @override
  String searchDeleteFailed(String reason) {
    return '删除失败：$reason';
  }

  @override
  String get searchSaveService => '保存';

  @override
  String get searchLabelField => '服务名';

  @override
  String get searchProtocolField => '协议';

  @override
  String get searchEndpointField => '端点地址';

  @override
  String get searchEndpointRequiredHint => '自建 SearXNG 实例没有默认地址，必须填写你自己的实例地址。';

  @override
  String searchEndpointResolved(String endpoint) {
    return '实际请求：$endpoint';
  }

  @override
  String get searchKeyField => 'API Key / 实例认证';

  @override
  String get searchKeyConfigured => '已配置（不回显内容；留空表示不修改）';

  @override
  String get searchKeyNotConfigured => '尚未配置';

  @override
  String get searchKeyOptionalHint => '该协议凭据可选：留空则不发送认证头（实例由反向代理认证时如此）。';

  @override
  String get searchDeleteKey => '删除已保存的凭据';

  @override
  String get searchMaxResultsField => '每次结果数（1–20）';

  @override
  String get searchTimeoutField => '超时秒数（5–60）';

  @override
  String get searchAllowPrivateLabel => '允许内网/HTTP 端点（SET-041）';

  @override
  String get searchAllowPrivateHint =>
      '仅在自建实例位于局域网或使用明文 HTTP 时打开。未批准时该端点会被地址守卫拒绝，不会发出请求。';

  @override
  String get searchPlannedNotice =>
      '查询关键词列表（SET-052）、禁止查询词与主题过滤（SET-053）以及每日新闻的检索编排（T036/T037）属后续任务；本页只做搜索服务本身。';

  @override
  String get readingTranslateAction => '翻译';

  @override
  String get readingTranslateTitle => '全文翻译';

  @override
  String readingTranslateRunning(int done, int total) {
    return '正在逐段翻译…（已完成 $done/$total 段）';
  }

  @override
  String readingTranslateDone(int done, int total) {
    return '翻译完成：已完成 $done/$total 段。';
  }

  @override
  String readingTranslatePartial(int done, int total, int failed) {
    return '翻译完成：已完成 $done/$total 段，$failed 段失败（可只重试失败段）。';
  }

  @override
  String get readingTranslateCancelAction => '取消翻译';

  @override
  String get readingTranslateCancelled => '已取消翻译，已完成的段落保留，未完成的段落显示原文。';

  @override
  String readingTranslateRetryFailed(int count) {
    return '重试失败段（$count 段）';
  }

  @override
  String get readingTranslateRetryHint => '只重跑失败的段落，已完成的译文会保留。';

  @override
  String get readingTranslateSegmentFailed => '这一段翻译失败，正文仍显示原文。';

  @override
  String get readingTranslateShowOriginal => '显示原文';

  @override
  String get readingTranslateShowTranslation => '显示译文';

  @override
  String get readingTranslateSourceKept => '原文始终保留，切换只改变显示。';

  @override
  String get readingTranslateTruncatedNotice =>
      '有段落超过单段预算（SET-061 的 8000 字符），这些段只翻译了前一部分。';

  @override
  String get readingTranslateStale => '这篇正文在上次翻译之后变化过；以下译文对应的是上一版正文。';

  @override
  String get readingTranslateSummaryOnly =>
      '这篇文章的源只提供了摘要（仅摘要），没有可翻译的全文；摘要不当作正文翻译。';

  @override
  String get readingTranslateNoBody => '这篇文章没有正文可翻译，已保留源摘要。';

  @override
  String get readingTranslateNoModelBody => '翻译需要 AI 服务。请先配置至少一个已启用的模型。';

  @override
  String get readingTranslateNoText => '这篇正文里没有可翻译的段落（例如只有一张图片）。';

  @override
  String readingTranslateFailed(String reason) {
    return '翻译失败：$reason';
  }

  @override
  String readingTranslateSavedLabel(String model, String date) {
    return '译文 · $model · $date';
  }

  @override
  String readingTranslateLanguage(String language) {
    return '目标语言：$language';
  }

  @override
  String get readingTranslateInterrupted => '上次翻译未完成（进程被中断），已完成的段落保留；可以重试失败段。';

  @override
  String get newsSettingsEntryTitle => '新闻生成';

  @override
  String get newsSettingsEntrySubtitle =>
      '来源选择、必访网站、关键词与总 prompt（SET-050–055）；今日新闻的生成流程属 T037–T040。';

  @override
  String get newsPageTitle => '新闻生成来源与 prompt';

  @override
  String newsLoadingFailed(String reason) {
    return '配置读取失败：$reason；以下显示的是本次运行的初值，不是已保存的配置。';
  }

  @override
  String get newsGlobalSwitchLabel => '让 RSS 订阅参与新闻选材';

  @override
  String get newsGlobalSwitchHint => '关闭后本次生成完全不使用订阅内容；逐源开关只影响单个源，与加精无关。';

  @override
  String get newsFeedSectionTitle => '逐源开关（SET-050）';

  @override
  String get newsFeedSectionHint => '「跟随」表示按该源的订阅启用状态决定；可以排除某个源的新闻但保留它的订阅刷新。';

  @override
  String get newsFeedFollow => '跟随订阅刷新';

  @override
  String get newsFeedInclude => '参与新闻';

  @override
  String get newsFeedExclude => '不参与新闻';

  @override
  String get newsFeedDisabledHint => '（订阅刷新已关闭）';

  @override
  String get newsFeedEmpty => '还没有订阅源；添加订阅后可以在这里逐源设置。';

  @override
  String get newsRequiredSectionTitle => '必访问网站（SET-051）';

  @override
  String get newsRequiredSectionHint =>
      '每一站在生成任务里都会被单独获取，并逐站写进总 prompt；停用的站不进 prompt。';

  @override
  String get newsRequiredEmpty => '还没有配置必访问网站。';

  @override
  String get newsRequiredAdd => '添加网站';

  @override
  String get newsRequiredNameField => '站点名';

  @override
  String get newsRequiredUrlField => '站点地址';

  @override
  String get newsRequiredSaved => '必访问网站已保存。';

  @override
  String newsRequiredSaveFailed(String reason) {
    return '保存失败：$reason';
  }

  @override
  String get newsListKeywordsTitle => '联网搜索关键词（SET-052）';

  @override
  String get newsListKeywordsHint => '空列表且没有 RSS 材料时会提示缺少输入，而不是凭空生成新闻。';

  @override
  String get newsListBlockedTitle => '禁止发送的查询词（SET-053）';

  @override
  String get newsListBlockedHint => '含这些词的查询不会发给搜索服务（按包含匹配）；它不影响生成时排除哪些主题。';

  @override
  String get newsListTopicsTitle => '排除的内容主题（SET-053）';

  @override
  String get newsListTopicsHint => '这些主题不会被写进结果；与上面的查询禁词是两个独立列表。';

  @override
  String get newsListEmpty => '列表为空。';

  @override
  String get newsListAddHint => '输入后回车添加';

  @override
  String get newsListSaved => '列表已保存。';

  @override
  String newsListSaveFailed(String reason) {
    return '保存失败：$reason';
  }

  @override
  String get newsPromptModeTitle => '总 prompt 模式（SET-055）';

  @override
  String get newsPromptModeComposed => '自动组合';

  @override
  String get newsPromptModeAdvanced => '高级覆盖';

  @override
  String get newsPromptModeComposedHint =>
      '按「任务 + 来源 + 规范 + 固定协议」自动组合；下面的组合结果就是实际会发的文本。';

  @override
  String get newsPromptModeAdvancedHint =>
      '直接编辑总 prompt。固定引用协议段仍会附加在末尾，且必访站缺失会被提示。';

  @override
  String get newsPromptTaskField => '任务说明';

  @override
  String get newsPromptSpecField => '输出规范';

  @override
  String get newsPromptAdvancedField => '总 prompt（高级覆盖）';

  @override
  String get newsPromptCitationFixed => '固定输出协议（不可删除，保存时始终附加）';

  @override
  String get newsPromptRestoreDefaults => '恢复默认模板';

  @override
  String get newsPromptRestored => '已恢复内置模板（尚未保存）。';

  @override
  String get newsPromptSaveVersion => '保存为新版本';

  @override
  String newsPromptVersionSaved(int version) {
    return '已保存为版本 $version。';
  }

  @override
  String newsPromptSaveFailed(String reason) {
    return '保存失败：$reason';
  }

  @override
  String get newsPromptVersionsTitle => '版本（可回退）';

  @override
  String get newsPromptVersionNone => '还没有保存过版本；当前使用内置模板。';

  @override
  String newsPromptVersionItem(int version, String mode) {
    return '版本 $version · $mode';
  }

  @override
  String get newsPromptVersionUse => '载入这一版';

  @override
  String newsPromptVersionLoaded(int version) {
    return '已载入版本 $version；保存后才会成为当前配置。';
  }

  @override
  String get newsPromptVersionDelete => '删除这一版';

  @override
  String get newsPromptDiffTitle => '必访任务缺失提示';

  @override
  String newsPromptDiffMissing(String sites) {
    return '当前总 prompt 里没有出现这些必访网站：$sites。它们仍然被列为必访任务，任务执行时会逐站获取；请确认这是你要的。';
  }

  @override
  String get newsPromptDiffCitationMissing =>
      '当前总 prompt 里没有出现引用标记（形如 [sourceId]）；固定协议段仍会在发送时附加，但建议保留你自己的引用要求。';

  @override
  String get newsPromptPreviewTitle => '实际会发送的 prompt';

  @override
  String get newsPromptPreviewHint => '下面是组合或覆盖后的完整文本（含固定协议段）。复制它可核对实际请求内容。';

  @override
  String get newsEffectiveQueriesTitle => '实际会发送的查询（已应用禁词）';

  @override
  String get newsEffectiveQueriesEmpty => '当前没有可发送的查询（关键词为空或被禁词全部挡住）。';

  @override
  String get newsPlannedNotice =>
      '今日新闻的检索编排、事件聚合与初稿（T037）、来源核验（T038）与定时执行（T040）属后续任务；本页只做 SET-050–055 的配置。';

  @override
  String get todayGenerate => '生成今天的新闻';

  @override
  String get todayRegenerate => '再生成一次';

  @override
  String get todayCancelGenerate => '取消生成';

  @override
  String get todayDateLabel => '查看日期';

  @override
  String get todayPreviousDay => '前一天';

  @override
  String get todayNextDay => '后一天';

  @override
  String get todayProgressTitle => '生成进度';

  @override
  String get todayStageSnapshot => '固化输入快照';

  @override
  String get todayStageRequiredSites => '逐个获取必访网站';

  @override
  String get todayStageSearch => '联网检索';

  @override
  String get todayStageGenerate => '生成初稿';

  @override
  String get todayStageVerify => '独立来源核验';

  @override
  String get todayStageSave => '保存版本';

  @override
  String get todayNoVersionTitle => '这一天还没有新闻';

  @override
  String get todayNoVersionBody =>
      '新闻由你点「生成」后产生：会用当前配置的必访网站、搜索关键词与模型，基于本机文章与联网检索材料生成带引用的条目。未生成前这里是空的，不会编造内容。';

  @override
  String todayMaterialCount(int count) {
    return '本次输入材料 $count 条';
  }

  @override
  String todayRejectedCount(int count) {
    return '其中 $count 条因引用不实被退回';
  }

  @override
  String get todaySiteFailedTitle => '必访网站获取情况';

  @override
  String todaySiteOk(int chars) {
    return '已获取（$chars 字符）';
  }

  @override
  String get todaySiteTimeout => '超时未完成';

  @override
  String todaySiteFailed(String reason) {
    return '获取失败（$reason）';
  }

  @override
  String get todaySiteSkipped => '本次未执行';

  @override
  String get todayLabelSingleSource => '来源单一';

  @override
  String get todayLabelInsufficient => '材料不足';

  @override
  String get todayLabelConflict => '来源冲突';

  @override
  String get todayLabelNotVerified => '未联网核验';

  @override
  String get todayLabelLegend =>
      '标签说明：来源单一 = 只找到一条独立来源；材料不足 = 核验没有拿到可用结果；来源冲突 = 第二条来源明确否定；未联网核验 = 没有配置搜索服务。这些是核验过程的说明，不是对真实性的保证。';

  @override
  String get todayCitationLocal => '本机文章';

  @override
  String get todayCitationOpen => '在浏览器打开';

  @override
  String get todayCitationRss => 'RSS';

  @override
  String get todayCitationFetch => '抓取';

  @override
  String get todayCitationSearch => '检索片段';

  @override
  String todayCitationIncomplete(String fields) {
    return '这一条引用缺字段：$fields';
  }

  @override
  String todayUnknownCitation(String ids) {
    return '模型引用的这些材料不存在，相关条目已退回：$ids';
  }

  @override
  String get todayVersionsTitle => '历史版本';

  @override
  String todayVersionItem(int version, String status) {
    return '版本 $version（$status）';
  }

  @override
  String get todayVersionCurrent => '当前展示';

  @override
  String get todayVersionUse => '切换到这一版';

  @override
  String todayVersionSwitched(int version) {
    return '已切换到版本 $version';
  }

  @override
  String get todayDraftLabel => '初稿';

  @override
  String get todayVerifiedLabel => '核验后';

  @override
  String todayModelLabel(String model) {
    return '模型：$model';
  }

  @override
  String todayVerificationMethod(String method) {
    return '核验方法：$method';
  }

  @override
  String get todayCostConfirmTitle => '确认生成（会产生费用）';

  @override
  String todayCostConfirmBody(int articles, int sites, int queries) {
    return '生成会用到模型调用与联网检索，可能产生费用：本次最多 $articles 篇文章、$sites 个必访网站、$queries 个查询，并受总时限与 Token 预算约束。这是一次真实的网络请求与数据发送。';
  }

  @override
  String get todayCostConfirmRegenerate => '这一天已经有生成的版本；再生成一次会新增一个版本并再次产生费用。';

  @override
  String get todayCostConfirmSend => '确认生成';

  @override
  String get todayCostConfirmCancel => '先不生成';

  @override
  String todayGenerateFailed(String reason) {
    return '本次生成没有完成：$reason';
  }

  @override
  String todayGenerateSucceeded(int version) {
    return '已保存为新版本 $version';
  }

  @override
  String get todayShortfallNoInput =>
      '本次没有可用输入（没有参与新闻的文章、没有关键词、必访网站也没有取到内容），因此没有生成任何内容。请检查 SET-050 的选材开关、必访列表与文章是否已刷新。';

  @override
  String get todayShortfallGlobalDisabled =>
      'RSS 内容总开关当前是关闭的，且没有其它输入（关键词/必访网站），因此没有生成。可在「设置 → 新闻生成」打开总开关。';

  @override
  String get todayJournalNotice => '标签、版本与材料都来自本机记录；模型输出不是事实保证，请按引用自行核对。';
}
