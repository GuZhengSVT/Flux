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
}
