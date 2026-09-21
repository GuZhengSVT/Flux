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
