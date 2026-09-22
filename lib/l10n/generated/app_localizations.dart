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

  /// 占位页正文；tasks 为任务编号列表
  ///
  /// In zh, this message translates to:
  /// **'本页目前只有应用壳占位，没有接入数据与交互。计划任务：{tasks}。'**
  String placeholderPageBody(String tasks);

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

  /// 列表筛选：全部
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get readingFilterAll;

  /// 列表筛选：未读（只匹配 unread）
  ///
  /// In zh, this message translates to:
  /// **'未读'**
  String get readingFilterUnread;

  /// 列表筛选：稍后再读（独立入口）
  ///
  /// In zh, this message translates to:
  /// **'稍后再读'**
  String get readingFilterLater;

  /// 列表筛选：收藏
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get readingFilterFavorite;

  /// 来源筛选：不限
  ///
  /// In zh, this message translates to:
  /// **'全部来源'**
  String get readingFeedFilterAll;

  /// 文章列表空态标题（有订阅但无文章）
  ///
  /// In zh, this message translates to:
  /// **'这里还没有文章'**
  String get readingEmptyTitle;

  /// 文章列表空态正文
  ///
  /// In zh, this message translates to:
  /// **'在「我的 → 订阅管理」添加订阅，或在顶部点「刷新」抓取内容。'**
  String get readingEmptyBody;

  /// 筛选结果为空标题
  ///
  /// In zh, this message translates to:
  /// **'当前筛选下没有文章'**
  String get readingEmptyFilteredTitle;

  /// 筛选结果为空正文
  ///
  /// In zh, this message translates to:
  /// **'换一个筛选条件，或有新文章后再回来看看。'**
  String get readingEmptyFilteredBody;

  /// 分页指示
  ///
  /// In zh, this message translates to:
  /// **'第 {page} / {pages} 页（共 {total} 篇）'**
  String readingPageIndicator(int page, int pages, int total);

  /// 上一页按钮
  ///
  /// In zh, this message translates to:
  /// **'上一页'**
  String get readingPreviousPage;

  /// 下一页按钮
  ///
  /// In zh, this message translates to:
  /// **'下一页'**
  String get readingNextPage;

  /// 列表分批加载的进度说明（已加载条数与筛选结果总数）
  ///
  /// In zh, this message translates to:
  /// **'已加载 {loaded} / {total} 篇'**
  String readingLoadedCount(int loaded, int total);

  /// 列表分批加载：继续加载下一批
  ///
  /// In zh, this message translates to:
  /// **'加载更多'**
  String get readingLoadMore;

  /// 发布时间缺失时的注明
  ///
  /// In zh, this message translates to:
  /// **'时间未知（按抓取时间排序）'**
  String get readingPublishedUnknown;

  /// 进入批量模式
  ///
  /// In zh, this message translates to:
  /// **'批量选择'**
  String get readingBatchEnter;

  /// 退出批量模式
  ///
  /// In zh, this message translates to:
  /// **'退出批量'**
  String get readingBatchExit;

  /// 全选本页
  ///
  /// In zh, this message translates to:
  /// **'选择本页'**
  String get readingBatchSelectPage;

  /// 已选数量
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 篇'**
  String readingBatchSelectedCount(int count);

  /// 批量操作范围选择标签
  ///
  /// In zh, this message translates to:
  /// **'作用范围'**
  String get readingBatchScopeLabel;

  /// 范围：全部
  ///
  /// In zh, this message translates to:
  /// **'全部文章'**
  String get readingBatchScopeAll;

  /// 范围：筛选结果
  ///
  /// In zh, this message translates to:
  /// **'当前筛选结果'**
  String get readingBatchScopeFiltered;

  /// 范围：所选行
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 篇'**
  String readingBatchScopeSelected(int count);

  /// 批量标为已读
  ///
  /// In zh, this message translates to:
  /// **'标为已读'**
  String get readingBatchMarkRead;

  /// 批量标为未读（不影响收藏）
  ///
  /// In zh, this message translates to:
  /// **'标为未读'**
  String get readingBatchMarkUnread;

  /// 批量标为稍后再读
  ///
  /// In zh, this message translates to:
  /// **'标为稍后读'**
  String get readingBatchMarkLater;

  /// 批量加入收藏
  ///
  /// In zh, this message translates to:
  /// **'加入收藏'**
  String get readingBatchFavorite;

  /// 批量取消收藏
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get readingBatchUnfavorite;

  /// 范围为空时的提示（不谎报成功）
  ///
  /// In zh, this message translates to:
  /// **'这个范围里没有文章可操作'**
  String get readingBatchEmptyScope;

  /// 批量操作完成
  ///
  /// In zh, this message translates to:
  /// **'已处理 {count} 篇'**
  String readingBatchDone(int count);

  /// 列表项右键菜单标题
  ///
  /// In zh, this message translates to:
  /// **'文章操作'**
  String get readingItemMenu;

  /// 打开正文占位页
  ///
  /// In zh, this message translates to:
  /// **'打开正文'**
  String get readingOpenArticle;

  /// 详情占位页的范围说明
  ///
  /// In zh, this message translates to:
  /// **'正文阅读器（标题排版、代码、公式、目录与上下篇）属 T019；当前是最简占位，只显示标题与纯文本正文。'**
  String get readingDetailPlaceholderNotice;

  /// 文章无正文时的说明
  ///
  /// In zh, this message translates to:
  /// **'这篇文章没有可显示的正文（源只提供了摘要）。'**
  String get readingDetailNoBody;

  /// 单条/批量操作失败提示
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{reason}'**
  String readingActionError(String reason);

  /// 列表读取失败
  ///
  /// In zh, this message translates to:
  /// **'文章列表读取失败：{reason}'**
  String readingLoadFailed(String reason);

  /// 批量操作后的提示条（带撤销）
  ///
  /// In zh, this message translates to:
  /// **'已处理 {count} 篇（{action}）'**
  String readingUndoMessage(int count, String action);

  /// 撤销按钮
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get readingUndoAction;

  /// 撤销完成提示
  ///
  /// In zh, this message translates to:
  /// **'已撤销 {count} 篇'**
  String readingUndoDone(int count);

  /// 撤销失败提示
  ///
  /// In zh, this message translates to:
  /// **'撤销失败：{reason}'**
  String readingUndoFailed(String reason);

  /// 撤销提示里的操作名：标为已读
  ///
  /// In zh, this message translates to:
  /// **'标为已读'**
  String get readingActionMarkRead;

  /// 撤销提示里的操作名：标为未读
  ///
  /// In zh, this message translates to:
  /// **'标为未读'**
  String get readingActionMarkUnread;

  /// 撤销提示里的操作名：标为稍后读
  ///
  /// In zh, this message translates to:
  /// **'标为稍后读'**
  String get readingActionMarkLater;

  /// 撤销提示里的操作名：加入收藏
  ///
  /// In zh, this message translates to:
  /// **'加入收藏'**
  String get readingActionFavorite;

  /// 撤销提示里的操作名：取消收藏
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get readingActionUnfavorite;

  /// 订阅行菜单里的删除入口；省略号表示会先弹出确认（架构 4.1 要求删除前展示影响范围）
  ///
  /// In zh, this message translates to:
  /// **'删除订阅…'**
  String get deleteFeedMenuEntry;

  /// 删除订阅确认框标题
  ///
  /// In zh, this message translates to:
  /// **'删除订阅「{name}」'**
  String deleteFeedDialogTitle(String name);

  /// 影响范围引导语
  ///
  /// In zh, this message translates to:
  /// **'这个订阅下有 {total} 篇文章，其中：'**
  String deleteFeedDialogIntro(int total);

  /// 影响预览：收藏数（勾选保留时会留下来并脱离源）
  ///
  /// In zh, this message translates to:
  /// **'收藏 {count} 篇'**
  String deleteFeedDialogFavoriteLine(int count);

  /// 收藏那一行的说明
  ///
  /// In zh, this message translates to:
  /// **'勾选后这些文章会脱离订阅，留在资料库里继续可读'**
  String get deleteFeedDialogFavoriteHint;

  /// 影响预览：其余文章数与其中 later 的数量；架构 4.1 明写 later 属于清理范围
  ///
  /// In zh, this message translates to:
  /// **'其他 {count} 篇（含稍后再读 {later} 篇）'**
  String deleteFeedDialogOtherLine(int count, int later);

  /// 其余文章那一行的说明
  ///
  /// In zh, this message translates to:
  /// **'无论是否保留收藏，这些文章都会被清理（稍后再读不会例外）'**
  String get deleteFeedDialogOtherHint;

  /// 空源的影响说明
  ///
  /// In zh, this message translates to:
  /// **'这个订阅还没有文章，删除后不会清理任何内容。'**
  String get deleteFeedDialogNoArticles;

  /// 复选框标题（SET-081 默认选保留）
  ///
  /// In zh, this message translates to:
  /// **'保留收藏文章'**
  String get deleteFeedKeepFavoritesOption;

  /// 复选框说明
  ///
  /// In zh, this message translates to:
  /// **'收藏会脱离订阅并保存来源快照；其余文章会被清理'**
  String get deleteFeedKeepFavoritesHint;

  /// 删除订阅确认按钮
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get deleteFeedConfirm;

  /// 删除完成回执
  ///
  /// In zh, this message translates to:
  /// **'已删除订阅「{name}」：清理 {deleted} 篇，保留收藏 {kept} 篇'**
  String deleteFeedDone(String name, int deleted, int kept);

  /// 空源删除完成回执（不显示无意义的 0 篇）
  ///
  /// In zh, this message translates to:
  /// **'已删除订阅「{name}」'**
  String deleteFeedDoneNoArticles(String name);

  /// 影响预览读取失败；此时不提供删除按钮，因为它无法满足「先展示影响范围」的要求
  ///
  /// In zh, this message translates to:
  /// **'无法读取「{name}」的影响范围：{reason}'**
  String deleteFeedPreviewFailed(String name, String reason);

  /// 删除分组的第二个分支（删除其中订阅）的影响范围
  ///
  /// In zh, this message translates to:
  /// **'该分组下有 {feeds} 个订阅、{articles} 篇文章（收藏 {favorites} 篇、含稍后再读 {later} 篇）。'**
  String deleteGroupDialogImpact(
    int feeds,
    int articles,
    int favorites,
    int later,
  );

  /// 空分组的影响说明
  ///
  /// In zh, this message translates to:
  /// **'该分组下还没有订阅。'**
  String get deleteGroupDialogNoFeeds;

  /// 删除分组内订阅时的保留收藏开关
  ///
  /// In zh, this message translates to:
  /// **'保留这些订阅中的收藏文章'**
  String get deleteGroupKeepFavoritesOption;

  /// 删除分组并删除其中订阅后的回执
  ///
  /// In zh, this message translates to:
  /// **'已删除分组「{name}」及其 {feeds} 个订阅：清理 {deleted} 篇，保留收藏 {kept} 篇'**
  String deleteGroupDoneDeleted(String name, int feeds, int deleted, int kept);

  /// 文章列表里来源一栏的标注：这条收藏的来源订阅已被删除，名字来自快照
  ///
  /// In zh, this message translates to:
  /// **'已脱离订阅'**
  String get detachedFeedLabel;

  /// 正文完整性四态之一（架构 4.2）
  ///
  /// In zh, this message translates to:
  /// **'来源全文'**
  String get readingCompletenessSourceBody;

  /// 正文完整性：源只提供了摘要，不能当作全文
  ///
  /// In zh, this message translates to:
  /// **'仅摘要'**
  String get readingCompletenessSummaryOnly;

  /// 正文完整性：本机通过静态提取得到的正文
  ///
  /// In zh, this message translates to:
  /// **'本机提取'**
  String get readingCompletenessExtracted;

  /// 正文完整性：尚未判定
  ///
  /// In zh, this message translates to:
  /// **'完整性未知'**
  String get readingCompletenessUnknown;

  /// 仅摘要时的显式说明（架构 4.2：不把源内 content 绝对当全文）
  ///
  /// In zh, this message translates to:
  /// **'来源只提供了摘要，这不是全文。'**
  String get readingCompletenessSummaryOnlyNotice;

  /// 详情页目录标题（h1–h3 提取）
  ///
  /// In zh, this message translates to:
  /// **'目录'**
  String get readingTocTitle;

  /// 目录空态
  ///
  /// In zh, this message translates to:
  /// **'这篇文章没有小节标题'**
  String get readingTocEmpty;

  /// 上下篇：上一篇
  ///
  /// In zh, this message translates to:
  /// **'上一篇'**
  String get readingPrevArticle;

  /// 上下篇：下一篇
  ///
  /// In zh, this message translates to:
  /// **'下一篇'**
  String get readingNextArticle;

  /// 上下篇边界说明（首篇）
  ///
  /// In zh, this message translates to:
  /// **'已是筛选结果的第一篇'**
  String get readingNoPrev;

  /// 上下篇边界说明（末篇）
  ///
  /// In zh, this message translates to:
  /// **'已是筛选结果的最后一篇'**
  String get readingNoNext;

  /// 说明上下篇的依据（架构 4.1：基于进入详情时的筛选/排序快照）
  ///
  /// In zh, this message translates to:
  /// **'上一篇／下一篇按进入时的筛选与排序快照'**
  String get readingNeighborOrderNote;

  /// 打开查找栏
  ///
  /// In zh, this message translates to:
  /// **'页内查找'**
  String get readingFindOpen;

  /// 页内查找输入框提示
  ///
  /// In zh, this message translates to:
  /// **'在本文中查找'**
  String get readingFindHint;

  /// 关闭查找栏
  ///
  /// In zh, this message translates to:
  /// **'关闭查找'**
  String get readingFindClose;

  /// 页内查找无结果
  ///
  /// In zh, this message translates to:
  /// **'没有匹配'**
  String get readingFindNoMatch;

  /// 页内查找的匹配计数
  ///
  /// In zh, this message translates to:
  /// **'第 {index} / {total} 个匹配'**
  String readingFindMatchCount(int index, int total);

  /// 跳到下一个匹配
  ///
  /// In zh, this message translates to:
  /// **'下一个匹配'**
  String get readingFindNext;

  /// 跳到上一个匹配
  ///
  /// In zh, this message translates to:
  /// **'上一个匹配'**
  String get readingFindPrevious;

  /// 代码块复制按钮
  ///
  /// In zh, this message translates to:
  /// **'复制代码'**
  String get readingCodeCopy;

  /// 代码复制完成提示
  ///
  /// In zh, this message translates to:
  /// **'代码已复制'**
  String get readingCodeCopied;

  /// 代码块语言未知时的标注（未知语言按纯文本显示）
  ///
  /// In zh, this message translates to:
  /// **'纯文本'**
  String get readingCodePlainText;

  /// 折叠长代码块
  ///
  /// In zh, this message translates to:
  /// **'折叠'**
  String get readingCodeCollapse;

  /// 展开被折叠的代码块
  ///
  /// In zh, this message translates to:
  /// **'展开（共 {lines} 行）'**
  String readingCodeExpand(int lines);

  /// 不支持的 LaTeX 命令：显示原式与提示，不留空白（架构 4.2）
  ///
  /// In zh, this message translates to:
  /// **'公式无法渲染，已显示原式'**
  String get readingMathUnsupported;

  /// 公式渲染失败的原因说明
  ///
  /// In zh, this message translates to:
  /// **'原因：{reason}'**
  String readingMathUnsupportedReason(String reason);

  /// 图片占位框；远程图片缓存属 T021，本期不加载
  ///
  /// In zh, this message translates to:
  /// **'图片占位'**
  String get readingImagePlaceholder;

  /// 图片位的范围说明（T021 起为真实缓存加载）
  ///
  /// In zh, this message translates to:
  /// **'远程图片按需加载并缓存在本机（SET-080 上限）；点击可打开查看器。'**
  String get readingImageNotice;

  /// 图片加载失败后的重试按钮
  ///
  /// In zh, this message translates to:
  /// **'重新加载这张图片'**
  String get readingImageRetry;

  /// 图片地址指向内网时的占位说明（不发起请求）
  ///
  /// In zh, this message translates to:
  /// **'已拦截：这个图片地址指向本机或私有网络。'**
  String get readingImageBlockedPrivate;

  /// 图片超过单图字节上限时的占位说明
  ///
  /// In zh, this message translates to:
  /// **'这张图片超过单图上限，未下载。'**
  String get readingImageTooLarge;

  /// 危险协议链接在正文里的可见标注（不静默丢弃）
  ///
  /// In zh, this message translates to:
  /// **'已拦截：{reason}'**
  String readingLinkBlocked(String reason);

  /// 外链的复制按钮（外开属 T020）
  ///
  /// In zh, this message translates to:
  /// **'复制链接'**
  String get readingLinkCopy;

  /// 链接复制完成提示
  ///
  /// In zh, this message translates to:
  /// **'链接已复制'**
  String get readingLinkCopied;

  /// 链接外开的范围说明
  ///
  /// In zh, this message translates to:
  /// **'外链打开属 T020，当前可复制地址。'**
  String get readingLinkOpenHint;

  /// 复制全文按钮（正文纯文本）
  ///
  /// In zh, this message translates to:
  /// **'复制全文'**
  String get readingCopyAll;

  /// 复制全文完成提示
  ///
  /// In zh, this message translates to:
  /// **'全文已复制（{characters} 字）'**
  String readingCopyAllDone(int characters);

  /// 正文为空时点复制全文的提示
  ///
  /// In zh, this message translates to:
  /// **'这篇没有可复制的正文。'**
  String get readingCopyAllEmpty;

  /// 选区菜单里的解释入口
  ///
  /// In zh, this message translates to:
  /// **'解释'**
  String get readingSelectionExplain;

  /// 选词解释：未配置 AI 时的提示标题
  ///
  /// In zh, this message translates to:
  /// **'尚未配置 AI 服务'**
  String get readingSelectionExplainNoAiTitle;

  /// 选词解释：说明将发送什么，并引导去配置
  ///
  /// In zh, this message translates to:
  /// **'解释需要 AI 服务。将只发送选中的文字与前后各一段的最少上下文（不超过 {limit} 字）。'**
  String readingSelectionExplainNoAiBody(int limit);

  /// 选词解释：跳转设置页
  ///
  /// In zh, this message translates to:
  /// **'去设置'**
  String get readingSelectionExplainGoSettings;

  /// 选词解释：已配置 AI 时的占位说明（不发起调用）
  ///
  /// In zh, this message translates to:
  /// **'选词解释需要 AI 服务，调用本身属 T034；本轮只做入口与提示，不会发出请求。'**
  String get readingSelectionExplainPending;

  /// 图片查看器：分析这张图的入口
  ///
  /// In zh, this message translates to:
  /// **'分析这张图'**
  String get readingImageAnalyzeAction;

  /// 首次视觉分析前的告知对话框标题
  ///
  /// In zh, this message translates to:
  /// **'首次向该服务发送图片'**
  String get visionConsentTitle;

  /// 首次视觉分析前的告知正文（架构第 8 节：绑定端点与能力）
  ///
  /// In zh, this message translates to:
  /// **'这张图片将被发送至 {endpoint} 进行分析。图片会离开本机，发送后无法撤回；分析结果由对方模型生成，可能有误。确认记录只保存在本机，端点变化时会再次询问。'**
  String visionConsentBody(String endpoint);

  /// 首次视觉分析告知：确认按钮
  ///
  /// In zh, this message translates to:
  /// **'同意并分析'**
  String get visionConsentConfirm;

  /// 首次视觉分析告知：取消按钮（不发任何请求）
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get visionConsentCancel;

  /// 图像分析结果面板标题
  ///
  /// In zh, this message translates to:
  /// **'图像分析'**
  String get visionAnalysisTitle;

  /// 图像分析进行中
  ///
  /// In zh, this message translates to:
  /// **'正在分析这张图…'**
  String get visionAnalysisRunning;

  /// 图像分析结果中的降采样说明
  ///
  /// In zh, this message translates to:
  /// **'（这张图超过单图上传上限，已降采样后发送：细节可能已经丢失。）'**
  String get visionAnalysisDownsampled;

  /// 图像分析结果面板：数据去向
  ///
  /// In zh, this message translates to:
  /// **'发送至 {endpoint}'**
  String visionAnalysisSentTo(String endpoint);

  /// 图像分析：没有视觉模型时的跳过说明（不是失败）
  ///
  /// In zh, this message translates to:
  /// **'本机没有声明视觉能力的模型，已跳过图像分析；正文与文本任务不受影响。可在设置中为某个模型打开视觉能力。'**
  String get visionAnalysisNoModel;

  /// 图像分析：开关关闭且写回失败
  ///
  /// In zh, this message translates to:
  /// **'图像分析开关当前是关闭的，且这次没能写回设置；请在设置中打开后再试。'**
  String get visionAnalysisDisabled;

  /// 图像分析：图片拿不到
  ///
  /// In zh, this message translates to:
  /// **'这张图片无法加载或未通过校验，因此没有送去分析。'**
  String get visionAnalysisImageUnavailable;

  /// 图像分析失败提示
  ///
  /// In zh, this message translates to:
  /// **'图像分析失败：{reason}'**
  String visionAnalysisFailed(String reason);

  /// 图像分析结果面板：关闭按钮
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get visionAnalysisClose;

  /// 图像分析结果面板：取消进行中的分析
  ///
  /// In zh, this message translates to:
  /// **'取消分析'**
  String get visionAnalysisCancelAction;

  /// 用户取消图像分析后的提示
  ///
  /// In zh, this message translates to:
  /// **'已取消图像分析，正文没有改动。'**
  String get visionAnalysisCancelled;

  /// AI 服务页：视觉能力说明
  ///
  /// In zh, this message translates to:
  /// **'图像分析的开关、单张上限与专用视觉模型在设置中；未配置视觉模型时会跳过图像分析，正文与文本任务照常。'**
  String get aiVisionSettingHint;

  /// 详情页：生成 AI 摘要按钮
  ///
  /// In zh, this message translates to:
  /// **'摘要'**
  String get readingSummaryAction;

  /// AI 摘要面板标题
  ///
  /// In zh, this message translates to:
  /// **'AI 摘要'**
  String get readingSummaryTitle;

  /// AI 摘要进行中
  ///
  /// In zh, this message translates to:
  /// **'正在生成摘要…'**
  String get readingSummaryRunning;

  /// AI 摘要面板：取消生成
  ///
  /// In zh, this message translates to:
  /// **'取消摘要'**
  String get readingSummaryCancelAction;

  /// 取消摘要后的提示
  ///
  /// In zh, this message translates to:
  /// **'已取消摘要生成，正文没有改动。'**
  String get readingSummaryCancelled;

  /// 正文里的 AI 摘要标注（来源与生成时间；与源摘要分列显示）
  ///
  /// In zh, this message translates to:
  /// **'AI 摘要 · {model} · {date}'**
  String readingAiSummaryLabel(String model, String date);

  /// AI 摘要面板：正文被截断的说明
  ///
  /// In zh, this message translates to:
  /// **'正文超过单篇预算（SET-061 的 8000 字符），摘要只依据前一部分生成。'**
  String get readingSummaryTruncatedNotice;

  /// AI 摘要面板：不覆盖源摘要的说明
  ///
  /// In zh, this message translates to:
  /// **'源摘要仍然保留，未被 AI 摘要覆盖。'**
  String get readingSummarySourceKept;

  /// AI 摘要：没有正文时的跳过说明
  ///
  /// In zh, this message translates to:
  /// **'这篇文章没有正文可总结（源只提供了摘要）；已保留源摘要。'**
  String get readingSummaryNoBody;

  /// AI 摘要/解释：没有可用模型时的提示
  ///
  /// In zh, this message translates to:
  /// **'摘要需要 AI 服务。请先配置至少一个已启用的模型；未配置时列表会退回到截取正文。'**
  String get readingSummaryNoModelBody;

  /// AI 摘要失败提示
  ///
  /// In zh, this message translates to:
  /// **'摘要生成失败：{reason}'**
  String readingSummaryFailed(String reason);

  /// SET-037 的界面开关标签
  ///
  /// In zh, this message translates to:
  /// **'缺摘要时自动生成 AI 摘要'**
  String get readingSummaryAutoToggleLabel;

  /// SET-037 的界面开关说明
  ///
  /// In zh, this message translates to:
  /// **'默认关闭。开启后只在**列表刷新**时补齐缺摘要的文章，每篇摘要单独计费，并受当天上限（SET-064，默认 50）约束；关闭时列表会截取正文作为兜底。'**
  String get readingSummaryAutoToggleHint;

  /// 开启自动摘要后的提示
  ///
  /// In zh, this message translates to:
  /// **'自动摘要已开启；下次刷新时会补齐缺摘要的文章。'**
  String get readingSummaryAutoToggleDone;

  /// 列表刷新后的自动摘要回执
  ///
  /// In zh, this message translates to:
  /// **'自动摘要：成功 {succeeded} 篇，失败 {failed} 篇，缓存命中 {cached} 篇（当天上限 {limit}）。'**
  String readingSummaryAutoBatchReport(
    int succeeded,
    int failed,
    int cached,
    int limit,
  );

  /// SET-064 额度用尽提示
  ///
  /// In zh, this message translates to:
  /// **'当天的自动摘要额度已用尽（{limit} 篇），手动摘要不受此限制。'**
  String readingSummaryAutoQuotaReached(int limit);

  /// 选词解释浮层标题
  ///
  /// In zh, this message translates to:
  /// **'解释「{selection}」'**
  String readingSelectionExplainTitle(String selection);

  /// 选词解释进行中
  ///
  /// In zh, this message translates to:
  /// **'正在解释…'**
  String get readingSelectionExplainRunning;

  /// 选词解释：发送量说明
  ///
  /// In zh, this message translates to:
  /// **'已发送选区与前后上下文共 {characters} 字；原文未被修改。'**
  String readingSelectionExplainSent(int characters);

  /// 选词解释：发送量说明（上下文被截断过）
  ///
  /// In zh, this message translates to:
  /// **'已发送选区与前后上下文共 {characters} 字（上下文已截断）；原文未被修改。'**
  String readingSelectionExplainSentTruncated(int characters);

  /// 选词解释失败（无类型化原因时）
  ///
  /// In zh, this message translates to:
  /// **'解释失败，请稍后重试；原文未被修改。'**
  String get readingSelectionExplainFailedUnknown;

  /// 选区菜单里的复制
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get readingSelectionCopy;

  /// 链接面板标题
  ///
  /// In zh, this message translates to:
  /// **'外部链接'**
  String get readingLinkPanelTitle;

  /// 链接面板：复制地址按钮
  ///
  /// In zh, this message translates to:
  /// **'复制地址'**
  String get readingLinkCopyAction;

  /// 链接面板：外部浏览器打开按钮
  ///
  /// In zh, this message translates to:
  /// **'用浏览器打开'**
  String get readingLinkOpenAction;

  /// 外部打开失败提示
  ///
  /// In zh, this message translates to:
  /// **'无法打开这个地址：{reason}'**
  String readingLinkOpenFailed(String reason);

  /// 图片查看器标题（无替代文字时）
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get readingImageViewerTitle;

  /// 图片查看器：关闭按钮
  ///
  /// In zh, this message translates to:
  /// **'关闭（Esc）'**
  String get readingImageCloseAction;

  /// 图片查看器：保存按钮
  ///
  /// In zh, this message translates to:
  /// **'保存图片'**
  String get readingImageSaveAction;

  /// 图片查看器：分享按钮
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get readingImageShareAction;

  /// 图片保存成功提示
  ///
  /// In zh, this message translates to:
  /// **'图片已保存到 {path}'**
  String readingImageSavedTo(String path);

  /// 图片保存失败提示
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{reason}'**
  String readingImageSaveFailed(String reason);

  /// 图片加载失败时的说明
  ///
  /// In zh, this message translates to:
  /// **'图片加载失败。'**
  String get readingImageLoadFailed;

  /// SET-012 关闭时：图片显示为占位框，点选可下载这一张
  ///
  /// In zh, this message translates to:
  /// **'点击下载这张图片'**
  String get readingImageTapToDownload;

  /// SET-012 关闭时正文里的范围说明
  ///
  /// In zh, this message translates to:
  /// **'自动加载远程图片已关闭（SET-012）；点击图片可单独下载。'**
  String get readingImageAutoLoadOff;

  /// 系统分享不可用时的回退说明（架构 4.2）
  ///
  /// In zh, this message translates to:
  /// **'系统分享不可用，已改为复制。'**
  String get readingShareUnavailable;

  /// 系统分享已打开
  ///
  /// In zh, this message translates to:
  /// **'已打开系统分享。'**
  String get readingShareDone;

  /// 分享失败时回退复制
  ///
  /// In zh, this message translates to:
  /// **'分享未完成，已复制到剪贴板。'**
  String get readingShareFailed;

  /// 没有可渲染文档结构时的说明（原文不丢）
  ///
  /// In zh, this message translates to:
  /// **'这篇正文只能按纯文本显示（缺少可渲染的受控文档结构）。'**
  String get readingRichBodyUnavailable;

  /// 未解析块的提示前缀；原因由解析层给出
  ///
  /// In zh, this message translates to:
  /// **'未能解析的内容（已按原文显示）：{reason}'**
  String readingRichBodyBlockReason(String reason);

  /// 详情页元信息：作者与来源
  ///
  /// In zh, this message translates to:
  /// **'{author} · {feed}'**
  String readingByAuthor(String author, String feed);

  /// 页内查找的范围说明
  ///
  /// In zh, this message translates to:
  /// **'已高亮「{query}」的匹配位置；目录与上下篇仍可用。'**
  String readingFindScopeNote(String query);

  /// 详情页返回按钮
  ///
  /// In zh, this message translates to:
  /// **'返回列表'**
  String get readingBackToList;

  /// RSS 列表的搜索框提示
  ///
  /// In zh, this message translates to:
  /// **'搜索全部文章'**
  String get searchFieldHint;

  /// 搜索框的无障碍标签
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get searchFieldLabel;

  /// 清除搜索按钮
  ///
  /// In zh, this message translates to:
  /// **'清除搜索'**
  String get searchClear;

  /// 关闭搜索框并回到浏览列表
  ///
  /// In zh, this message translates to:
  /// **'关闭搜索'**
  String get searchClose;

  /// 打开搜索框的按钮
  ///
  /// In zh, this message translates to:
  /// **'搜索文章'**
  String get searchOpen;

  /// 还没输入查询词时的空态标题
  ///
  /// In zh, this message translates to:
  /// **'输入关键词开始检索'**
  String get searchIdleTitle;

  /// 搜索范围与匹配语义的说明（架构 4.2 要求语义确定）
  ///
  /// In zh, this message translates to:
  /// **'搜索范围包括标题、作者、来源、摘要与已存正文。中文与英文都按子串匹配（大小写不敏感）。'**
  String get searchIdleBody;

  /// 有查询词但无结果的空态标题
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的文章'**
  String get searchEmptyTitle;

  /// 无结果时的说明（不访问未收录网页）
  ///
  /// In zh, this message translates to:
  /// **'试试更短的关键词。检索只在本地已收录的文章里进行，不会访问网页。'**
  String get searchEmptyBody;

  /// 检索失败提示（与无结果区分）
  ///
  /// In zh, this message translates to:
  /// **'检索失败：{reason}'**
  String searchFailed(String reason);

  /// 检索失败后的重试按钮
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get searchRetry;

  /// 结果计数
  ///
  /// In zh, this message translates to:
  /// **'命中 {count} 篇'**
  String searchResultsCount(int count);

  /// 检索范围：全库
  ///
  /// In zh, this message translates to:
  /// **'全部文章'**
  String get searchScopeAll;

  /// 检索范围：跟随列表当前的筛选
  ///
  /// In zh, this message translates to:
  /// **'当前筛选'**
  String get searchScopeFiltered;

  /// 范围选择器的标签
  ///
  /// In zh, this message translates to:
  /// **'范围'**
  String get searchScopeLabel;

  /// No description provided for @statsPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'阅读统计'**
  String get statsPageTitle;

  /// No description provided for @statsHeatmapTitle.
  ///
  /// In zh, this message translates to:
  /// **'年度热力图'**
  String get statsHeatmapTitle;

  /// No description provided for @statsHeatmapLegendLess.
  ///
  /// In zh, this message translates to:
  /// **'少'**
  String get statsHeatmapLegendLess;

  /// No description provided for @statsHeatmapLegendMore.
  ///
  /// In zh, this message translates to:
  /// **'多'**
  String get statsHeatmapLegendMore;

  /// No description provided for @statsHeatmapCellTooltip.
  ///
  /// In zh, this message translates to:
  /// **'{date}：{minutes} 分钟'**
  String statsHeatmapCellTooltip(Object date, Object minutes);

  /// No description provided for @statsHeatmapEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这一年还没有阅读记录。'**
  String get statsHeatmapEmpty;

  /// No description provided for @statsWeeklyTitle.
  ///
  /// In zh, this message translates to:
  /// **'近七日'**
  String get statsWeeklyTitle;

  /// No description provided for @statsWeeklyEmpty.
  ///
  /// In zh, this message translates to:
  /// **'近七日还没有阅读记录。'**
  String get statsWeeklyEmpty;

  /// No description provided for @statsYearLabel.
  ///
  /// In zh, this message translates to:
  /// **'年份'**
  String get statsYearLabel;

  /// No description provided for @statsYearTotal.
  ///
  /// In zh, this message translates to:
  /// **'这一年累计 {minutes} 分钟'**
  String statsYearTotal(Object minutes);

  /// No description provided for @statsActiveDays.
  ///
  /// In zh, this message translates to:
  /// **'有记录 {days} 天'**
  String statsActiveDays(Object days);

  /// No description provided for @statsWeekdayMon.
  ///
  /// In zh, this message translates to:
  /// **'周一'**
  String get statsWeekdayMon;

  /// No description provided for @statsWeekdayTue.
  ///
  /// In zh, this message translates to:
  /// **'周二'**
  String get statsWeekdayTue;

  /// No description provided for @statsWeekdayWed.
  ///
  /// In zh, this message translates to:
  /// **'周三'**
  String get statsWeekdayWed;

  /// No description provided for @statsWeekdayThu.
  ///
  /// In zh, this message translates to:
  /// **'周四'**
  String get statsWeekdayThu;

  /// No description provided for @statsWeekdayFri.
  ///
  /// In zh, this message translates to:
  /// **'周五'**
  String get statsWeekdayFri;

  /// No description provided for @statsWeekdaySat.
  ///
  /// In zh, this message translates to:
  /// **'周六'**
  String get statsWeekdaySat;

  /// No description provided for @statsWeekdaySun.
  ///
  /// In zh, this message translates to:
  /// **'周日'**
  String get statsWeekdaySun;

  /// No description provided for @statsTodayLabel.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get statsTodayLabel;

  /// No description provided for @statsDateLabel.
  ///
  /// In zh, this message translates to:
  /// **'{month}/{day}'**
  String statsDateLabel(Object day, Object month);

  /// No description provided for @statsClearAction.
  ///
  /// In zh, this message translates to:
  /// **'清空统计'**
  String get statsClearAction;

  /// No description provided for @statsClearConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空阅读统计？'**
  String get statsClearConfirmTitle;

  /// No description provided for @statsClearConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'将删除本机记录的全部阅读会话与时长，历史年份与热力图都会清空。文章、阅读状态与收藏不受影响。此操作不可撤销。'**
  String get statsClearConfirmBody;

  /// No description provided for @statsClearConfirmYes.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get statsClearConfirmYes;

  /// No description provided for @statsClearCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get statsClearCancel;

  /// No description provided for @statsClearDone.
  ///
  /// In zh, this message translates to:
  /// **'已清空 {count} 条阅读会话。'**
  String statsClearDone(Object count);

  /// No description provided for @statsClearFailed.
  ///
  /// In zh, this message translates to:
  /// **'清空失败：{reason}'**
  String statsClearFailed(Object reason);

  /// No description provided for @statsRecordToggleLabel.
  ///
  /// In zh, this message translates to:
  /// **'记录阅读时间'**
  String get statsRecordToggleLabel;

  /// No description provided for @statsRecordToggleHint.
  ///
  /// In zh, this message translates to:
  /// **'关闭后不再记录新的阅读时间；已有历史仍保留，可随时清空。'**
  String get statsRecordToggleHint;

  /// No description provided for @statsIdlePauseLabel.
  ///
  /// In zh, this message translates to:
  /// **'空闲 {minutes} 分钟后暂停累计'**
  String statsIdlePauseLabel(Object minutes);

  /// No description provided for @statsDisabledNotice.
  ///
  /// In zh, this message translates to:
  /// **'阅读统计已关闭（SET-015），本页显示的是已有历史记录。'**
  String get statsDisabledNotice;

  /// No description provided for @statsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取统计失败：{reason}'**
  String statsLoadFailed(Object reason);

  /// No description provided for @statsRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get statsRetry;

  /// No description provided for @statsEstimateNote.
  ///
  /// In zh, this message translates to:
  /// **'统计是本机的估计值：只在前台可见且活跃时累计，不跨设备相加。'**
  String get statsEstimateNote;

  /// No description provided for @settingsStatsEntryTitle.
  ///
  /// In zh, this message translates to:
  /// **'阅读统计'**
  String get settingsStatsEntryTitle;

  /// No description provided for @settingsStatsEntrySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'年度热力图与近七日阅读时长'**
  String get settingsStatsEntrySubtitle;

  /// No description provided for @readingFetchFullTextAction.
  ///
  /// In zh, this message translates to:
  /// **'获取原站全文'**
  String get readingFetchFullTextAction;

  /// No description provided for @readingFetchFullTextLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在获取原站正文…'**
  String get readingFetchFullTextLoading;

  /// No description provided for @readingFetchFullTextDone.
  ///
  /// In zh, this message translates to:
  /// **'已提取原站正文（{chars} 字）'**
  String readingFetchFullTextDone(Object chars);

  /// No description provided for @readingFetchFullTextFailed.
  ///
  /// In zh, this message translates to:
  /// **'未能获取原站正文：{reason}'**
  String readingFetchFullTextFailed(Object reason);

  /// No description provided for @readingFetchFullTextViewOriginal.
  ///
  /// In zh, this message translates to:
  /// **'查看原文'**
  String get readingFetchFullTextViewOriginal;

  /// No description provided for @readingFetchFullTextViewExtracted.
  ///
  /// In zh, this message translates to:
  /// **'查看提取正文'**
  String get readingFetchFullTextViewExtracted;

  /// No description provided for @readingFetchFullTextPaywall.
  ///
  /// In zh, this message translates to:
  /// **'原站可能要求付费或登录，可能拿不到全文。'**
  String get readingFetchFullTextPaywall;

  /// No description provided for @readingFetchFullTextShort.
  ///
  /// In zh, this message translates to:
  /// **'提取到的正文很短，原站可能需要脚本渲染。'**
  String get readingFetchFullTextShort;

  /// No description provided for @readingFetchFullTextOpenExternal.
  ///
  /// In zh, this message translates to:
  /// **'在浏览器打开'**
  String get readingFetchFullTextOpenExternal;

  /// No description provided for @readingFetchFullTextNoUrl.
  ///
  /// In zh, this message translates to:
  /// **'这篇文章没有可访问的原站地址。'**
  String get readingFetchFullTextNoUrl;

  /// No description provided for @readingFetchFullTextNoScript.
  ///
  /// In zh, this message translates to:
  /// **'只做 HTTP 抓取与静态解析：不执行脚本，也不绕过付费墙或登录。'**
  String get readingFetchFullTextNoScript;

  /// No description provided for @readingFetchFullTextButtonHint.
  ///
  /// In zh, this message translates to:
  /// **'仅在点击时抓取原站，不会自动或后台执行。'**
  String get readingFetchFullTextButtonHint;

  /// 设置页入口：AI 服务配置
  ///
  /// In zh, this message translates to:
  /// **'AI 服务'**
  String get settingsAiEntryTitle;

  /// 设置页入口副标题
  ///
  /// In zh, this message translates to:
  /// **'提供商、模型、能力与凭据（SET-030–033）'**
  String get settingsAiEntrySubtitle;

  /// AI 服务页标题
  ///
  /// In zh, this message translates to:
  /// **'AI 服务'**
  String get aiPageTitle;

  /// 模型列表分区标题
  ///
  /// In zh, this message translates to:
  /// **'模型与提供商'**
  String get aiModelsSection;

  /// 模型列表为空时的说明
  ///
  /// In zh, this message translates to:
  /// **'还没有配置任何模型。添加一个提供商与模型 ID 之后，AI 功能才可用。'**
  String get aiEmptyNotice;

  /// 新增模型按钮
  ///
  /// In zh, this message translates to:
  /// **'添加模型'**
  String get aiAddModel;

  /// 编辑模型
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get aiEditModel;

  /// 删除模型
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get aiDeleteModel;

  /// 协议选择标签
  ///
  /// In zh, this message translates to:
  /// **'协议'**
  String get aiProtocolLabel;

  /// 协议选择说明
  ///
  /// In zh, this message translates to:
  /// **'协议决定请求与事件流的形状；同名域名下不同路径的协议并不通用。'**
  String get aiProtocolHint;

  /// 协议选项后缀：适配器尚未实现
  ///
  /// In zh, this message translates to:
  /// **'（适配器待实现）'**
  String get aiProtocolPendingSuffix;

  /// 预设选择标签
  ///
  /// In zh, this message translates to:
  /// **'提供商预设'**
  String get aiPresetLabel;

  /// 预设下拉的自定义选项
  ///
  /// In zh, this message translates to:
  /// **'自定义（不套预设）'**
  String get aiPresetCustom;

  /// 预设选择说明：不含凭据
  ///
  /// In zh, this message translates to:
  /// **'预设只填协议与 Base URL，不代填 Key；Key 始终手填，只保存在安全存储里。'**
  String get aiPresetHint;

  /// 显示预设最终端点
  ///
  /// In zh, this message translates to:
  /// **'将请求'**
  String get aiPresetEndpointLabel;

  /// 预设状态徽章：已真实调用成功
  ///
  /// In zh, this message translates to:
  /// **'实测'**
  String get aiPresetStatusLive;

  /// 预设状态徽章：夹具级证据
  ///
  /// In zh, this message translates to:
  /// **'fixture 通过'**
  String get aiPresetStatusFixture;

  /// 预设状态徽章：未验证
  ///
  /// In zh, this message translates to:
  /// **'待验证'**
  String get aiPresetStatusUnverified;

  /// 实测徽章说明
  ///
  /// In zh, this message translates to:
  /// **'本机真的对真实端点发起过调用并成功（见手册轮次记录）。'**
  String get aiPresetStatusLiveHint;

  /// fixture 徽章说明
  ///
  /// In zh, this message translates to:
  /// **'该协议的适配器有完整夹具级证据，但本轮没有对真实端点发起过调用。'**
  String get aiPresetStatusFixtureHint;

  /// 待验证徽章说明
  ///
  /// In zh, this message translates to:
  /// **'本端点尚未做任何真实调用（通常是没有凭据）；不要把它当成已验证可用。'**
  String get aiPresetStatusUnverifiedHint;

  /// AI 服务页的预设状态小节标题
  ///
  /// In zh, this message translates to:
  /// **'预设验证状态'**
  String get aiPresetMatrixTitle;

  /// 验证矩阵说明：不夸大状态
  ///
  /// In zh, this message translates to:
  /// **'「已支持」只写实测过的范围；fixture 通过不等于真实可用。'**
  String get aiPresetMatrixHint;

  /// 没有任何实测预设时的提示
  ///
  /// In zh, this message translates to:
  /// **'本机尚无任何实测通过的预设。'**
  String get aiPresetNoLiveNotice;

  /// 别名标签
  ///
  /// In zh, this message translates to:
  /// **'提供商别名'**
  String get aiAliasLabel;

  /// 别名说明
  ///
  /// In zh, this message translates to:
  /// **'本机唯一，用于标识这份凭据；模型列表与故障转移顺序按它显示。'**
  String get aiAliasHint;

  /// Base URL 标签
  ///
  /// In zh, this message translates to:
  /// **'Base URL'**
  String get aiBaseUrlLabel;

  /// Base URL 说明
  ///
  /// In zh, this message translates to:
  /// **'只填到主机或公共前缀即可，例如 https://api.deepseek.com；协议路径由适配器追加。'**
  String get aiBaseUrlHint;

  /// 模型 ID 标签
  ///
  /// In zh, this message translates to:
  /// **'模型 ID'**
  String get aiModelIdLabel;

  /// 模型 ID 说明
  ///
  /// In zh, this message translates to:
  /// **'列表接口不可用时可以手填；必须与服务商的模型名完全一致。'**
  String get aiModelIdHint;

  /// API Key 标签
  ///
  /// In zh, this message translates to:
  /// **'API Key（SET-031）'**
  String get aiApiKeyLabel;

  /// 已配置 Key 时的遮盖显示；preview 为固定长度的掩码
  ///
  /// In zh, this message translates to:
  /// **'已配置：{preview}'**
  String aiApiKeyConfigured(String preview);

  /// 未配置 Key
  ///
  /// In zh, this message translates to:
  /// **'尚未配置'**
  String get aiApiKeyNotConfigured;

  /// Key 存储说明
  ///
  /// In zh, this message translates to:
  /// **'只写入系统安全存储（钥匙串），不进数据库、不进日志、不随同步或备份外传。'**
  String get aiApiKeyHint;

  /// 替换 Key 按钮
  ///
  /// In zh, this message translates to:
  /// **'替换 Key'**
  String get aiApiKeyReplace;

  /// 删除 Key 按钮
  ///
  /// In zh, this message translates to:
  /// **'删除 Key'**
  String get aiApiKeyClear;

  /// 安全存储不可用提示
  ///
  /// In zh, this message translates to:
  /// **'本机安全存储不可用，本次会话可以填 Key 但不会保存。'**
  String get aiApiKeyUnavailable;

  /// 能力分区标题
  ///
  /// In zh, this message translates to:
  /// **'能力（SET-033）'**
  String get aiCapabilitySection;

  /// 能力说明
  ///
  /// In zh, this message translates to:
  /// **'能力由你声明，不由模型名推断。未声明视觉能力的模型不会收到图片。'**
  String get aiCapabilityHint;

  /// 文本能力
  ///
  /// In zh, this message translates to:
  /// **'文本'**
  String get aiCapabilityText;

  /// 视觉能力
  ///
  /// In zh, this message translates to:
  /// **'视觉'**
  String get aiCapabilityVision;

  /// 流式能力
  ///
  /// In zh, this message translates to:
  /// **'流式'**
  String get aiCapabilityStreaming;

  /// 工具调用能力
  ///
  /// In zh, this message translates to:
  /// **'工具调用'**
  String get aiCapabilityTools;

  /// 结构化输出能力
  ///
  /// In zh, this message translates to:
  /// **'结构化输出'**
  String get aiCapabilityStructured;

  /// 上下文上限标签
  ///
  /// In zh, this message translates to:
  /// **'上下文上限（token）'**
  String get aiContextWindowLabel;

  /// 输出上限标签
  ///
  /// In zh, this message translates to:
  /// **'输出上限（token）'**
  String get aiOutputBudgetLabel;

  /// 保守预算说明
  ///
  /// In zh, this message translates to:
  /// **'留空表示未声明：按保守预算使用（上下文 {context}、输出 {output}），这不是真实能力扩容。'**
  String aiBudgetConservativeHint(int context, int output);

  /// 启用开关
  ///
  /// In zh, this message translates to:
  /// **'启用'**
  String get aiEnabledLabel;

  /// 默认模型开关
  ///
  /// In zh, this message translates to:
  /// **'设为任务默认模型'**
  String get aiDefaultForTasksLabel;

  /// 默认模型标记
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get aiDefaultForTasksBadge;

  /// 上移排序
  ///
  /// In zh, this message translates to:
  /// **'上移（故障转移顺序）'**
  String get aiMoveUp;

  /// 下移排序
  ///
  /// In zh, this message translates to:
  /// **'下移（故障转移顺序）'**
  String get aiMoveDown;

  /// 排序说明
  ///
  /// In zh, this message translates to:
  /// **'顺序决定故障转移的先后（SET-032/035）；停用的模型不参与。'**
  String get aiSortHint;

  /// 保存按钮
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get aiSaveAction;

  /// 取消按钮
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get aiCancelAction;

  /// 表单校验失败提示
  ///
  /// In zh, this message translates to:
  /// **'请检查：{detail}'**
  String aiFormInvalid(String detail);

  /// 测试按钮
  ///
  /// In zh, this message translates to:
  /// **'测试连接与最小生成'**
  String get aiTestButton;

  /// 费用确认标题
  ///
  /// In zh, this message translates to:
  /// **'这次测试会产生费用'**
  String get aiTestCostTitle;

  /// 费用确认正文
  ///
  /// In zh, this message translates to:
  /// **'测试会向 {provider} 发起一次真实生成调用（输出上限 {tokens} token），可能产生费用，且不支持幂等键的协议无法保证只计费一次。是否继续？'**
  String aiTestCostBody(String provider, int tokens);

  /// 费用确认的确认按钮
  ///
  /// In zh, this message translates to:
  /// **'确认并测试'**
  String get aiTestCostConfirm;

  /// 测试进行中
  ///
  /// In zh, this message translates to:
  /// **'正在测试…'**
  String get aiTestRunning;

  /// 测试成功（无 usage 信息时）
  ///
  /// In zh, this message translates to:
  /// **'测试成功：耗时 {elapsedMs} 毫秒，返回 {chars} 字符'**
  String aiTestSuccess(int elapsedMs, int chars);

  /// 测试成功（含 usage）
  ///
  /// In zh, this message translates to:
  /// **'测试成功：耗时 {elapsedMs} 毫秒，输入 {inputTokens} / 输出 {outputTokens} token，返回 {chars} 字符'**
  String aiTestSuccessWithUsage(
    int elapsedMs,
    int inputTokens,
    int outputTokens,
    int chars,
  );

  /// 测试失败
  ///
  /// In zh, this message translates to:
  /// **'测试失败：{reason}'**
  String aiTestFailed(String reason);

  /// 认证失败文案
  ///
  /// In zh, this message translates to:
  /// **'认证失败：Key 可能不正确，或账号余额不足。'**
  String get aiFailureAuth;

  /// 限流文案
  ///
  /// In zh, this message translates to:
  /// **'被服务商限流，请稍后再试。'**
  String get aiFailureRateLimited;

  /// 内容拒绝文案
  ///
  /// In zh, this message translates to:
  /// **'内容被服务商拒绝。这不是网络问题，换一家服务商重试也不能规避。'**
  String get aiFailureContentFiltered;

  /// 网络失败文案
  ///
  /// In zh, this message translates to:
  /// **'网络请求失败：{reason}'**
  String aiFailureNetwork(String reason);

  /// 超时文案
  ///
  /// In zh, this message translates to:
  /// **'请求超时。'**
  String get aiFailureTimeout;

  /// 取消文案
  ///
  /// In zh, this message translates to:
  /// **'已取消。'**
  String get aiFailureCancelled;

  /// 适配器缺失文案
  ///
  /// In zh, this message translates to:
  /// **'该协议的适配器尚未实现，当前无法调用。'**
  String get aiFailureAdapterMissing;

  /// Key 缺失文案
  ///
  /// In zh, this message translates to:
  /// **'尚未配置 API Key。'**
  String get aiFailureCredentialMissing;

  /// 模型停用文案
  ///
  /// In zh, this message translates to:
  /// **'这个模型当前是停用状态。'**
  String get aiFailureDisabled;

  /// 校验失败文案
  ///
  /// In zh, this message translates to:
  /// **'配置无效：{reason}'**
  String aiFailureValidation(String reason);

  /// 存储失败文案
  ///
  /// In zh, this message translates to:
  /// **'本地存储写入失败，本次改动没有保存。'**
  String get aiFailureStorage;

  /// 其它失败文案
  ///
  /// In zh, this message translates to:
  /// **'调用失败：{reason}'**
  String aiFailureUnknown(String reason);

  /// 删除确认标题
  ///
  /// In zh, this message translates to:
  /// **'删除模型「{alias}」？'**
  String aiDeleteConfirmTitle(String alias);

  /// 删除确认正文
  ///
  /// In zh, this message translates to:
  /// **'删除后这条模型记录不再可用。它使用的 API Key 不会被删除。'**
  String get aiDeleteConfirmBody;

  /// 被引用时的删除确认正文
  ///
  /// In zh, this message translates to:
  /// **'这个模型仍被以下配置引用：{references}。删除后这些配置会指向不存在的模型，需要你随后手动修正。'**
  String aiDeleteInUseBody(String references);

  /// 引用来源：任务默认模型
  ///
  /// In zh, this message translates to:
  /// **'任务默认模型'**
  String get aiReferenceDefaultForTasks;

  /// 引用来源：视觉模型
  ///
  /// In zh, this message translates to:
  /// **'SET-034 专用视觉模型'**
  String get aiReferenceVisionModel;

  /// 引用来源：故障转移允许列表
  ///
  /// In zh, this message translates to:
  /// **'SET-035 故障转移允许列表'**
  String get aiReferenceFailover;

  /// 确认删除
  ///
  /// In zh, this message translates to:
  /// **'仍然删除'**
  String get aiDeleteConfirmYes;

  /// 取消删除
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get aiDeleteCancel;

  /// 删除失败
  ///
  /// In zh, this message translates to:
  /// **'删除失败：{reason}'**
  String aiDeleteFailed(String reason);

  /// 保存成功提示
  ///
  /// In zh, this message translates to:
  /// **'已保存。'**
  String get aiSavedNotice;

  /// 读取失败
  ///
  /// In zh, this message translates to:
  /// **'读取模型列表失败：{reason}'**
  String aiLoadFailed(String reason);

  /// 未实现部分说明
  ///
  /// In zh, this message translates to:
  /// **'自动摘要开关（SET-037）属 T034，本页只做提供商与模型配置；故障转移的五次无响应、总时限与 Token 预算已由 T029 落地（见设置 → AI 任务记录）。'**
  String get aiPlannedNotice;

  /// 任务记录页标题
  ///
  /// In zh, this message translates to:
  /// **'AI 任务记录'**
  String get aiTaskListTitle;

  /// 设置页入口
  ///
  /// In zh, this message translates to:
  /// **'AI 任务记录'**
  String get settingsAiTasksEntryTitle;

  /// 设置页入口说明
  ///
  /// In zh, this message translates to:
  /// **'查看历史任务与中断记录，可手动重新开始'**
  String get settingsAiTasksEntrySubtitle;

  /// 空态
  ///
  /// In zh, this message translates to:
  /// **'还没有 AI 任务记录。'**
  String get aiTaskListEmpty;

  /// 读取失败
  ///
  /// In zh, this message translates to:
  /// **'读取 AI 任务列表失败：{reason}'**
  String aiTaskListLoadFailed(String reason);

  /// 重新开始按钮
  ///
  /// In zh, this message translates to:
  /// **'重新开始'**
  String get aiTaskRestart;

  /// 活跃任务不能重开
  ///
  /// In zh, this message translates to:
  /// **'任务仍在进行中，不能重复发起'**
  String get aiTaskRestartBlocked;

  /// 重开成功回执
  ///
  /// In zh, this message translates to:
  /// **'已创建新任务并完成，原任务记录保持不变'**
  String get aiTaskRestartSuccess;

  /// 命中缓存标注
  ///
  /// In zh, this message translates to:
  /// **'命中缓存（未发请求）'**
  String get aiTaskFromCache;

  /// 任务元信息
  ///
  /// In zh, this message translates to:
  /// **'累计 {tokens} token · {attempts} 次尝试'**
  String aiTaskMeta(int tokens, int attempts);

  /// 九态与任务类型文案
  ///
  /// In zh, this message translates to:
  /// **'排队中'**
  String get aiTaskStatusQueued;

  /// 九态与任务类型文案
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get aiTaskStatusRunning;

  /// 九态与任务类型文案
  ///
  /// In zh, this message translates to:
  /// **'等待配置'**
  String get aiTaskStatusWaitingConfiguration;

  /// 九态与任务类型文案
  ///
  /// In zh, this message translates to:
  /// **'等待网络'**
  String get aiTaskStatusWaitingNetwork;

  /// 九态与任务类型文案
  ///
  /// In zh, this message translates to:
  /// **'成功'**
  String get aiTaskStatusSucceeded;

  /// 九态与任务类型文案
  ///
  /// In zh, this message translates to:
  /// **'部分完成'**
  String get aiTaskStatusPartial;

  /// 九态与任务类型文案
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get aiTaskStatusFailed;

  /// 九态与任务类型文案
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get aiTaskStatusCancelled;

  /// 九态与任务类型文案
  ///
  /// In zh, this message translates to:
  /// **'已中断（未自动重发）'**
  String get aiTaskStatusInterrupted;

  /// 九态与任务类型文案
  ///
  /// In zh, this message translates to:
  /// **'每日总结'**
  String get aiTaskKindSummary;

  /// 九态与任务类型文案
  ///
  /// In zh, this message translates to:
  /// **'选词解释'**
  String get aiTaskKindExplain;

  /// 九态与任务类型文案
  ///
  /// In zh, this message translates to:
  /// **'全文翻译'**
  String get aiTaskKindTranslate;

  /// 九态与任务类型文案
  ///
  /// In zh, this message translates to:
  /// **'今日新闻'**
  String get aiTaskKindNews;

  /// 九态与任务类型文案
  ///
  /// In zh, this message translates to:
  /// **'其它任务'**
  String get aiTaskKindOther;

  /// 搜索服务页标题
  ///
  /// In zh, this message translates to:
  /// **'搜索服务'**
  String get searchPageTitle;

  /// 设置页入口
  ///
  /// In zh, this message translates to:
  /// **'搜索服务'**
  String get settingsSearchEntryTitle;

  /// 设置页入口说明
  ///
  /// In zh, this message translates to:
  /// **'Tavily / Brave / 自建 SearXNG 的端点与凭据'**
  String get settingsSearchEntrySubtitle;

  /// 新增按钮
  ///
  /// In zh, this message translates to:
  /// **'添加搜索服务'**
  String get searchAddService;

  /// 编辑对话框标题
  ///
  /// In zh, this message translates to:
  /// **'编辑搜索服务'**
  String get searchEditService;

  /// 列表小节标题
  ///
  /// In zh, this message translates to:
  /// **'搜索服务列表'**
  String get searchServicesSection;

  /// 排序说明
  ///
  /// In zh, this message translates to:
  /// **'顺序即工具执行器选择服务的顺序；停用后不参与选择。'**
  String get searchSortHint;

  /// 空态说明
  ///
  /// In zh, this message translates to:
  /// **'还没有配置任何搜索服务。没有搜索服务时，联网检索类任务会明确提示缺少配置，而不是静默跳过。'**
  String get searchEmptyNotice;

  /// 读取失败
  ///
  /// In zh, this message translates to:
  /// **'读取搜索服务列表失败：{reason}'**
  String searchLoadFailed(String reason);

  /// 默认服务徽章
  ///
  /// In zh, this message translates to:
  /// **'任务默认'**
  String get searchDefaultBadge;

  /// 默认服务开关
  ///
  /// In zh, this message translates to:
  /// **'任务默认搜索'**
  String get searchDefaultLabel;

  /// 预算提示
  ///
  /// In zh, this message translates to:
  /// **'每次取 {maxResults} 条 · 超时 {timeoutSeconds} 秒（SET-040）'**
  String searchBudgetHint(int maxResults, int timeoutSeconds);

  /// 已批准内网
  ///
  /// In zh, this message translates to:
  /// **'已显式批准内网/HTTP 端点（SET-041）'**
  String get searchPrivateApproved;

  /// 缺凭据提示
  ///
  /// In zh, this message translates to:
  /// **'尚未配置凭据：该协议没有 Key 一定失败，因此测试按钮已禁用。'**
  String get searchCredentialMissingHint;

  /// 测试禁用原因
  ///
  /// In zh, this message translates to:
  /// **'请先填写并保存凭据，本协议没有 Key 无法调用'**
  String get searchTestDisabledNoCredential;

  /// 测试按钮
  ///
  /// In zh, this message translates to:
  /// **'测试'**
  String get searchTestButton;

  /// 测试确认标题
  ///
  /// In zh, this message translates to:
  /// **'发送一次真实检索？'**
  String get searchTestConfirmTitle;

  /// 测试确认正文（费用与数据去向）
  ///
  /// In zh, this message translates to:
  /// **'这次会把查询词发送到 {protocol} 的端点 {endpoint}，并可能产生费用。查询词会离开本机。'**
  String searchTestConfirmBody(String protocol, String endpoint);

  /// 确认发送
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get searchTestConfirmYes;

  /// 取消发送
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get searchTestConfirmCancel;

  /// 测试成功回执
  ///
  /// In zh, this message translates to:
  /// **'检索成功：{elapsedMs} ms，返回 {count} 条'**
  String searchTestSuccess(int elapsedMs, int count);

  /// 删除确认标题
  ///
  /// In zh, this message translates to:
  /// **'删除搜索服务「{label}」？'**
  String searchDeleteConfirmTitle(String label);

  /// 删除确认正文
  ///
  /// In zh, this message translates to:
  /// **'删除后这条搜索服务不再可用。它使用的 Key 不会被删除。'**
  String get searchDeleteConfirmBody;

  /// 被引用时的删除确认正文
  ///
  /// In zh, this message translates to:
  /// **'这个搜索服务仍被以下配置引用：{references}。删除后这些配置会指向不存在的服务，需要你随后手动修正。'**
  String searchDeleteInUseBody(String references);

  /// 确认删除
  ///
  /// In zh, this message translates to:
  /// **'仍然删除'**
  String get searchDeleteConfirmYes;

  /// 取消删除
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get searchDeleteCancel;

  /// 删除失败
  ///
  /// In zh, this message translates to:
  /// **'删除失败：{reason}'**
  String searchDeleteFailed(String reason);

  /// 保存按钮
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get searchSaveService;

  /// 服务名字段
  ///
  /// In zh, this message translates to:
  /// **'服务名'**
  String get searchLabelField;

  /// 协议字段
  ///
  /// In zh, this message translates to:
  /// **'协议'**
  String get searchProtocolField;

  /// 端点字段
  ///
  /// In zh, this message translates to:
  /// **'端点地址'**
  String get searchEndpointField;

  /// 端点必填提示
  ///
  /// In zh, this message translates to:
  /// **'自建 SearXNG 实例没有默认地址，必须填写你自己的实例地址。'**
  String get searchEndpointRequiredHint;

  /// 最终端点提示
  ///
  /// In zh, this message translates to:
  /// **'实际请求：{endpoint}'**
  String searchEndpointResolved(String endpoint);

  /// 凭据字段
  ///
  /// In zh, this message translates to:
  /// **'API Key / 实例认证'**
  String get searchKeyField;

  /// 凭据已配置
  ///
  /// In zh, this message translates to:
  /// **'已配置（不回显内容；留空表示不修改）'**
  String get searchKeyConfigured;

  /// 凭据未配置
  ///
  /// In zh, this message translates to:
  /// **'尚未配置'**
  String get searchKeyNotConfigured;

  /// 凭据可选提示
  ///
  /// In zh, this message translates to:
  /// **'该协议凭据可选：留空则不发送认证头（实例由反向代理认证时如此）。'**
  String get searchKeyOptionalHint;

  /// 删除凭据按钮
  ///
  /// In zh, this message translates to:
  /// **'删除已保存的凭据'**
  String get searchDeleteKey;

  /// 结果数字段
  ///
  /// In zh, this message translates to:
  /// **'每次结果数（1–20）'**
  String get searchMaxResultsField;

  /// 超时字段
  ///
  /// In zh, this message translates to:
  /// **'超时秒数（5–60）'**
  String get searchTimeoutField;

  /// 内网批准开关
  ///
  /// In zh, this message translates to:
  /// **'允许内网/HTTP 端点（SET-041）'**
  String get searchAllowPrivateLabel;

  /// 内网批准说明
  ///
  /// In zh, this message translates to:
  /// **'仅在自建实例位于局域网或使用明文 HTTP 时打开。未批准时该端点会被地址守卫拒绝，不会发出请求。'**
  String get searchAllowPrivateHint;

  /// 未实现部分说明
  ///
  /// In zh, this message translates to:
  /// **'查询关键词列表（SET-052）、禁止查询词与主题过滤（SET-053）以及每日新闻的检索编排（T036/T037）属后续任务；本页只做搜索服务本身。'**
  String get searchPlannedNotice;

  /// 详情页：全文翻译入口
  ///
  /// In zh, this message translates to:
  /// **'翻译'**
  String get readingTranslateAction;

  /// 翻译面板标题
  ///
  /// In zh, this message translates to:
  /// **'全文翻译'**
  String get readingTranslateTitle;

  /// 翻译进度（已完成段数 / 总段数）
  ///
  /// In zh, this message translates to:
  /// **'正在逐段翻译…（已完成 {done}/{total} 段）'**
  String readingTranslateRunning(int done, int total);

  /// 翻译完成回执
  ///
  /// In zh, this message translates to:
  /// **'翻译完成：已完成 {done}/{total} 段。'**
  String readingTranslateDone(int done, int total);

  /// 部分成功回执（失败段可单独重试）
  ///
  /// In zh, this message translates to:
  /// **'翻译完成：已完成 {done}/{total} 段，{failed} 段失败（可只重试失败段）。'**
  String readingTranslatePartial(int done, int total, int failed);

  /// 翻译面板：取消进行中的翻译
  ///
  /// In zh, this message translates to:
  /// **'取消翻译'**
  String get readingTranslateCancelAction;

  /// 取消翻译后的提示（取消保留已完成段）
  ///
  /// In zh, this message translates to:
  /// **'已取消翻译，已完成的段落保留，未完成的段落显示原文。'**
  String get readingTranslateCancelled;

  /// 只重试失败段按钮
  ///
  /// In zh, this message translates to:
  /// **'重试失败段（{count} 段）'**
  String readingTranslateRetryFailed(int count);

  /// 重试失败段说明
  ///
  /// In zh, this message translates to:
  /// **'只重跑失败的段落，已完成的译文会保留。'**
  String get readingTranslateRetryHint;

  /// 失败段的说明（渲染在未完成的段上）
  ///
  /// In zh, this message translates to:
  /// **'这一段翻译失败，正文仍显示原文。'**
  String get readingTranslateSegmentFailed;

  /// 切换到原文
  ///
  /// In zh, this message translates to:
  /// **'显示原文'**
  String get readingTranslateShowOriginal;

  /// 切换到译文
  ///
  /// In zh, this message translates to:
  /// **'显示译文'**
  String get readingTranslateShowTranslation;

  /// 原译文切换的说明（原文永远保留）
  ///
  /// In zh, this message translates to:
  /// **'原文始终保留，切换只改变显示。'**
  String get readingTranslateSourceKept;

  /// 有段落被截断的说明
  ///
  /// In zh, this message translates to:
  /// **'有段落超过单段预算（SET-061 的 8000 字符），这些段只翻译了前一部分。'**
  String get readingTranslateTruncatedNotice;

  /// 译文对应旧版正文的说明
  ///
  /// In zh, this message translates to:
  /// **'这篇正文在上次翻译之后变化过；以下译文对应的是上一版正文。'**
  String get readingTranslateStale;

  /// summaryOnly 不提供全文翻译的说明
  ///
  /// In zh, this message translates to:
  /// **'这篇文章的源只提供了摘要（仅摘要），没有可翻译的全文；摘要不当作正文翻译。'**
  String get readingTranslateSummaryOnly;

  /// 没有正文时的跳过说明
  ///
  /// In zh, this message translates to:
  /// **'这篇文章没有正文可翻译，已保留源摘要。'**
  String get readingTranslateNoBody;

  /// 没有可用模型时的提示
  ///
  /// In zh, this message translates to:
  /// **'翻译需要 AI 服务。请先配置至少一个已启用的模型。'**
  String get readingTranslateNoModelBody;

  /// 没有可翻译块时的说明
  ///
  /// In zh, this message translates to:
  /// **'这篇正文里没有可翻译的段落（例如只有一张图片）。'**
  String get readingTranslateNoText;

  /// 翻译失败提示
  ///
  /// In zh, this message translates to:
  /// **'翻译失败：{reason}'**
  String readingTranslateFailed(String reason);

  /// 译文来源与生成时间标注
  ///
  /// In zh, this message translates to:
  /// **'译文 · {model} · {date}'**
  String readingTranslateSavedLabel(String model, String date);

  /// 当前目标语言（SET-011）
  ///
  /// In zh, this message translates to:
  /// **'目标语言：{language}'**
  String readingTranslateLanguage(String language);

  /// 中断后恢复的说明
  ///
  /// In zh, this message translates to:
  /// **'上次翻译未完成（进程被中断），已完成的段落保留；可以重试失败段。'**
  String get readingTranslateInterrupted;

  /// 设置入口：新闻生成
  ///
  /// In zh, this message translates to:
  /// **'新闻生成'**
  String get newsSettingsEntryTitle;

  /// 设置入口说明
  ///
  /// In zh, this message translates to:
  /// **'来源选择、必访网站、关键词与总 prompt（SET-050–055）；今日新闻的生成流程属 T037–T040。'**
  String get newsSettingsEntrySubtitle;

  /// 页面标题
  ///
  /// In zh, this message translates to:
  /// **'新闻生成来源与 prompt'**
  String get newsPageTitle;

  /// 读取失败提示
  ///
  /// In zh, this message translates to:
  /// **'配置读取失败：{reason}；以下显示的是本次运行的初值，不是已保存的配置。'**
  String newsLoadingFailed(String reason);

  /// SET-050 总开关
  ///
  /// In zh, this message translates to:
  /// **'让 RSS 订阅参与新闻选材'**
  String get newsGlobalSwitchLabel;

  /// SET-050 总开关说明
  ///
  /// In zh, this message translates to:
  /// **'关闭后本次生成完全不使用订阅内容；逐源开关只影响单个源，与加精无关。'**
  String get newsGlobalSwitchHint;

  /// 逐源小节标题
  ///
  /// In zh, this message translates to:
  /// **'逐源开关（SET-050）'**
  String get newsFeedSectionTitle;

  /// 逐源说明
  ///
  /// In zh, this message translates to:
  /// **'「跟随」表示按该源的订阅启用状态决定；可以排除某个源的新闻但保留它的订阅刷新。'**
  String get newsFeedSectionHint;

  /// 三态：跟随
  ///
  /// In zh, this message translates to:
  /// **'跟随订阅刷新'**
  String get newsFeedFollow;

  /// 三态：参与
  ///
  /// In zh, this message translates to:
  /// **'参与新闻'**
  String get newsFeedInclude;

  /// 三态：不参与
  ///
  /// In zh, this message translates to:
  /// **'不参与新闻'**
  String get newsFeedExclude;

  /// 订阅刷新已关的标注
  ///
  /// In zh, this message translates to:
  /// **'（订阅刷新已关闭）'**
  String get newsFeedDisabledHint;

  /// 没有任何订阅时的空态
  ///
  /// In zh, this message translates to:
  /// **'还没有订阅源；添加订阅后可以在这里逐源设置。'**
  String get newsFeedEmpty;

  /// 必访小节标题
  ///
  /// In zh, this message translates to:
  /// **'必访问网站（SET-051）'**
  String get newsRequiredSectionTitle;

  /// 必访说明
  ///
  /// In zh, this message translates to:
  /// **'每一站在生成任务里都会被单独获取，并逐站写进总 prompt；停用的站不进 prompt。'**
  String get newsRequiredSectionHint;

  /// 必访空态
  ///
  /// In zh, this message translates to:
  /// **'还没有配置必访问网站。'**
  String get newsRequiredEmpty;

  /// 添加必访站按钮
  ///
  /// In zh, this message translates to:
  /// **'添加网站'**
  String get newsRequiredAdd;

  /// 站点名字段
  ///
  /// In zh, this message translates to:
  /// **'站点名'**
  String get newsRequiredNameField;

  /// 站点地址字段
  ///
  /// In zh, this message translates to:
  /// **'站点地址'**
  String get newsRequiredUrlField;

  /// 保存回执
  ///
  /// In zh, this message translates to:
  /// **'必访问网站已保存。'**
  String get newsRequiredSaved;

  /// 保存失败
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{reason}'**
  String newsRequiredSaveFailed(String reason);

  /// 关键词小节标题
  ///
  /// In zh, this message translates to:
  /// **'联网搜索关键词（SET-052）'**
  String get newsListKeywordsTitle;

  /// 关键词说明
  ///
  /// In zh, this message translates to:
  /// **'空列表且没有 RSS 材料时会提示缺少输入，而不是凭空生成新闻。'**
  String get newsListKeywordsHint;

  /// 查询禁词小节标题
  ///
  /// In zh, this message translates to:
  /// **'禁止发送的查询词（SET-053）'**
  String get newsListBlockedTitle;

  /// 查询禁词说明
  ///
  /// In zh, this message translates to:
  /// **'含这些词的查询不会发给搜索服务（按包含匹配）；它不影响生成时排除哪些主题。'**
  String get newsListBlockedHint;

  /// 主题排除小节标题
  ///
  /// In zh, this message translates to:
  /// **'排除的内容主题（SET-053）'**
  String get newsListTopicsTitle;

  /// 主题排除说明
  ///
  /// In zh, this message translates to:
  /// **'这些主题不会被写进结果；与上面的查询禁词是两个独立列表。'**
  String get newsListTopicsHint;

  /// 列表空态
  ///
  /// In zh, this message translates to:
  /// **'列表为空。'**
  String get newsListEmpty;

  /// 添加输入提示
  ///
  /// In zh, this message translates to:
  /// **'输入后回车添加'**
  String get newsListAddHint;

  /// 列表保存回执
  ///
  /// In zh, this message translates to:
  /// **'列表已保存。'**
  String get newsListSaved;

  /// 列表保存失败
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{reason}'**
  String newsListSaveFailed(String reason);

  /// 模式小节标题
  ///
  /// In zh, this message translates to:
  /// **'总 prompt 模式（SET-055）'**
  String get newsPromptModeTitle;

  /// 模式：自动组合
  ///
  /// In zh, this message translates to:
  /// **'自动组合'**
  String get newsPromptModeComposed;

  /// 模式：高级覆盖
  ///
  /// In zh, this message translates to:
  /// **'高级覆盖'**
  String get newsPromptModeAdvanced;

  /// 组合模式说明
  ///
  /// In zh, this message translates to:
  /// **'按「任务 + 来源 + 规范 + 固定协议」自动组合；下面的组合结果就是实际会发的文本。'**
  String get newsPromptModeComposedHint;

  /// 高级模式说明
  ///
  /// In zh, this message translates to:
  /// **'直接编辑总 prompt。固定引用协议段仍会附加在末尾，且必访站缺失会被提示。'**
  String get newsPromptModeAdvancedHint;

  /// 任务说明字段
  ///
  /// In zh, this message translates to:
  /// **'任务说明'**
  String get newsPromptTaskField;

  /// 输出规范字段
  ///
  /// In zh, this message translates to:
  /// **'输出规范'**
  String get newsPromptSpecField;

  /// 高级 prompt 字段
  ///
  /// In zh, this message translates to:
  /// **'总 prompt（高级覆盖）'**
  String get newsPromptAdvancedField;

  /// 固定协议段标题
  ///
  /// In zh, this message translates to:
  /// **'固定输出协议（不可删除，保存时始终附加）'**
  String get newsPromptCitationFixed;

  /// 恢复默认按钮
  ///
  /// In zh, this message translates to:
  /// **'恢复默认模板'**
  String get newsPromptRestoreDefaults;

  /// 恢复默认回执
  ///
  /// In zh, this message translates to:
  /// **'已恢复内置模板（尚未保存）。'**
  String get newsPromptRestored;

  /// 保存版本按钮
  ///
  /// In zh, this message translates to:
  /// **'保存为新版本'**
  String get newsPromptSaveVersion;

  /// 保存版本回执
  ///
  /// In zh, this message translates to:
  /// **'已保存为版本 {version}。'**
  String newsPromptVersionSaved(int version);

  /// 保存失败
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{reason}'**
  String newsPromptSaveFailed(String reason);

  /// 版本列表标题
  ///
  /// In zh, this message translates to:
  /// **'版本（可回退）'**
  String get newsPromptVersionsTitle;

  /// 没有版本时的说明
  ///
  /// In zh, this message translates to:
  /// **'还没有保存过版本；当前使用内置模板。'**
  String get newsPromptVersionNone;

  /// 版本条目
  ///
  /// In zh, this message translates to:
  /// **'版本 {version} · {mode}'**
  String newsPromptVersionItem(int version, String mode);

  /// 载入某个版本按钮
  ///
  /// In zh, this message translates to:
  /// **'载入这一版'**
  String get newsPromptVersionUse;

  /// 载入版本回执
  ///
  /// In zh, this message translates to:
  /// **'已载入版本 {version}；保存后才会成为当前配置。'**
  String newsPromptVersionLoaded(int version);

  /// 删除版本按钮
  ///
  /// In zh, this message translates to:
  /// **'删除这一版'**
  String get newsPromptVersionDelete;

  /// 差异提示标题
  ///
  /// In zh, this message translates to:
  /// **'必访任务缺失提示'**
  String get newsPromptDiffTitle;

  /// 缺失必访站提示
  ///
  /// In zh, this message translates to:
  /// **'当前总 prompt 里没有出现这些必访网站：{sites}。它们仍然被列为必访任务，任务执行时会逐站获取；请确认这是你要的。'**
  String newsPromptDiffMissing(String sites);

  /// 缺引用标记提示
  ///
  /// In zh, this message translates to:
  /// **'当前总 prompt 里没有出现引用标记（形如 [sourceId]）；固定协议段仍会在发送时附加，但建议保留你自己的引用要求。'**
  String get newsPromptDiffCitationMissing;

  /// 预览标题
  ///
  /// In zh, this message translates to:
  /// **'实际会发送的 prompt'**
  String get newsPromptPreviewTitle;

  /// 预览说明
  ///
  /// In zh, this message translates to:
  /// **'下面是组合或覆盖后的完整文本（含固定协议段）。复制它可核对实际请求内容。'**
  String get newsPromptPreviewHint;

  /// 生效查询标题
  ///
  /// In zh, this message translates to:
  /// **'实际会发送的查询（已应用禁词）'**
  String get newsEffectiveQueriesTitle;

  /// 没有生效查询时的说明
  ///
  /// In zh, this message translates to:
  /// **'当前没有可发送的查询（关键词为空或被禁词全部挡住）。'**
  String get newsEffectiveQueriesEmpty;

  /// 未实现部分说明
  ///
  /// In zh, this message translates to:
  /// **'今日新闻的检索编排、事件聚合与初稿（T037）、来源核验（T038）与定时执行（T040）属后续任务；本页只做 SET-050–055 的配置。'**
  String get newsPlannedNotice;

  /// 今日页生成按钮
  ///
  /// In zh, this message translates to:
  /// **'生成今天的新闻'**
  String get todayGenerate;

  /// 当天已有成功版本时的生成按钮
  ///
  /// In zh, this message translates to:
  /// **'再生成一次'**
  String get todayRegenerate;

  /// 取消正在进行的生成
  ///
  /// In zh, this message translates to:
  /// **'取消生成'**
  String get todayCancelGenerate;

  /// 日期选择标签
  ///
  /// In zh, this message translates to:
  /// **'查看日期'**
  String get todayDateLabel;

  /// 前一天按钮
  ///
  /// In zh, this message translates to:
  /// **'前一天'**
  String get todayPreviousDay;

  /// 后一天按钮
  ///
  /// In zh, this message translates to:
  /// **'后一天'**
  String get todayNextDay;

  /// 进度标题
  ///
  /// In zh, this message translates to:
  /// **'生成进度'**
  String get todayProgressTitle;

  /// 阶段：快照
  ///
  /// In zh, this message translates to:
  /// **'固化输入快照'**
  String get todayStageSnapshot;

  /// 阶段：必访站
  ///
  /// In zh, this message translates to:
  /// **'逐个获取必访网站'**
  String get todayStageRequiredSites;

  /// 阶段：检索
  ///
  /// In zh, this message translates to:
  /// **'联网检索'**
  String get todayStageSearch;

  /// 阶段：生成
  ///
  /// In zh, this message translates to:
  /// **'生成初稿'**
  String get todayStageGenerate;

  /// 阶段：核验
  ///
  /// In zh, this message translates to:
  /// **'独立来源核验'**
  String get todayStageVerify;

  /// 阶段：保存
  ///
  /// In zh, this message translates to:
  /// **'保存版本'**
  String get todayStageSave;

  /// 空态标题
  ///
  /// In zh, this message translates to:
  /// **'这一天还没有新闻'**
  String get todayNoVersionTitle;

  /// 空态说明
  ///
  /// In zh, this message translates to:
  /// **'新闻由你点「生成」后产生：会用当前配置的必访网站、搜索关键词与模型，基于本机文章与联网检索材料生成带引用的条目。未生成前这里是空的，不会编造内容。'**
  String get todayNoVersionBody;

  /// 材料数说明
  ///
  /// In zh, this message translates to:
  /// **'本次输入材料 {count} 条'**
  String todayMaterialCount(int count);

  /// 被退回条目数
  ///
  /// In zh, this message translates to:
  /// **'其中 {count} 条因引用不实被退回'**
  String todayRejectedCount(int count);

  /// 逐站状态标题
  ///
  /// In zh, this message translates to:
  /// **'必访网站获取情况'**
  String get todaySiteFailedTitle;

  /// 站点成功
  ///
  /// In zh, this message translates to:
  /// **'已获取（{chars} 字符）'**
  String todaySiteOk(int chars);

  /// 站点超时
  ///
  /// In zh, this message translates to:
  /// **'超时未完成'**
  String get todaySiteTimeout;

  /// 站点失败
  ///
  /// In zh, this message translates to:
  /// **'获取失败（{reason}）'**
  String todaySiteFailed(String reason);

  /// 站点未执行
  ///
  /// In zh, this message translates to:
  /// **'本次未执行'**
  String get todaySiteSkipped;

  /// 证据标签：来源单一
  ///
  /// In zh, this message translates to:
  /// **'来源单一'**
  String get todayLabelSingleSource;

  /// 证据标签：材料不足
  ///
  /// In zh, this message translates to:
  /// **'材料不足'**
  String get todayLabelInsufficient;

  /// 证据标签：来源冲突
  ///
  /// In zh, this message translates to:
  /// **'来源冲突'**
  String get todayLabelConflict;

  /// 证据标签：未联网核验
  ///
  /// In zh, this message translates to:
  /// **'未联网核验'**
  String get todayLabelNotVerified;

  /// 标签说明
  ///
  /// In zh, this message translates to:
  /// **'标签说明：来源单一 = 只找到一条独立来源；材料不足 = 核验没有拿到可用结果；来源冲突 = 第二条来源明确否定；未联网核验 = 没有配置搜索服务。这些是核验过程的说明，不是对真实性的保证。'**
  String get todayLabelLegend;

  /// 引用类型：本机文章
  ///
  /// In zh, this message translates to:
  /// **'本机文章'**
  String get todayCitationLocal;

  /// 引用外开按钮
  ///
  /// In zh, this message translates to:
  /// **'在浏览器打开'**
  String get todayCitationOpen;

  /// 引用获取方式：RSS
  ///
  /// In zh, this message translates to:
  /// **'RSS'**
  String get todayCitationRss;

  /// 引用获取方式：抓取
  ///
  /// In zh, this message translates to:
  /// **'抓取'**
  String get todayCitationFetch;

  /// 引用获取方式：检索
  ///
  /// In zh, this message translates to:
  /// **'检索片段'**
  String get todayCitationSearch;

  /// 引用不完整提示
  ///
  /// In zh, this message translates to:
  /// **'这一条引用缺字段：{fields}'**
  String todayCitationIncomplete(String fields);

  /// 编造引用提示
  ///
  /// In zh, this message translates to:
  /// **'模型引用的这些材料不存在，相关条目已退回：{ids}'**
  String todayUnknownCitation(String ids);

  /// 版本列表标题
  ///
  /// In zh, this message translates to:
  /// **'历史版本'**
  String get todayVersionsTitle;

  /// 版本条目
  ///
  /// In zh, this message translates to:
  /// **'版本 {version}（{status}）'**
  String todayVersionItem(int version, String status);

  /// 当前版本标记
  ///
  /// In zh, this message translates to:
  /// **'当前展示'**
  String get todayVersionCurrent;

  /// 切换版本按钮
  ///
  /// In zh, this message translates to:
  /// **'切换到这一版'**
  String get todayVersionUse;

  /// 切换版本回执
  ///
  /// In zh, this message translates to:
  /// **'已切换到版本 {version}'**
  String todayVersionSwitched(int version);

  /// 初稿版本标记
  ///
  /// In zh, this message translates to:
  /// **'初稿'**
  String get todayDraftLabel;

  /// 核验后版本标记
  ///
  /// In zh, this message translates to:
  /// **'核验后'**
  String get todayVerifiedLabel;

  /// 模型元数据
  ///
  /// In zh, this message translates to:
  /// **'模型：{model}'**
  String todayModelLabel(String model);

  /// 核验方法记录
  ///
  /// In zh, this message translates to:
  /// **'核验方法：{method}'**
  String todayVerificationMethod(String method);

  /// 费用确认标题
  ///
  /// In zh, this message translates to:
  /// **'确认生成（会产生费用）'**
  String get todayCostConfirmTitle;

  /// 费用确认正文
  ///
  /// In zh, this message translates to:
  /// **'生成会用到模型调用与联网检索，可能产生费用：本次最多 {articles} 篇文章、{sites} 个必访网站、{queries} 个查询，并受总时限与 Token 预算约束。这是一次真实的网络请求与数据发送。'**
  String todayCostConfirmBody(int articles, int sites, int queries);

  /// 再生成的额外说明
  ///
  /// In zh, this message translates to:
  /// **'这一天已经有生成的版本；再生成一次会新增一个版本并再次产生费用。'**
  String get todayCostConfirmRegenerate;

  /// 确认按钮
  ///
  /// In zh, this message translates to:
  /// **'确认生成'**
  String get todayCostConfirmSend;

  /// 取消按钮
  ///
  /// In zh, this message translates to:
  /// **'先不生成'**
  String get todayCostConfirmCancel;

  /// 生成失败说明
  ///
  /// In zh, this message translates to:
  /// **'本次生成没有完成：{reason}'**
  String todayGenerateFailed(String reason);

  /// 生成成功回执
  ///
  /// In zh, this message translates to:
  /// **'已保存为新版本 {version}'**
  String todayGenerateSucceeded(int version);

  /// 缺输入说明
  ///
  /// In zh, this message translates to:
  /// **'本次没有可用输入（没有参与新闻的文章、没有关键词、必访网站也没有取到内容），因此没有生成任何内容。请检查 SET-050 的选材开关、必访列表与文章是否已刷新。'**
  String get todayShortfallNoInput;

  /// 总开关关闭说明
  ///
  /// In zh, this message translates to:
  /// **'RSS 内容总开关当前是关闭的，且没有其它输入（关键词/必访网站），因此没有生成。可在「设置 → 新闻生成」打开总开关。'**
  String get todayShortfallGlobalDisabled;

  /// 今日页底部说明
  ///
  /// In zh, this message translates to:
  /// **'标签、版本与材料都来自本机记录；模型输出不是事实保证，请按引用自行核对。'**
  String get todayJournalNotice;

  /// 今日页顶部日期条带说明
  ///
  /// In zh, this message translates to:
  /// **'近 7 天'**
  String get todayRecentLabel;

  /// 日历弹层入口
  ///
  /// In zh, this message translates to:
  /// **'选择历史日期'**
  String get todayPickDate;

  /// 日期条带上的今天标记
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get todayTodayChip;

  /// 当前查看的就是今天时的说明
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get todayIsToday;

  /// 历史日期说明
  ///
  /// In zh, this message translates to:
  /// **'正在查看历史日期 {date} 的版本。历史记录按生成当时的设备时区归属，不会因现在换时区而改写。'**
  String todayHistoryBanner(String date);

  /// 生成中的逐站进度标题
  ///
  /// In zh, this message translates to:
  /// **'必访网站（逐站）'**
  String get todaySitesProgressTitle;

  /// 必访站尚未轮到
  ///
  /// In zh, this message translates to:
  /// **'待获取'**
  String get todaySitePending;

  /// 取消已请求、任务尚未收尾
  ///
  /// In zh, this message translates to:
  /// **'正在取消…'**
  String get todayCancelling;

  /// 非成功记录的状态说明标题
  ///
  /// In zh, this message translates to:
  /// **'本次生成状态'**
  String get todayStatusTitle;

  /// 状态说明：取消
  ///
  /// In zh, this message translates to:
  /// **'本次生成已取消（已完成的阶段信息保留在下面的记录里）。'**
  String get todayStatusCancelled;

  /// 状态说明：中断
  ///
  /// In zh, this message translates to:
  /// **'这次任务没有跑完就被系统终止了（应用退出或崩溃）。不会自动重发，避免为可能已经计费的内容再发一次请求；可在需要时手动重新生成。'**
  String get todayStatusInterrupted;

  /// 状态说明：等待配置
  ///
  /// In zh, this message translates to:
  /// **'缺少必要配置（没有启用的 AI 模型，或首次费用告知未确认），因此本次没有发出任何请求。补齐配置后可以重新生成。'**
  String get todayStatusWaitingConfiguration;

  /// 状态说明：等待网络
  ///
  /// In zh, this message translates to:
  /// **'生成时设备无网络，任务暂停后结束，没有产出可用结果。联网后可以重新生成。'**
  String get todayStatusWaitingNetwork;

  /// 状态说明：仍在运行/中断的占位
  ///
  /// In zh, this message translates to:
  /// **'有一条任务记录停在“进行中”：若应用曾被强制退出，它已被标为中断，不会自动重发。'**
  String get todayStatusRunning;

  /// 状态说明：失败
  ///
  /// In zh, this message translates to:
  /// **'本次生成失败：{reason}。上一版成功总结没有受影响。'**
  String todayStatusFailed(String reason);

  /// 状态说明：材料不足
  ///
  /// In zh, this message translates to:
  /// **'材料不足：没有取到足够的输入（没有参与新闻的文章、没有关键词、必访网站也没有取到内容），因此没有生成条目，也不会编造内容。'**
  String get todayStatusInsufficient;

  /// 中止阶段说明
  ///
  /// In zh, this message translates to:
  /// **'中止于「{stage}」这一步。'**
  String todayStatusStage(String stage);

  /// 有记录但没有可用结果
  ///
  /// In zh, this message translates to:
  /// **'这一天的生成还没有产出可用条目。'**
  String get todayNoResultYet;

  /// 版本条目（含时间与模型）
  ///
  /// In zh, this message translates to:
  /// **'版本 {version} · {status} · {time} · {model}'**
  String todayVersionItemDetail(
    int version,
    String status,
    String time,
    String model,
  );

  /// 记录里没有模型信息
  ///
  /// In zh, this message translates to:
  /// **'模型未记录'**
  String get todayVersionModelUnknown;

  /// 删除历史版本按钮
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get todayVersionDelete;

  /// 删除按钮提示
  ///
  /// In zh, this message translates to:
  /// **'删除这个历史版本（当前展示的版本不能删）'**
  String get todayVersionDeleteTooltip;

  /// 删除确认标题
  ///
  /// In zh, this message translates to:
  /// **'删除版本 {version}？'**
  String todayVersionDeleteConfirmTitle(int version);

  /// 删除确认正文
  ///
  /// In zh, this message translates to:
  /// **'将永久删除这一天的版本 {version}。当前展示的版本不会被删除，其它版本与材料记录不受影响。'**
  String todayVersionDeleteConfirmBody(int version);

  /// 删除确认按钮
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get todayVersionDeleteConfirmOk;

  /// 删除取消按钮
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get todayVersionDeleteCancel;

  /// 删除成功回执
  ///
  /// In zh, this message translates to:
  /// **'已删除版本 {version}'**
  String todayVersionDeleted(int version);

  /// 删除失败回执
  ///
  /// In zh, this message translates to:
  /// **'删除失败：{reason}'**
  String todayVersionDeleteFailed(String reason);

  /// 本机正文已清理说明
  ///
  /// In zh, this message translates to:
  /// **'这篇本机文章的正文已被清理（例如清理过缓存），只能显示当时保存的最小摘录。'**
  String get todayCitationContentCleared;

  /// 引用摘录为空时的说明
  ///
  /// In zh, this message translates to:
  /// **'原文已清理，只保留最小摘录。'**
  String get todayCitationExcerptCleared;

  /// 历史记录里正文已被清理的条数
  ///
  /// In zh, this message translates to:
  /// **'这一天有 {count} 条引用对应的本机文章正文已被清理，仍显示当时保存的最小摘录。'**
  String todayCacheClearedNotice(int count);

  /// 定时小节标题
  ///
  /// In zh, this message translates to:
  /// **'每日定时总结'**
  String get newsScheduleTitle;

  /// SET-056 开关标签
  ///
  /// In zh, this message translates to:
  /// **'本设备自动定时总结'**
  String get newsScheduleEnableLabel;

  /// SET-056 开关说明
  ///
  /// In zh, this message translates to:
  /// **'默认开启。开启后每天到点会自动运行一次总结；未完成配置或未确认费用告知时会显示「等待配置」，不会发出任何请求。这是本机项，不随同步传给其它设备。'**
  String get newsScheduleEnableHint;

  /// SET-057 时间标签
  ///
  /// In zh, this message translates to:
  /// **'每天执行时间'**
  String get newsScheduleTimeLabel;

  /// SET-057 时间说明
  ///
  /// In zh, this message translates to:
  /// **'按当前设备时区计算。当前时区：{zone}。'**
  String newsScheduleTimeHint(String zone);

  /// 打开时间选择器
  ///
  /// In zh, this message translates to:
  /// **'修改时间'**
  String get newsScheduleTimeEdit;

  /// 时间保存回执
  ///
  /// In zh, this message translates to:
  /// **'执行时间已改为 {time}'**
  String newsScheduleTimeSaved(String time);

  /// 下次运行时间
  ///
  /// In zh, this message translates to:
  /// **'下次运行：{time}'**
  String newsScheduleNextRun(String time);

  /// 今天已生成
  ///
  /// In zh, this message translates to:
  /// **'今日已完成（不会重复自动运行）'**
  String get newsScheduleCompletedToday;

  /// 定时任务正在运行
  ///
  /// In zh, this message translates to:
  /// **'正在运行…'**
  String get newsScheduleRunning;

  /// SET-056 关闭说明
  ///
  /// In zh, this message translates to:
  /// **'已关闭：这台设备不会自动运行定时总结。'**
  String get newsScheduleDisabled;

  /// 等待配置标题
  ///
  /// In zh, this message translates to:
  /// **'等待配置：不会发出任何请求'**
  String get newsScheduleWaitingTitle;

  /// 等待配置：没有模型
  ///
  /// In zh, this message translates to:
  /// **'没有启用的 AI 模型。请到「AI 服务」添加并启用一个模型。'**
  String get newsScheduleWaitingNoModel;

  /// 等待配置：没有凭据
  ///
  /// In zh, this message translates to:
  /// **'已启用的模型没有配置 API Key。请到「AI 服务」补上凭据。'**
  String get newsScheduleWaitingNoCredential;

  /// 等待配置：费用告知未确认
  ///
  /// In zh, this message translates to:
  /// **'尚未确认定时任务的费用与数据发送告知。确认后才会自动运行。'**
  String get newsScheduleWaitingCostNotice;

  /// 等待配置：模型列表读失败
  ///
  /// In zh, this message translates to:
  /// **'读取模型列表失败，暂时无法判断是否可以运行，因此没有发出请求。'**
  String get newsScheduleWaitingModelReadFailed;

  /// 等待配置：其它原因
  ///
  /// In zh, this message translates to:
  /// **'缺少运行所需的配置，因此没有发出请求。'**
  String get newsScheduleWaitingUnknown;

  /// 确认费用告知按钮
  ///
  /// In zh, this message translates to:
  /// **'我已了解（会按计划自动运行）'**
  String get newsScheduleCostNoticeAck;

  /// 确认费用告知回执
  ///
  /// In zh, this message translates to:
  /// **'已确认；定时任务会在下次到点时运行。'**
  String get newsScheduleCostNoticeDone;

  /// 确认写入失败
  ///
  /// In zh, this message translates to:
  /// **'确认写入失败：{reason}。为避免未经告知的付费运行，定时任务仍不会自动执行。'**
  String newsScheduleCostNoticeFailed(String reason);

  /// 费用告知正文
  ///
  /// In zh, this message translates to:
  /// **'定时总结会在每天 {time}（设备当地时间）自动运行一次：它会联网检索、抓取必访网站并调用你配置的模型，可能产生费用；当天已有成功版本时不会重复自动运行。macOS 上应用退出后不会后台执行——错过的时点会在下次打开应用时补跑一次（仅当天）。'**
  String newsScheduleCostNoticeBody(String time);

  /// 缺搜索服务的提示（非阻塞）
  ///
  /// In zh, this message translates to:
  /// **'未配置联网搜索：定时总结仍会运行，但核验会标注「未联网核验」。'**
  String get newsScheduleSearchMissing;

  /// 上次自动运行失败说明
  ///
  /// In zh, this message translates to:
  /// **'上次自动运行未完成（{reason}）。'**
  String newsScheduleLastRunFailed(String reason);

  /// 中断语义说明
  ///
  /// In zh, this message translates to:
  /// **'应用退出时正在进行的任务会被标为「中断」，不会自动重发（避免为可能已计费的内容再付一次）。'**
  String get newsScheduleInterruptedNote;

  /// 时间选择器标题
  ///
  /// In zh, this message translates to:
  /// **'选择每天的执行时间'**
  String get newsScheduleTimePickerTitle;
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
