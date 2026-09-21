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
  String get milestoneShellNotice => '当前构建是 M0 应用壳：只包含导航、主题、语言与首次引导，没有业务功能。';

  @override
  String get placeholderBadge => '占位';

  @override
  String placeholderPageBody(String tasks) {
    return '本页目前只有应用壳占位，没有接入数据与交互。计划任务：$tasks。';
  }

  @override
  String get layoutPaneSource => '订阅源栏';

  @override
  String get layoutPaneList => '文章列表';

  @override
  String get layoutPaneBody => '正文区';

  @override
  String get layoutBreakpointSingle => '单栏布局（窗口宽度 <600）';

  @override
  String get layoutBreakpointDouble => '双栏布局（600–1099）';

  @override
  String get layoutBreakpointTriple => '三栏布局（≥1100）';

  @override
  String get layoutShellNote => '本期只做壳：以下区域都是占位面板，没有数据、没有交互，也不代表已实现这些区域的功能。';

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
  String get todayEmptyTitle => '今天还没有新闻';

  @override
  String get todayEmptyBody =>
      '每日新闻需要先配置 AI 与搜索服务并完成首次数据发送告知。来源、prompt、生成与核验由 T036–T040 交付；未配置时本页保持空白，不会编造内容。';

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
  String get readingImageNotice => '远程图片加载与缓存属 T021，当前仅显示占位框。';

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
  String get readingRichBodyUnavailable => '这篇正文只能按纯文本显示（缺少可渲染的受控文档结构）。';
}
