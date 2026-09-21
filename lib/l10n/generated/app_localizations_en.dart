// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Flux';

  @override
  String get appTagline => 'Local-first news & RSS reader';

  @override
  String get milestoneShellNotice =>
      'This build is the M0 app shell: navigation, theme, language and first-run setup only. No product feature is implemented yet.';

  @override
  String get placeholderBadge => 'Placeholder';

  @override
  String placeholderPageBody(String tasks) {
    return 'This page is an app-shell placeholder with no data or interaction. Planned tasks: $tasks.';
  }

  @override
  String get layoutPaneSource => 'Feed pane';

  @override
  String get layoutPaneList => 'Article list';

  @override
  String get layoutPaneBody => 'Body pane';

  @override
  String get layoutBreakpointSingle => 'Single column (window width < 600)';

  @override
  String get layoutBreakpointDouble => 'Two columns (600–1099)';

  @override
  String get layoutBreakpointTriple => 'Three columns (≥1100)';

  @override
  String get layoutShellNote =>
      'This milestone is shell only: every area below is a placeholder panel with no data, no interaction, and no claim that the region is implemented.';

  @override
  String get navToday => 'Today';

  @override
  String get navReading => 'Reading';

  @override
  String get navMine => 'Mine';

  @override
  String get emptyNoFeedsTitle => 'No subscriptions yet';

  @override
  String get emptyNoFeedsBody =>
      'Articles will appear here once you add a feed or import OPML. The subscription UI and use cases ship in T013–T016.';

  @override
  String get emptyAllReadTitle => 'Everything is read';

  @override
  String get emptyAllReadBody =>
      'No unread articles match the current filter. Switch to Later or Favorites to review what you already handled.';

  @override
  String get emptyNoResultsTitle => 'No matching results';

  @override
  String get emptyNoResultsBody =>
      'Try another keyword, or adjust the search scope and filters. Local full-text search ships in T022.';

  @override
  String get todayEmptyTitle => 'No news for today yet';

  @override
  String get todayEmptyBody =>
      'Daily news needs configured AI and search services plus a first-send acknowledgement. Sources, prompt, generation and verification ship in T036–T040; while unconfigured this page stays empty instead of inventing content.';

  @override
  String get shellDatabaseFailedTitle => 'The local database cannot be opened';

  @override
  String get shellDatabaseFailedBody =>
      'This run can only show the shell: language and theme changes will not be saved. The original database file is left untouched — check disk space and file permissions, then restart.';

  @override
  String onboardingStepIndicator(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingBack => 'Back';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingStart => 'Get started';

  @override
  String get onboardingWelcomeTitle => 'Welcome to Flux';

  @override
  String get onboardingWelcomeBody =>
      'Subscriptions, article text, reading state and summaries all stay on your own device. Flux has no account and no backend service; AI, web search and WebDAV are configured by you at your own cost. Before data is first sent to a service, Flux tells you the recipient and the allowed capabilities item by item.';

  @override
  String get onboardingOfflineNote =>
      'Offline reading and local search do not depend on AI and keep working without a network.';

  @override
  String get onboardingFeedsTitle => 'Add subscriptions';

  @override
  String get onboardingFeedsBody =>
      'Single-feed add/edit, groups and OPML batch import ship in T013–T016. There is no usable import UI yet, so this step creates nothing and fabricates no sample data; skip it and add feeds later inside the app.';

  @override
  String get onboardingFeedsSkipNote =>
      'Skipping changes no future behaviour and writes no subscription.';

  @override
  String get onboardingAiTitle => 'AI and search (optional)';

  @override
  String get onboardingAiBody =>
      'Offline reading, local search and reading statistics work fully without AI or search services. Provider protocols, model management, credentials, connectivity tests and cost warnings ship in T025/T031; until then this step asks for no credential and sends no request.';

  @override
  String get onboardingAiSkipNote =>
      'You can start without configuring AI: every local feature is unaffected.';

  @override
  String get onboardingAppearanceNote =>
      'Interface language and theme stay editable in Mine → Reading & appearance. Changing the language never rewrites AI output that was already generated.';

  @override
  String get settingsTitle => 'Mine';

  @override
  String get settingsSectionShell => 'Reading & appearance';

  @override
  String get settingsSectionAppearancePlanned =>
      'Reading & appearance settings not implemented yet';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsLanguageLabel => 'Interface language';

  @override
  String get settingsLanguageId => 'SET-001';

  @override
  String get settingsLanguageHint =>
      'Following the system resolves per device; when nothing matches, English is used. Articles are never auto-translated.';

  @override
  String get settingsThemeLabel => 'Theme';

  @override
  String get settingsThemeId => 'SET-002';

  @override
  String get settingsThemeHint =>
      'Light, dark or follow the system; following the system resolves independently on each device.';

  @override
  String get settingsOptionFollowSystem => 'Follow system';

  @override
  String get settingsOptionChinese => '简体中文';

  @override
  String get settingsOptionEnglish => 'English';

  @override
  String get settingsOptionLight => 'Light';

  @override
  String get settingsOptionDark => 'Dark';

  @override
  String get settingsWriteFailed =>
      'The change was not saved (write failed or the value was rejected). The displayed value is still the stored one.';

  @override
  String get settingsPlannedNotice =>
      'The settings below are not implemented. To avoid fake working switches, only their name, ID and classification are listed and they cannot be changed; each UI ships in its own task.';

  @override
  String get settingsPlannedBadge => 'Coming soon';

  @override
  String get settingsClassificationCommon => 'Common · syncable';

  @override
  String get settingsClassificationDevice => 'This device';

  @override
  String get settingsClassificationSecret => 'Secret · local only';

  @override
  String get settingsItemSet003 => 'Theme background images';

  @override
  String get settingsItemSet004 => 'Background opacity, blur and brightness';

  @override
  String get settingsItemSet005 => 'UI, article and news fonts';

  @override
  String get settingsItemSet006 => 'UI, article and news font sizes';

  @override
  String get settingsItemSet007 => 'Paper background, reading font and scale';

  @override
  String get settingsItemSet008 => 'List view and desktop column width';

  @override
  String get settingsItemSet009 => 'List sorting, filter and return position';

  @override
  String get settingsItemSet010 => 'Mark read after the article body is shown';

  @override
  String get settingsItemSet011 => 'Translation target and generation language';

  @override
  String get settingsItemSet012 => 'Load remote images automatically';

  @override
  String get settingsItemSet013 => 'Allow media download on metered networks';

  @override
  String get settingsItemSet014 => 'Reduce motion';

  @override
  String get settingsItemSet015 => 'Reading statistics and idle pause';

  @override
  String get settingsItemSet016 => 'Focus reading layout';

  @override
  String settingsItemPlannedTask(String task) {
    return 'Planned task $task';
  }

  @override
  String get aboutVersionLabel => 'Version';

  @override
  String aboutVersionValue(String version) {
    return '$version (M0 skeleton version placeholder; the release version is fixed in T054)';
  }

  @override
  String get aboutLicenseLabel => 'License';

  @override
  String get aboutLicenseValue => 'MIT License';

  @override
  String get aboutLicenseNote =>
      'The repository LICENSE is MIT; the full third-party and original-asset notices land in T054.';

  @override
  String get aboutRepositoryLabel => 'GitHub repository';

  @override
  String get aboutRepositoryValue => 'https://github.com/GuZhengSVT/Flux';

  @override
  String get aboutIssueLabel => 'Issue tracker';

  @override
  String get aboutIssueValue => 'https://github.com/GuZhengSVT/Flux/issues';

  @override
  String get aboutDeveloperLabel => 'Developer';

  @override
  String get aboutDeveloperValue => 'GuZhengSVT';

  @override
  String get aboutNotConfigured => 'Not configured';

  @override
  String get aboutReadOnlyNote =>
      'About shows read-only release metadata (SET-084).';

  @override
  String get aboutUnverifiedNote =>
      'The repository and issue URLs come from release metadata built into this app and were verified on 2026-09-21 through GitHub\'s public API (exists, not archived, issues enabled). An empty address reads \"Not configured\" instead of a guess. Update checking and the release link ship in T053.';

  @override
  String get readingStateLabel => 'Reading state';

  @override
  String get readingStateUnread => 'Unread';

  @override
  String get readingStateRead => 'Read';

  @override
  String get readingStateLater => 'Read later';

  @override
  String get readingStateControlHint =>
      'Click or press Enter to cycle through unread, read and read later';

  @override
  String readingStateSwitched(String state) {
    return 'Reading state changed to $state';
  }

  @override
  String get favoriteToggleLabel => 'Favourite';

  @override
  String get favoriteAddLabel => 'Add to favourites';

  @override
  String get favoriteRemoveLabel => 'Remove from favourites';

  @override
  String get favoriteToggleHint =>
      'Favourites are independent of reading state and never change unread, read or read later';

  @override
  String get featuredBadgeLabel => 'Featured';

  @override
  String get controlLoadingLabel => 'Loading';

  @override
  String get controlSuccessLabel => 'Done';

  @override
  String get controlErrorLabel => 'Failed';

  @override
  String get controlDisabledLabelSuffix => 'unavailable';
}
