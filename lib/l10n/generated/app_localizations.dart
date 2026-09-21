import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// 应用名（导航与窗口标题）
  ///
  /// In zh, this message translates to:
  /// **'Flux'**
  String get appName;

  /// 应用定位一句话说明
  ///
  /// In zh, this message translates to:
  /// **'本地优先的新闻与 RSS 阅读器'**
  String get appTagline;

  /// 壳层顶部说明，避免被误解为已交付功能
  ///
  /// In zh, this message translates to:
  /// **'当前构建是 M0 应用壳：只包含导航、主题、语言与首次引导，没有业务功能。'**
  String get milestoneShellNotice;

  /// 占位页标记
  ///
  /// In zh, this message translates to:
  /// **'占位'**
  String get placeholderBadge;

  /// 占位页正文；tasks 为任务编号列表
  ///
  /// In zh, this message translates to:
  /// **'本页目前只有应用壳占位，没有接入数据与交互。计划任务：{tasks}。'**
  String placeholderPageBody(String tasks);

  /// 响应式布局占位：来源栏
  ///
  /// In zh, this message translates to:
  /// **'订阅源栏'**
  String get layoutPaneSource;

  /// 响应式布局占位：列表栏
  ///
  /// In zh, this message translates to:
  /// **'文章列表'**
  String get layoutPaneList;

  /// 响应式布局占位：正文栏
  ///
  /// In zh, this message translates to:
  /// **'正文区'**
  String get layoutPaneBody;

  /// 当前布局模式标注：单栏
  ///
  /// In zh, this message translates to:
  /// **'单栏布局（窗口宽度 <600）'**
  String get layoutBreakpointSingle;

  /// 当前布局模式标注：双栏
  ///
  /// In zh, this message translates to:
  /// **'双栏布局（600–1099）'**
  String get layoutBreakpointDouble;

  /// 当前布局模式标注：三栏
  ///
  /// In zh, this message translates to:
  /// **'三栏布局（≥1100）'**
  String get layoutBreakpointTriple;

  /// 响应式布局说明
  ///
  /// In zh, this message translates to:
  /// **'本期只做壳：以下区域都是占位面板，没有数据、没有交互，也不代表已实现这些区域的功能。'**
  String get layoutShellNote;

  /// 顶层导航去向：今日新闻
  ///
  /// In zh, this message translates to:
  /// **'今日新闻'**
  String get navToday;

  /// 顶层导航去向：RSS 阅读
  ///
  /// In zh, this message translates to:
  /// **'RSS 阅读'**
  String get navReading;

  /// 顶层导航去向：我的/设置
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get navMine;

  /// 空态：无订阅
  ///
  /// In zh, this message translates to:
  /// **'还没有订阅'**
  String get emptyNoFeedsTitle;

  /// 空态：无订阅说明
  ///
  /// In zh, this message translates to:
  /// **'添加订阅或导入 OPML 之后，文章会出现在这里。订阅相关的界面与用例由 T013–T016 交付。'**
  String get emptyNoFeedsBody;

  /// 空态：全部已读
  ///
  /// In zh, this message translates to:
  /// **'所有文章已读'**
  String get emptyAllReadTitle;

  /// 空态：全部已读说明
  ///
  /// In zh, this message translates to:
  /// **'当前筛选条件下没有未读文章。可以切到稍后再读或收藏查看已处理的内容。'**
  String get emptyAllReadBody;

  /// 空态：搜索/筛选无结果
  ///
  /// In zh, this message translates to:
  /// **'没有匹配结果'**
  String get emptyNoResultsTitle;

  /// 空态：无结果说明
  ///
  /// In zh, this message translates to:
  /// **'换个关键词，或调整搜索范围与筛选条件后重试。本地全文检索由 T022 交付。'**
  String get emptyNoResultsBody;

  /// 今日页空态
  ///
  /// In zh, this message translates to:
  /// **'今天还没有新闻'**
  String get todayEmptyTitle;

  /// 今日页空态说明
  ///
  /// In zh, this message translates to:
  /// **'每日新闻需要先配置 AI 与搜索服务并完成首次数据发送告知。来源、prompt、生成与核验由 T036–T040 交付；未配置时本页保持空白，不会编造内容。'**
  String get todayEmptyBody;

  /// 启动失败态标题
  ///
  /// In zh, this message translates to:
  /// **'本地数据库打不开'**
  String get shellDatabaseFailedTitle;

  /// 启动失败态说明（不掩盖失败，也不重建数据库）
  ///
  /// In zh, this message translates to:
  /// **'本次运行只能显示壳层：语言与主题改动不会被保存。原始数据库文件保持不动，请检查磁盘空间与文件权限后重启。'**
  String get shellDatabaseFailedBody;

  /// 向导进度
  ///
  /// In zh, this message translates to:
  /// **'第 {current} 步 / 共 {total} 步'**
  String onboardingStepIndicator(int current, int total);

  /// 向导跳过按钮
  ///
  /// In zh, this message translates to:
  /// **'跳过'**
  String get onboardingSkip;

  /// 向导返回按钮
  ///
  /// In zh, this message translates to:
  /// **'上一步'**
  String get onboardingBack;

  /// 向导前进按钮
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get onboardingNext;

  /// 向导完成按钮
  ///
  /// In zh, this message translates to:
  /// **'开始使用'**
  String get onboardingStart;

  /// 向导第 1 步标题
  ///
  /// In zh, this message translates to:
  /// **'欢迎使用 Flux'**
  String get onboardingWelcomeTitle;

  /// 向导第 1 步：离线与数据边界说明
  ///
  /// In zh, this message translates to:
  /// **'订阅、正文、阅读状态和总结都保存在你自己的设备上。Flux 没有账号，也没有业务后端；AI、联网搜索和 WebDAV 由你自行配置并自行承担费用。首次向某个服务发送数据前，都会逐项告知接收者与允许的能力。'**
  String get onboardingWelcomeBody;

  /// 向导第 1 步补充说明
  ///
  /// In zh, this message translates to:
  /// **'离线阅读与本地搜索不依赖 AI，可以长期离线使用。'**
  String get onboardingOfflineNote;

  /// 向导第 2 步标题
  ///
  /// In zh, this message translates to:
  /// **'添加订阅'**
  String get onboardingFeedsTitle;

  /// 向导第 2 步：订阅导入占位说明
  ///
  /// In zh, this message translates to:
  /// **'单条添加、编辑、分组与 OPML 批量导入由 T013–T016 交付。现在还没有可用的导入界面，因此本步骤不创建任何订阅，也不会伪造示例数据；你可以直接跳过，进入应用后再添加。'**
  String get onboardingFeedsBody;

  /// 向导第 2 步补充说明
  ///
  /// In zh, this message translates to:
  /// **'跳过不会影响后续功能，也不会写入任何订阅。'**
  String get onboardingFeedsSkipNote;

  /// 向导第 3 步标题
  ///
  /// In zh, this message translates to:
  /// **'AI 与搜索（可选）'**
  String get onboardingAiTitle;

  /// 向导第 3 步：可跳过的 AI 配置说明
  ///
  /// In zh, this message translates to:
  /// **'未配置 AI 与搜索服务也能完整使用离线阅读、本地搜索和阅读统计。提供商协议、模型管理、凭据、连通性测试与费用提醒由 T025/T031 交付；在此之前本步骤不请求任何凭据，也不发起任何请求。'**
  String get onboardingAiBody;

  /// 向导第 3 步补充说明
  ///
  /// In zh, this message translates to:
  /// **'没有配置 AI 也可以直接开始使用：所有本地功能都不受影响。'**
  String get onboardingAiSkipNote;

  /// 向导中指向设置入口的提示
  ///
  /// In zh, this message translates to:
  /// **'界面语言与主题可以随时在「我的 → 阅读与外观」修改；切换语言不会改写已经生成的 AI 输出。'**
  String get onboardingAppearanceNote;

  /// 我的/设置页标题
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get settingsTitle;

  /// 设置分段：T011 已接线的外观项
  ///
  /// In zh, this message translates to:
  /// **'阅读与外观'**
  String get settingsSectionShell;

  /// 设置分段：T012 起的占位项
  ///
  /// In zh, this message translates to:
  /// **'尚未实现的阅读与外观设置'**
  String get settingsSectionAppearancePlanned;

  /// 设置分段：关于
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get settingsSectionAbout;

  /// SET-001 标题
  ///
  /// In zh, this message translates to:
  /// **'界面语言'**
  String get settingsLanguageLabel;

  /// SET-001 编号（界面显示编号便于对照文档）
  ///
  /// In zh, this message translates to:
  /// **'SET-001'**
  String get settingsLanguageId;

  /// SET-001 说明
  ///
  /// In zh, this message translates to:
  /// **'跟随系统时按各设备的系统语言解析，无匹配时回退英文。文章不会自动翻译。'**
  String get settingsLanguageHint;

  /// SET-002 标题
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get settingsThemeLabel;

  /// SET-002 编号
  ///
  /// In zh, this message translates to:
  /// **'SET-002'**
  String get settingsThemeId;

  /// SET-002 说明
  ///
  /// In zh, this message translates to:
  /// **'浅色、深色与跟随系统；跟随系统时各设备独立解析。'**
  String get settingsThemeHint;

  /// 语言/主题选项：跟随系统
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get settingsOptionFollowSystem;

  /// 语言选项：简体中文
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get settingsOptionChinese;

  /// 语言选项：English
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get settingsOptionEnglish;

  /// 主题选项：浅色
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get settingsOptionLight;

  /// 主题选项：深色
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get settingsOptionDark;

  /// 设置写入失败的可见提示，不静默失败
  ///
  /// In zh, this message translates to:
  /// **'改动没有保存（写入失败或值被拒绝）。当前显示的仍是已保存的值。'**
  String get settingsWriteFailed;

  /// 占位设置项说明
  ///
  /// In zh, this message translates to:
  /// **'以下设置项尚未实现。为避免做成假的可用开关，这里只列出名称、编号与分类，不能修改；对应界面在各自任务中交付。'**
  String get settingsPlannedNotice;

  /// 占位设置项标记
  ///
  /// In zh, this message translates to:
  /// **'即将推出'**
  String get settingsPlannedBadge;

  /// C 类设置
  ///
  /// In zh, this message translates to:
  /// **'共通·可同步'**
  String get settingsClassificationCommon;

  /// D 类设置
  ///
  /// In zh, this message translates to:
  /// **'设备专属'**
  String get settingsClassificationDevice;

  /// S 类设置
  ///
  /// In zh, this message translates to:
  /// **'秘密·仅本机'**
  String get settingsClassificationSecret;

  /// SET-003 标题
  ///
  /// In zh, this message translates to:
  /// **'主题背景图'**
  String get settingsItemSet003;

  /// SET-004 标题
  ///
  /// In zh, this message translates to:
  /// **'背景不透明度、模糊与亮度'**
  String get settingsItemSet004;

  /// SET-005 标题
  ///
  /// In zh, this message translates to:
  /// **'界面、正文与新闻字体'**
  String get settingsItemSet005;

  /// SET-006 标题
  ///
  /// In zh, this message translates to:
  /// **'界面、正文与新闻字号'**
  String get settingsItemSet006;

  /// SET-007 标题
  ///
  /// In zh, this message translates to:
  /// **'纸张背景、阅读字体与字号倍率'**
  String get settingsItemSet007;

  /// SET-008 标题
  ///
  /// In zh, this message translates to:
  /// **'列表视图与桌面栏宽'**
  String get settingsItemSet008;

  /// SET-009 标题
  ///
  /// In zh, this message translates to:
  /// **'列表排序、筛选与返回位置'**
  String get settingsItemSet009;

  /// SET-010 标题
  ///
  /// In zh, this message translates to:
  /// **'显示正文后自动标为已读'**
  String get settingsItemSet010;

  /// SET-011 标题
  ///
  /// In zh, this message translates to:
  /// **'翻译目标语言与生成语言'**
  String get settingsItemSet011;

  /// SET-012 标题
  ///
  /// In zh, this message translates to:
  /// **'自动加载远程图片'**
  String get settingsItemSet012;

  /// SET-013 标题
  ///
  /// In zh, this message translates to:
  /// **'允许在计费网络下载媒体'**
  String get settingsItemSet013;

  /// SET-014 标题
  ///
  /// In zh, this message translates to:
  /// **'减少动态效果'**
  String get settingsItemSet014;

  /// SET-015 标题
  ///
  /// In zh, this message translates to:
  /// **'阅读统计与空闲暂停时间'**
  String get settingsItemSet015;

  /// SET-016 标题
  ///
  /// In zh, this message translates to:
  /// **'专注阅读布局'**
  String get settingsItemSet016;

  /// 占位设置项的对应任务
  ///
  /// In zh, this message translates to:
  /// **'计划任务 {task}'**
  String settingsItemPlannedTask(String task);

  /// 关于：版本
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get aboutVersionLabel;

  /// 关于：版本显示；version 来自 pubspec
  ///
  /// In zh, this message translates to:
  /// **'{version}（M0 骨架版本号占位，发行版本在 T054 确定）'**
  String aboutVersionValue(String version);

  /// 关于：许可
  ///
  /// In zh, this message translates to:
  /// **'许可'**
  String get aboutLicenseLabel;

  /// 关于：许可名称
  ///
  /// In zh, this message translates to:
  /// **'MIT License'**
  String get aboutLicenseValue;

  /// 关于：许可说明
  ///
  /// In zh, this message translates to:
  /// **'仓库内的 LICENSE 为 MIT；第三方依赖与原创素材的完整声明在 T054 落地。'**
  String get aboutLicenseNote;

  /// 关于：仓库链接
  ///
  /// In zh, this message translates to:
  /// **'GitHub 仓库'**
  String get aboutRepositoryLabel;

  /// 关于：仓库地址（2026-09-21 经 api.github.com 核实存在且公开）
  ///
  /// In zh, this message translates to:
  /// **'https://github.com/GuZhengSVT/Flux'**
  String get aboutRepositoryValue;

  /// 关于：Issue 链接
  ///
  /// In zh, this message translates to:
  /// **'问题反馈'**
  String get aboutIssueLabel;

  /// 关于：Issue 地址（同上核实 has_issues=true）
  ///
  /// In zh, this message translates to:
  /// **'https://github.com/GuZhengSVT/Flux/issues'**
  String get aboutIssueValue;

  /// 关于：开发者
  ///
  /// In zh, this message translates to:
  /// **'开发者'**
  String get aboutDeveloperLabel;

  /// 关于：开发者名称
  ///
  /// In zh, this message translates to:
  /// **'GuZhengSVT'**
  String get aboutDeveloperValue;

  /// 关于：未配置的链接（不伪造 URL）
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
  String get aboutNotConfigured;

  /// 关于：只读说明
  ///
  /// In zh, this message translates to:
  /// **'关于信息为只读发布元数据（SET-084）。仓库与 Issue 地址尚未在本机配置，因此显示「未配置」，不提供猜测的地址；检查更新由 T053 交付。'**
  String get aboutReadOnlyNote;

  /// 关于：地址来源与核实说明（不伪造 URL）
  ///
  /// In zh, this message translates to:
  /// **'仓库与 Issue 地址取自本机内置的发布元数据，并在 2026-09-21 用 GitHub 公开接口核实存在、未归档且已开启 Issue；地址为空时显示「未配置」，不猜测。检查更新与 Release 链接由 T053 交付。'**
  String get aboutUnverifiedNote;

  /// 三态控件：读屏标签
  ///
  /// In zh, this message translates to:
  /// **'阅读状态'**
  String get readingStateLabel;

  /// 三态控件取值：未读
  ///
  /// In zh, this message translates to:
  /// **'未读'**
  String get readingStateUnread;

  /// 三态控件取值：已读
  ///
  /// In zh, this message translates to:
  /// **'已读'**
  String get readingStateRead;

  /// 三态控件取值：稍后再读
  ///
  /// In zh, this message translates to:
  /// **'稍后再读'**
  String get readingStateLater;

  /// 三态控件：读屏提示
  ///
  /// In zh, this message translates to:
  /// **'点按或按回车循环切换未读、已读、稍后再读'**
  String get readingStateControlHint;

  /// 三态控件：切换后的读屏播报
  ///
  /// In zh, this message translates to:
  /// **'阅读状态已切换为{state}'**
  String readingStateSwitched(String state);

  /// 收藏控件：读屏标签
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get favoriteToggleLabel;

  /// 收藏控件：未收藏时的动作
  ///
  /// In zh, this message translates to:
  /// **'加入收藏'**
  String get favoriteAddLabel;

  /// 收藏控件：已收藏时的动作
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get favoriteRemoveLabel;

  /// 收藏控件：读屏提示（强调与三态互不影响）
  ///
  /// In zh, this message translates to:
  /// **'收藏独立于阅读状态，不改变未读、已读或稍后再读'**
  String get favoriteToggleHint;

  /// 加精徽标的读屏标签（来源属性，与文章收藏不同）
  ///
  /// In zh, this message translates to:
  /// **'加精'**
  String get featuredBadgeLabel;

  /// 控件加载态读屏标签
  ///
  /// In zh, this message translates to:
  /// **'正在加载'**
  String get controlLoadingLabel;

  /// 控件成功态读屏标签
  ///
  /// In zh, this message translates to:
  /// **'操作成功'**
  String get controlSuccessLabel;

  /// 控件失败态读屏标签
  ///
  /// In zh, this message translates to:
  /// **'操作失败'**
  String get controlErrorLabel;

  /// 禁用态附在控件读屏标签后，说明当前不可操作
  ///
  /// In zh, this message translates to:
  /// **'不可用'**
  String get controlDisabledLabelSuffix;

  /// 订阅管理页标题
  ///
  /// In zh, this message translates to:
  /// **'订阅管理'**
  String get subscriptionManagerTitle;

  /// 订阅管理页的范围说明，避免被当成已交付文章列表
  ///
  /// In zh, this message translates to:
  /// **'本页管理订阅与分组；文章列表与批量状态操作属 T017–T019。'**
  String get subscriptionManagerNotice;

  /// 分组列表小节标题
  ///
  /// In zh, this message translates to:
  /// **'分组与订阅'**
  String get subscriptionGroupsSection;

  /// 添加单个订阅的入口
  ///
  /// In zh, this message translates to:
  /// **'添加订阅'**
  String get subscriptionAddFeed;

  /// 添加订阅对话框标题
  ///
  /// In zh, this message translates to:
  /// **'添加订阅'**
  String get subscriptionAddFeedTitle;

  /// 订阅地址输入框标签
  ///
  /// In zh, this message translates to:
  /// **'订阅地址'**
  String get subscriptionFeedUrlLabel;

  /// 订阅地址输入提示
  ///
  /// In zh, this message translates to:
  /// **'完整的 http/https 地址，例如 https://example.com/feed.xml'**
  String get subscriptionFeedUrlHint;

  /// 抓取并解析地址，展示预览
  ///
  /// In zh, this message translates to:
  /// **'预览'**
  String get subscriptionPreviewAction;

  /// 预览结果区标题
  ///
  /// In zh, this message translates to:
  /// **'预览结果'**
  String get subscriptionPreviewTitle;

  /// 预览项：源格式
  ///
  /// In zh, this message translates to:
  /// **'格式'**
  String get subscriptionPreviewFormat;

  /// 预览项：解析出的文章数
  ///
  /// In zh, this message translates to:
  /// **'{count} 篇文章'**
  String subscriptionPreviewEntries(int count);

  /// 预览项：因缺少必需字段被跳过的条目数
  ///
  /// In zh, this message translates to:
  /// **'{count} 条被跳过'**
  String subscriptionPreviewRejected(int count);

  /// 预览项：用于匹配与去重的规范化地址
  ///
  /// In zh, this message translates to:
  /// **'规范化地址'**
  String get subscriptionPreviewNormalized;

  /// 重复添加时的预览标题
  ///
  /// In zh, this message translates to:
  /// **'该地址已订阅'**
  String get subscriptionPreviewDuplicateTitle;

  /// 重复添加的说明
  ///
  /// In zh, this message translates to:
  /// **'已存在该地址的订阅「{name}」。原有的分组、加精与刷新设置都保留，没有做任何改动。'**
  String subscriptionPreviewDuplicateBody(String name);

  /// 确认入库
  ///
  /// In zh, this message translates to:
  /// **'确认添加'**
  String get subscriptionConfirmAdd;

  /// 取消对话框
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get subscriptionCancel;

  /// 保存名称类对话框（改名/新建分组）
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get subscriptionSave;

  /// 关闭对话框
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get subscriptionClose;

  /// 订阅显示名称输入标签
  ///
  /// In zh, this message translates to:
  /// **'显示名称'**
  String get subscriptionFeedNameLabel;

  /// 订阅归属分组选择标签
  ///
  /// In zh, this message translates to:
  /// **'归属分组'**
  String get subscriptionFeedGroupLabel;

  /// 添加订阅成功后的提示
  ///
  /// In zh, this message translates to:
  /// **'已添加「{name}」，导入 {count} 篇文章'**
  String subscriptionAddSuccess(String name, int count);

  /// 添加成功但源里没有条目时的提示
  ///
  /// In zh, this message translates to:
  /// **'已添加「{name}」，源里暂时没有可导入的文章'**
  String subscriptionAddSuccessEmpty(String name);

  /// 添加订阅失败：地址非法
  ///
  /// In zh, this message translates to:
  /// **'地址不合法：请输入完整的 http/https 订阅地址'**
  String get subscriptionErrorInvalidUrl;

  /// 添加订阅失败：网络
  ///
  /// In zh, this message translates to:
  /// **'抓取失败：请检查网络后重试'**
  String get subscriptionErrorNetwork;

  /// 添加订阅失败：解析
  ///
  /// In zh, this message translates to:
  /// **'解析失败：该地址的内容不是可解析的 RSS/Atom'**
  String get subscriptionErrorParse;

  /// 添加订阅失败：存储
  ///
  /// In zh, this message translates to:
  /// **'本地存储失败，本次改动没有保存'**
  String get subscriptionErrorStorage;

  /// 新建分组入口
  ///
  /// In zh, this message translates to:
  /// **'新建分组'**
  String get subscriptionNewGroup;

  /// 分组名称输入标签
  ///
  /// In zh, this message translates to:
  /// **'分组名称'**
  String get subscriptionGroupNameLabel;

  /// 重命名分组菜单项
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get subscriptionGroupRename;

  /// 删除分组菜单项
  ///
  /// In zh, this message translates to:
  /// **'删除分组'**
  String get subscriptionGroupDelete;

  /// 置顶分组菜单项
  ///
  /// In zh, this message translates to:
  /// **'置顶分组'**
  String get subscriptionGroupPin;

  /// 取消置顶菜单项
  ///
  /// In zh, this message translates to:
  /// **'取消置顶'**
  String get subscriptionGroupUnpin;

  /// 置顶徽标
  ///
  /// In zh, this message translates to:
  /// **'置顶'**
  String get subscriptionPinnedBadge;

  /// 未分类保留组的说明
  ///
  /// In zh, this message translates to:
  /// **'保留分组：不能删除或改名，其中订阅可移动'**
  String get subscriptionReservedGroupNote;

  /// 删除分组确认框标题
  ///
  /// In zh, this message translates to:
  /// **'删除分组「{name}」'**
  String subscriptionGroupDeleteTitle(String name);

  /// 删除分组确认框正文
  ///
  /// In zh, this message translates to:
  /// **'该分组下有 {count} 个订阅。请选择处理方式：'**
  String subscriptionGroupDeleteBody(int count);

  /// 删除分组分支：移动订阅
  ///
  /// In zh, this message translates to:
  /// **'移动到未分类'**
  String get subscriptionGroupDeleteMoveOption;

  /// 移动分支说明
  ///
  /// In zh, this message translates to:
  /// **'订阅与文章都保留，只改归属'**
  String get subscriptionGroupDeleteMoveHint;

  /// 删除分组分支：删除订阅
  ///
  /// In zh, this message translates to:
  /// **'删除其中的订阅'**
  String get subscriptionGroupDeleteFeedsOption;

  /// 删除订阅分支说明（本期为预留）
  ///
  /// In zh, this message translates to:
  /// **'保留收藏选项在 T018 生效；本期只记录，不会真正删除'**
  String get subscriptionGroupDeleteFeedsHint;

  /// 预留分支的结果说明
  ///
  /// In zh, this message translates to:
  /// **'已记录 {count} 个待处理订阅；保留收藏规则在 T018 生效，本期没有删除任何数据'**
  String subscriptionGroupDeleteFeedsPending(int count);

  /// 删除分组成功提示
  ///
  /// In zh, this message translates to:
  /// **'已删除分组「{name}」，{count} 个订阅已移动到未分类'**
  String subscriptionGroupDeleted(String name, int count);

  /// 订阅行菜单的读屏标签
  ///
  /// In zh, this message translates to:
  /// **'订阅操作'**
  String get subscriptionFeedMenu;

  /// 分组行菜单的读屏标签
  ///
  /// In zh, this message translates to:
  /// **'分组操作'**
  String get subscriptionGroupMenu;

  /// 重命名订阅菜单项
  ///
  /// In zh, this message translates to:
  /// **'重命名订阅'**
  String get subscriptionFeedRename;

  /// 编辑订阅菜单项
  ///
  /// In zh, this message translates to:
  /// **'编辑订阅'**
  String get subscriptionFeedEdit;

  /// 移动订阅菜单项
  ///
  /// In zh, this message translates to:
  /// **'移动到分组'**
  String get subscriptionFeedMove;

  /// 启用订阅自动刷新（SET-022）
  ///
  /// In zh, this message translates to:
  /// **'启用自动刷新'**
  String get subscriptionFeedEnable;

  /// 停用订阅自动刷新（SET-022）
  ///
  /// In zh, this message translates to:
  /// **'停用自动刷新'**
  String get subscriptionFeedDisable;

  /// 停用徽标
  ///
  /// In zh, this message translates to:
  /// **'已停用'**
  String get subscriptionFeedDisabledBadge;

  /// 加精菜单项（SET-023）
  ///
  /// In zh, this message translates to:
  /// **'加精'**
  String get subscriptionFeedFavorite;

  /// 取消加精菜单项
  ///
  /// In zh, this message translates to:
  /// **'取消加精'**
  String get subscriptionFeedUnfavorite;

  /// 订阅行未读数
  ///
  /// In zh, this message translates to:
  /// **'{count} 未读'**
  String subscriptionUnreadCount(int count);

  /// 订阅管理页空态标题
  ///
  /// In zh, this message translates to:
  /// **'还没有订阅'**
  String get subscriptionEmptyTitle;

  /// 订阅管理页空态正文
  ///
  /// In zh, this message translates to:
  /// **'点击「添加订阅」输入 RSS/Atom 地址；批量导入与导出属 T015。'**
  String get subscriptionEmptyBody;

  /// 刷新策略区标题（SET-020/021）
  ///
  /// In zh, this message translates to:
  /// **'刷新策略'**
  String get subscriptionRefreshPolicyTitle;

  /// 刷新策略范围说明
  ///
  /// In zh, this message translates to:
  /// **'这里只保存设置；后台定时调度在 T016 落地，本期不会自动联网。'**
  String get subscriptionRefreshPolicyNote;

  /// SET-020 开关标签
  ///
  /// In zh, this message translates to:
  /// **'全局自动刷新'**
  String get subscriptionGlobalRefreshLabel;

  /// SET-020 间隔标签
  ///
  /// In zh, this message translates to:
  /// **'刷新间隔'**
  String get subscriptionGlobalIntervalLabel;

  /// SET-021 开关标签
  ///
  /// In zh, this message translates to:
  /// **'启动时刷新'**
  String get subscriptionStartupRefreshLabel;

  /// 单源刷新间隔：跟随全局
  ///
  /// In zh, this message translates to:
  /// **'继承全局'**
  String get subscriptionIntervalInherit;

  /// 刷新间隔：手动（SET-020 取值）
  ///
  /// In zh, this message translates to:
  /// **'手动'**
  String get subscriptionIntervalManual;

  /// 刷新间隔的分钟文案
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String subscriptionIntervalMinutes(String minutes);

  /// SET-022 单源刷新间隔标签
  ///
  /// In zh, this message translates to:
  /// **'该源刷新间隔'**
  String get subscriptionFeedIntervalLabel;

  /// 移动订阅对话框标题
  ///
  /// In zh, this message translates to:
  /// **'把「{name}」移动到分组'**
  String subscriptionMoveToGroupTitle(String name);

  /// 排序的可达性提示（拖动 + 键盘）
  ///
  /// In zh, this message translates to:
  /// **'拖动把手排序；聚焦把手后用上下方向键也能移动'**
  String get subscriptionReorderHint;

  /// 折叠状态下的订阅数
  ///
  /// In zh, this message translates to:
  /// **'{count} 个订阅（已折叠）'**
  String subscriptionCollapsedCount(int count);

  /// 分组头部的读屏标签
  ///
  /// In zh, this message translates to:
  /// **'{name}，{count} 个订阅'**
  String subscriptionGroupHeaderLabel(String name, int count);

  /// 订阅行的读屏标签
  ///
  /// In zh, this message translates to:
  /// **'{name}，{count} 未读'**
  String subscriptionFeedRowLabel(String name, int count);

  /// 停用订阅的说明
  ///
  /// In zh, this message translates to:
  /// **'已停用：自动刷新会跳过该源（SET-022）'**
  String get subscriptionEnabledNote;

  /// 加精的说明
  ///
  /// In zh, this message translates to:
  /// **'加精只影响显示，不参与新闻选材（SET-023）'**
  String get subscriptionFavoriteNote;

  /// 排序把手的读屏标签
  ///
  /// In zh, this message translates to:
  /// **'拖动或按上下方向键调整顺序'**
  String get subscriptionDragHandleLabel;

  /// 把当前项上移一位
  ///
  /// In zh, this message translates to:
  /// **'上移'**
  String get subscriptionMoveUp;

  /// 把当前项下移一位
  ///
  /// In zh, this message translates to:
  /// **'下移'**
  String get subscriptionMoveDown;

  /// 重命名订阅对话框标题
  ///
  /// In zh, this message translates to:
  /// **'重命名订阅'**
  String get subscriptionFeedRenameTitle;

  /// 重命名分组对话框标题
  ///
  /// In zh, this message translates to:
  /// **'重命名分组'**
  String get subscriptionGroupRenameTitle;

  /// 新建分组对话框标题
  ///
  /// In zh, this message translates to:
  /// **'新建分组'**
  String get subscriptionNewGroupTitle;

  /// 分组名校验失败文案
  ///
  /// In zh, this message translates to:
  /// **'分组名称不能为空'**
  String get subscriptionInvalidGroupName;

  /// 订阅名校验失败文案
  ///
  /// In zh, this message translates to:
  /// **'订阅名称不能为空'**
  String get subscriptionInvalidFeedName;

  /// 移动到分组对话框里「不归入任何分组」的选项
  ///
  /// In zh, this message translates to:
  /// **'未分组'**
  String get subscriptionUngrouped;

  /// 保留组的显示名；保留组不可改名，因此显示名来自资源而不是数据库
  ///
  /// In zh, this message translates to:
  /// **'未分类'**
  String get subscriptionReservedGroupName;

  /// OPML 导入导出页标题
  ///
  /// In zh, this message translates to:
  /// **'导入与导出 OPML'**
  String get opmlPageTitle;

  /// OPML 交换范围说明（架构 4.1）
  ///
  /// In zh, this message translates to:
  /// **'导入与导出只交换标准订阅地址、名称与分组；不含 Flux 内部 ID、加精或阅读状态。'**
  String get opmlPageNotice;

  /// 打开文件选择器
  ///
  /// In zh, this message translates to:
  /// **'选择 OPML 文件'**
  String get opmlPickFile;

  /// 重新选文件
  ///
  /// In zh, this message translates to:
  /// **'换一个文件'**
  String get opmlRepick;

  /// 当前选中的文件名
  ///
  /// In zh, this message translates to:
  /// **'文件：{name}'**
  String opmlFileName(String name);

  /// 预览区标题
  ///
  /// In zh, this message translates to:
  /// **'导入预览'**
  String get opmlPreviewTitle;

  /// 预览统计
  ///
  /// In zh, this message translates to:
  /// **'共 {total} 项：新增 {added}、重复 {duplicate}、无效 {invalid}'**
  String opmlPreviewSummary(int total, int added, int duplicate, int invalid);

  /// SET-026 分组策略标签
  ///
  /// In zh, this message translates to:
  /// **'分组处理'**
  String get opmlStrategyLabel;

  /// SET-026 默认策略
  ///
  /// In zh, this message translates to:
  /// **'全部放入未分类'**
  String get opmlStrategyUncategorized;

  /// SET-026 另一选项
  ///
  /// In zh, this message translates to:
  /// **'保留文件分组'**
  String get opmlStrategyKeepGroups;

  /// SET-026 说明
  ///
  /// In zh, this message translates to:
  /// **'默认全部放入未分类；保留文件分组会按文件里的层级新建分组。'**
  String get opmlStrategyHint;

  /// 预览状态：新增
  ///
  /// In zh, this message translates to:
  /// **'新增'**
  String get opmlStatusAdded;

  /// 预览状态：重复
  ///
  /// In zh, this message translates to:
  /// **'重复'**
  String get opmlStatusDuplicate;

  /// 预览状态：无效
  ///
  /// In zh, this message translates to:
  /// **'无效'**
  String get opmlStatusInvalid;

  /// 结果状态：已导入
  ///
  /// In zh, this message translates to:
  /// **'已导入'**
  String get opmlStatusImported;

  /// 结果状态：失败
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get opmlStatusFailed;

  /// 重复项说明（架构 4.1 不重置状态）
  ///
  /// In zh, this message translates to:
  /// **'重复项已存在，导入时会保留它们原有的分组、加精与刷新设置（不重置状态）。'**
  String get opmlDuplicatesNote;

  /// 无效项说明
  ///
  /// In zh, this message translates to:
  /// **'无效项无法导入：地址缺失或不是可用的 http/https 地址。'**
  String get opmlInvalidNote;

  /// 没有可导入项时的说明
  ///
  /// In zh, this message translates to:
  /// **'这份文件没有可导入的订阅。'**
  String get opmlNothingToImport;

  /// 确认导入
  ///
  /// In zh, this message translates to:
  /// **'开始导入'**
  String get opmlStartImport;

  /// 导入进行中
  ///
  /// In zh, this message translates to:
  /// **'正在导入…'**
  String get opmlImporting;

  /// 结果区标题
  ///
  /// In zh, this message translates to:
  /// **'导入结果'**
  String get opmlResultTitle;

  /// 结果统计
  ///
  /// In zh, this message translates to:
  /// **'成功 {imported}、重复 {duplicate}、失败 {failed}、无效 {invalid}；导入文章 {articles} 篇'**
  String opmlResultSummary(
    int imported,
    int duplicate,
    int failed,
    int invalid,
    int articles,
  );

  /// 只重试失败项
  ///
  /// In zh, this message translates to:
  /// **'重试失败项（{count}）'**
  String opmlRetryFailed(int count);

  /// 重试范围说明
  ///
  /// In zh, this message translates to:
  /// **'只重跑失败的条目；已成功的不会被重新请求，也不会新建重复订阅。'**
  String get opmlRetryHint;

  /// 无需重试
  ///
  /// In zh, this message translates to:
  /// **'没有可重试的失败项'**
  String get opmlRetryNone;

  /// 导出区标题
  ///
  /// In zh, this message translates to:
  /// **'导出 OPML'**
  String get opmlExportTitle;

  /// 导出说明
  ///
  /// In zh, this message translates to:
  /// **'把全部订阅导出为标准 OPML 文件，可在其他阅读器里导入。'**
  String get opmlExportBody;

  /// 触发导出（弹出保存对话框）
  ///
  /// In zh, this message translates to:
  /// **'导出为 OPML'**
  String get opmlExportAction;

  /// 导出成功提示
  ///
  /// In zh, this message translates to:
  /// **'已导出 {count} 个订阅到 {path}'**
  String opmlExportDone(int count, String path);

  /// 导出空清单提示
  ///
  /// In zh, this message translates to:
  /// **'当前没有任何订阅，导出的文件只含空的 body。'**
  String get opmlExportEmpty;

  /// 秘密排除说明（SET-027）
  ///
  /// In zh, this message translates to:
  /// **'导出会移除地址里明确的秘密参数（token、api_key、password 等）与账号密码；这些订阅在目标设备上需要重新填写凭据。'**
  String get opmlExportSecretNote;

  /// 导出时确实剥离了秘密参数时的提示
  ///
  /// In zh, this message translates to:
  /// **'已从 {count} 处地址移除秘密参数（{names}）；这些订阅在其它设备上需要补填凭据。'**
  String opmlExportSecretRemoved(int count, String names);

  /// 导出失败提示
  ///
  /// In zh, this message translates to:
  /// **'导出失败：{reason}'**
  String opmlExportError(String reason);

  /// 导入流程失败提示
  ///
  /// In zh, this message translates to:
  /// **'导入失败：{reason}'**
  String opmlImportError(String reason);

  /// 取消当前导入
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get opmlCancel;

  /// 条目在文件中的序号
  ///
  /// In zh, this message translates to:
  /// **'第 {index} 项'**
  String opmlEntryIndex(int index);

  /// 条目所属分组路径
  ///
  /// In zh, this message translates to:
  /// **'分组：{path}'**
  String opmlEntryGroup(String path);

  /// 订阅管理页上的 OPML 入口
  ///
  /// In zh, this message translates to:
  /// **'导入 / 导出 OPML'**
  String get opmlMenuEntry;

  /// RSS 页顶部的刷新按钮
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get readingRefresh;

  /// 刷新进行中的按钮状态
  ///
  /// In zh, this message translates to:
  /// **'正在刷新…'**
  String get readingRefreshing;

  /// 刷新成功提示
  ///
  /// In zh, this message translates to:
  /// **'刷新完成：新增 {inserted} 篇（检查 {checked} 个源）'**
  String readingRefreshDone(int inserted, int checked);

  /// 刷新完成但没有新内容
  ///
  /// In zh, this message translates to:
  /// **'刷新完成：源暂无更新（检查 {checked} 个源）'**
  String readingRefreshNotModified(int checked);

  /// 刷新结果含失败源
  ///
  /// In zh, this message translates to:
  /// **'刷新完成：新增 {inserted} 篇，{failed} 个源失败（旧内容已保留）'**
  String readingRefreshPartial(int inserted, int failed);

  /// 离线时的刷新提示（不伪造成功）
  ///
  /// In zh, this message translates to:
  /// **'当前无网络，未发起刷新；网络恢复后会自动重试'**
  String get readingRefreshOffline;

  /// SET-013 守卫命中时的提示
  ///
  /// In zh, this message translates to:
  /// **'当前是计费网络，已在设置中关闭计费网络请求，因此未刷新'**
  String get readingRefreshMetered;

  /// 刷新整体失败
  ///
  /// In zh, this message translates to:
  /// **'刷新失败：{reason}'**
  String readingRefreshFailed(String reason);

  /// T016 占位页上的未读计数（真实统计）
  ///
  /// In zh, this message translates to:
  /// **'当前未读 {count} 篇'**
  String readingPlaceholderUnread(int count);

  /// 未读计数读取中
  ///
  /// In zh, this message translates to:
  /// **'正在读取未读计数…'**
  String get readingPlaceholderCounting;

  /// 未读计数读取失败（不显示 0 假装没有未读）
  ///
  /// In zh, this message translates to:
  /// **'未读计数读取失败'**
  String get readingPlaceholderCountFailed;

  /// T016 RSS 去向的范围说明
  ///
  /// In zh, this message translates to:
  /// **'文章列表、三态、收藏、筛选与批量操作属 T017；本页当前只显示真实未读计数与真实刷新结果，不画列表占位。'**
  String get readingPlaceholderBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
