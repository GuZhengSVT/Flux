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

  @override
  String get subscriptionManagerTitle => 'Subscriptions';

  @override
  String get subscriptionManagerNotice =>
      'This page manages feeds and groups; the article list and batch state actions ship in T017-T019.';

  @override
  String get subscriptionGroupsSection => 'Groups and feeds';

  @override
  String get subscriptionAddFeed => 'Add feed';

  @override
  String get subscriptionAddFeedTitle => 'Add a feed';

  @override
  String get subscriptionFeedUrlLabel => 'Feed address';

  @override
  String get subscriptionFeedUrlHint =>
      'A full http/https address, for example https://example.com/feed.xml';

  @override
  String get subscriptionPreviewAction => 'Preview';

  @override
  String get subscriptionPreviewTitle => 'Preview';

  @override
  String get subscriptionPreviewFormat => 'Format';

  @override
  String subscriptionPreviewEntries(int count) {
    return '$count articles';
  }

  @override
  String subscriptionPreviewRejected(int count) {
    return '$count entries skipped';
  }

  @override
  String get subscriptionPreviewNormalized => 'Normalised address';

  @override
  String get subscriptionPreviewDuplicateTitle =>
      'This address is already subscribed';

  @override
  String subscriptionPreviewDuplicateBody(String name) {
    return 'A subscription to this address already exists (\"$name\"). Its group, featured flag and refresh settings are unchanged.';
  }

  @override
  String get subscriptionConfirmAdd => 'Add';

  @override
  String get subscriptionCancel => 'Cancel';

  @override
  String get subscriptionSave => 'Save';

  @override
  String get subscriptionClose => 'Close';

  @override
  String get subscriptionFeedNameLabel => 'Display name';

  @override
  String get subscriptionFeedGroupLabel => 'Group';

  @override
  String subscriptionAddSuccess(String name, int count) {
    return 'Added \"$name\" with $count articles';
  }

  @override
  String subscriptionAddSuccessEmpty(String name) {
    return 'Added \"$name\"; the feed has no articles to import right now';
  }

  @override
  String get subscriptionErrorInvalidUrl =>
      'Invalid address: enter a full http/https feed URL';

  @override
  String get subscriptionErrorNetwork =>
      'Fetch failed: check the network and try again';

  @override
  String get subscriptionErrorParse =>
      'Parse failed: this address does not serve RSS/Atom';

  @override
  String get subscriptionErrorStorage =>
      'Local storage failed; nothing was saved';

  @override
  String get subscriptionNewGroup => 'New group';

  @override
  String get subscriptionGroupNameLabel => 'Group name';

  @override
  String get subscriptionGroupRename => 'Rename';

  @override
  String get subscriptionGroupDelete => 'Delete group';

  @override
  String get subscriptionGroupPin => 'Pin group';

  @override
  String get subscriptionGroupUnpin => 'Unpin';

  @override
  String get subscriptionPinnedBadge => 'Pinned';

  @override
  String get subscriptionReservedGroupNote =>
      'Reserved group: it cannot be deleted or renamed, but its feeds can be moved';

  @override
  String subscriptionGroupDeleteTitle(String name) {
    return 'Delete group \"$name\"';
  }

  @override
  String subscriptionGroupDeleteBody(int count) {
    return 'This group holds $count feeds. Choose what happens to them:';
  }

  @override
  String get subscriptionGroupDeleteMoveOption => 'Move to Uncategorized';

  @override
  String get subscriptionGroupDeleteMoveHint =>
      'Feeds and articles are kept; only the group changes';

  @override
  String get subscriptionGroupDeleteFeedsOption => 'Delete the feeds';

  @override
  String get subscriptionGroupDeleteFeedsHint =>
      'Keeping favourites takes effect in T018; for now this is recorded only and nothing is deleted';

  @override
  String subscriptionGroupDeleteFeedsPending(int count) {
    return 'Recorded $count feeds as pending; the keep-favourites rule lands in T018 and nothing was deleted here';
  }

  @override
  String subscriptionGroupDeleted(String name, int count) {
    return 'Deleted group \"$name\"; $count feeds moved to Uncategorized';
  }

  @override
  String get subscriptionFeedMenu => 'Feed actions';

  @override
  String get subscriptionGroupMenu => 'Group actions';

  @override
  String get subscriptionFeedRename => 'Rename feed';

  @override
  String get subscriptionFeedEdit => 'Edit feed';

  @override
  String get subscriptionFeedMove => 'Move to group';

  @override
  String get subscriptionFeedEnable => 'Enable automatic refresh';

  @override
  String get subscriptionFeedDisable => 'Pause automatic refresh';

  @override
  String get subscriptionFeedDisabledBadge => 'Paused';

  @override
  String get subscriptionFeedFavorite => 'Mark as featured';

  @override
  String get subscriptionFeedUnfavorite => 'Remove featured mark';

  @override
  String subscriptionUnreadCount(int count) {
    return '$count unread';
  }

  @override
  String get subscriptionEmptyTitle => 'No subscriptions yet';

  @override
  String get subscriptionEmptyBody =>
      'Use Add feed to enter an RSS/Atom address; OPML import and export ship in T015.';

  @override
  String get subscriptionRefreshPolicyTitle => 'Refresh policy';

  @override
  String get subscriptionRefreshPolicyNote =>
      'These are saved settings only; background scheduling lands in T016, so nothing goes online from this page yet.';

  @override
  String get subscriptionGlobalRefreshLabel => 'Global automatic refresh';

  @override
  String get subscriptionGlobalIntervalLabel => 'Refresh interval';

  @override
  String get subscriptionStartupRefreshLabel => 'Refresh on launch';

  @override
  String get subscriptionIntervalInherit => 'Use global';

  @override
  String get subscriptionIntervalManual => 'Manual';

  @override
  String subscriptionIntervalMinutes(String minutes) {
    return '$minutes minutes';
  }

  @override
  String get subscriptionFeedIntervalLabel => 'Interval for this feed';

  @override
  String subscriptionMoveToGroupTitle(String name) {
    return 'Move \"$name\" to a group';
  }

  @override
  String get subscriptionReorderHint =>
      'Drag the handle to reorder; with the handle focused the arrow keys work too';

  @override
  String subscriptionCollapsedCount(int count) {
    return '$count feeds (collapsed)';
  }

  @override
  String subscriptionGroupHeaderLabel(String name, int count) {
    return '$name, $count feeds';
  }

  @override
  String subscriptionFeedRowLabel(String name, int count) {
    return '$name, $count unread';
  }

  @override
  String get subscriptionEnabledNote =>
      'Paused: automatic refresh skips this feed (SET-022)';

  @override
  String get subscriptionFavoriteNote =>
      'Featured only affects display and never changes news selection (SET-023)';

  @override
  String get subscriptionDragHandleLabel =>
      'Drag or press the arrow keys to reorder';

  @override
  String get subscriptionMoveUp => 'Move up';

  @override
  String get subscriptionMoveDown => 'Move down';

  @override
  String get subscriptionFeedRenameTitle => 'Rename feed';

  @override
  String get subscriptionGroupRenameTitle => 'Rename group';

  @override
  String get subscriptionNewGroupTitle => 'New group';

  @override
  String get subscriptionInvalidGroupName => 'Group name cannot be empty';

  @override
  String get subscriptionInvalidFeedName => 'Feed name cannot be empty';

  @override
  String get subscriptionUngrouped => 'No group';

  @override
  String get subscriptionReservedGroupName => 'Uncategorized';

  @override
  String get opmlPageTitle => 'Import and export OPML';

  @override
  String get opmlPageNotice =>
      'Import and export exchange standard feed addresses, names and groups only; no Flux internal IDs, featured flags or reading state.';

  @override
  String get opmlPickFile => 'Choose an OPML file';

  @override
  String get opmlRepick => 'Choose another file';

  @override
  String opmlFileName(String name) {
    return 'File: $name';
  }

  @override
  String get opmlPreviewTitle => 'Import preview';

  @override
  String opmlPreviewSummary(int total, int added, int duplicate, int invalid) {
    return '$total entries: $added new, $duplicate duplicates, $invalid invalid';
  }

  @override
  String get opmlStrategyLabel => 'Group handling';

  @override
  String get opmlStrategyUncategorized => 'Put everything in Uncategorized';

  @override
  String get opmlStrategyKeepGroups => 'Keep the file groups';

  @override
  String get opmlStrategyHint =>
      'The default puts everything in Uncategorized; keeping file groups creates groups from the nesting in the file.';

  @override
  String get opmlStatusAdded => 'New';

  @override
  String get opmlStatusDuplicate => 'Duplicate';

  @override
  String get opmlStatusInvalid => 'Invalid';

  @override
  String get opmlStatusImported => 'Imported';

  @override
  String get opmlStatusFailed => 'Failed';

  @override
  String get opmlDuplicatesNote =>
      'Duplicates already exist; importing keeps their group, featured flag and refresh settings (no state is reset).';

  @override
  String get opmlInvalidNote =>
      'Invalid entries cannot be imported: the address is missing or is not a usable http/https address.';

  @override
  String get opmlNothingToImport =>
      'This file has no feeds that can be imported.';

  @override
  String get opmlStartImport => 'Start import';

  @override
  String get opmlImporting => 'Importing...';

  @override
  String get opmlResultTitle => 'Import result';

  @override
  String opmlResultSummary(
    int imported,
    int duplicate,
    int failed,
    int invalid,
    int articles,
  ) {
    return '$imported imported, $duplicate duplicates, $failed failed, $invalid invalid; $articles articles imported';
  }

  @override
  String opmlRetryFailed(int count) {
    return 'Retry failed entries ($count)';
  }

  @override
  String get opmlRetryHint =>
      'Only failed entries are re-run; successful ones are not requested again and no duplicate subscriptions are created.';

  @override
  String get opmlRetryNone => 'No failed entries to retry';

  @override
  String get opmlExportTitle => 'Export OPML';

  @override
  String get opmlExportBody =>
      'Export every subscription as a standard OPML file that other readers can import.';

  @override
  String get opmlExportAction => 'Export as OPML';

  @override
  String opmlExportDone(int count, String path) {
    return 'Exported $count subscriptions to $path';
  }

  @override
  String get opmlExportEmpty =>
      'There are no subscriptions, so the exported file has an empty body.';

  @override
  String get opmlExportSecretNote =>
      'Export removes explicit secret parameters from addresses (token, api_key, password and similar) plus any account credentials; those subscriptions need their credentials re-entered on the target device.';

  @override
  String opmlExportSecretRemoved(int count, String names) {
    return 'Removed secret parameters from $count address(es) ($names); those subscriptions need credentials re-entered on other devices.';
  }

  @override
  String opmlExportError(String reason) {
    return 'Export failed: $reason';
  }

  @override
  String opmlImportError(String reason) {
    return 'Import failed: $reason';
  }

  @override
  String get opmlCancel => 'Cancel';

  @override
  String opmlEntryIndex(int index) {
    return 'Entry $index';
  }

  @override
  String opmlEntryGroup(String path) {
    return 'Group: $path';
  }

  @override
  String get opmlMenuEntry => 'Import / export OPML';

  @override
  String get readingRefresh => 'Refresh';

  @override
  String get readingRefreshing => 'Refreshing…';

  @override
  String readingRefreshDone(int inserted, int checked) {
    return 'Refresh complete: $inserted new articles ($checked feeds checked)';
  }

  @override
  String readingRefreshNotModified(int checked) {
    return 'Refresh complete: no updates ($checked feeds checked)';
  }

  @override
  String readingRefreshPartial(int inserted, int failed) {
    return 'Refresh complete: $inserted new articles, $failed feeds failed (existing content kept)';
  }

  @override
  String get readingRefreshOffline =>
      'No network connection, so nothing was fetched; Flux will retry when you are back online';

  @override
  String get readingRefreshMetered =>
      'You are on a metered network and metered downloads are disabled in settings, so nothing was fetched';

  @override
  String readingRefreshFailed(String reason) {
    return 'Refresh failed: $reason';
  }

  @override
  String get readingFilterAll => 'All';

  @override
  String get readingFilterUnread => 'Unread';

  @override
  String get readingFilterLater => 'Read later';

  @override
  String get readingFilterFavorite => 'Favorites';

  @override
  String get readingFeedFilterAll => 'All feeds';

  @override
  String get readingEmptyTitle => 'No articles yet';

  @override
  String get readingEmptyBody =>
      'Add a subscription under Mine → Subscriptions, or tap Refresh at the top.';

  @override
  String get readingEmptyFilteredTitle => 'No articles match this filter';

  @override
  String get readingEmptyFilteredBody =>
      'Try another filter, or come back when new articles arrive.';

  @override
  String readingPageIndicator(int page, int pages, int total) {
    return 'Page $page of $pages ($total articles)';
  }

  @override
  String get readingPreviousPage => 'Previous page';

  @override
  String get readingNextPage => 'Next page';

  @override
  String readingLoadedCount(int loaded, int total) {
    return '$loaded of $total loaded';
  }

  @override
  String get readingLoadMore => 'Load more';

  @override
  String get readingPublishedUnknown => 'Date unknown (sorted by fetch time)';

  @override
  String get readingBatchEnter => 'Select';

  @override
  String get readingBatchExit => 'Exit selection';

  @override
  String get readingBatchSelectPage => 'Select this page';

  @override
  String readingBatchSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get readingBatchScopeLabel => 'Apply to';

  @override
  String get readingBatchScopeAll => 'All articles';

  @override
  String get readingBatchScopeFiltered => 'Current filter results';

  @override
  String readingBatchScopeSelected(int count) {
    return '$count selected';
  }

  @override
  String get readingBatchMarkRead => 'Mark as read';

  @override
  String get readingBatchMarkUnread => 'Mark as unread';

  @override
  String get readingBatchMarkLater => 'Mark as read later';

  @override
  String get readingBatchFavorite => 'Add to favorites';

  @override
  String get readingBatchUnfavorite => 'Remove from favorites';

  @override
  String get readingBatchEmptyScope => 'No articles in this scope';

  @override
  String readingBatchDone(int count) {
    return 'Updated $count articles';
  }

  @override
  String get readingItemMenu => 'Article actions';

  @override
  String get readingOpenArticle => 'Open article';

  @override
  String get readingDetailPlaceholderNotice =>
      'The full reader (typography, code, math, outline, prev/next) ships in T019; this is a minimal placeholder showing the title and plain-text body.';

  @override
  String get readingDetailNoBody =>
      'This article has no body to show (the feed only provided a summary).';

  @override
  String readingActionError(String reason) {
    return 'Action failed: $reason';
  }

  @override
  String readingLoadFailed(String reason) {
    return 'Could not load the article list: $reason';
  }

  @override
  String readingUndoMessage(int count, String action) {
    return 'Updated $count articles ($action)';
  }

  @override
  String get readingUndoAction => 'Undo';

  @override
  String readingUndoDone(int count) {
    return 'Undid the last action on $count articles';
  }

  @override
  String readingUndoFailed(String reason) {
    return 'Undo failed: $reason';
  }

  @override
  String get readingActionMarkRead => 'mark as read';

  @override
  String get readingActionMarkUnread => 'mark as unread';

  @override
  String get readingActionMarkLater => 'mark as read later';

  @override
  String get readingActionFavorite => 'add to favorites';

  @override
  String get readingActionUnfavorite => 'remove from favorites';

  @override
  String get deleteFeedMenuEntry => 'Delete feed…';

  @override
  String deleteFeedDialogTitle(String name) {
    return 'Delete feed \"$name\"';
  }

  @override
  String deleteFeedDialogIntro(int total) {
    return 'This feed has $total articles:';
  }

  @override
  String deleteFeedDialogFavoriteLine(int count) {
    return '$count in favorites';
  }

  @override
  String get deleteFeedDialogFavoriteHint =>
      'If you keep favorites, these articles leave the feed and stay in your library';

  @override
  String deleteFeedDialogOtherLine(int count, int later) {
    return '$count others (including $later marked read later)';
  }

  @override
  String get deleteFeedDialogOtherHint =>
      'These are cleared whether or not you keep favorites (read later is no exception)';

  @override
  String get deleteFeedDialogNoArticles =>
      'This feed has no articles yet, so nothing will be cleared.';

  @override
  String get deleteFeedKeepFavoritesOption => 'Keep favorite articles';

  @override
  String get deleteFeedKeepFavoritesHint =>
      'Favorites leave the feed with a source snapshot; the remaining articles are cleared';

  @override
  String get deleteFeedConfirm => 'Delete';

  @override
  String deleteFeedDone(String name, int deleted, int kept) {
    return 'Deleted feed \"$name\": cleared $deleted, kept $kept favorites';
  }

  @override
  String deleteFeedDoneNoArticles(String name) {
    return 'Deleted feed \"$name\"';
  }

  @override
  String deleteFeedPreviewFailed(String name, String reason) {
    return 'Could not read what deleting \"$name\" would affect: $reason';
  }

  @override
  String deleteGroupDialogImpact(
    int feeds,
    int articles,
    int favorites,
    int later,
  ) {
    return 'This group has $feeds feeds and $articles articles ($favorites in favorites, $later marked read later).';
  }

  @override
  String get deleteGroupDialogNoFeeds => 'This group has no feeds yet.';

  @override
  String get deleteGroupKeepFavoritesOption =>
      'Keep favorite articles in these feeds';

  @override
  String deleteGroupDoneDeleted(String name, int feeds, int deleted, int kept) {
    return 'Deleted group \"$name\" and its $feeds feeds: cleared $deleted, kept $kept favorites';
  }

  @override
  String get detachedFeedLabel => 'feed removed';

  @override
  String get readingCompletenessSourceBody => 'Feed body';

  @override
  String get readingCompletenessSummaryOnly => 'Summary only';

  @override
  String get readingCompletenessExtracted => 'Extracted locally';

  @override
  String get readingCompletenessUnknown => 'Completeness unknown';

  @override
  String get readingCompletenessSummaryOnlyNotice =>
      'The feed only provided a summary; this is not the full article.';

  @override
  String get readingTocTitle => 'Contents';

  @override
  String get readingTocEmpty => 'This article has no section headings';

  @override
  String get readingPrevArticle => 'Previous';

  @override
  String get readingNextArticle => 'Next';

  @override
  String get readingNoPrev =>
      'This is the first article in the filtered results';

  @override
  String get readingNoNext =>
      'This is the last article in the filtered results';

  @override
  String get readingNeighborOrderNote =>
      'Previous/next follow the filter and sort snapshot taken when you opened this article';

  @override
  String get readingFindOpen => 'Find in article';

  @override
  String get readingFindHint => 'Find in this article';

  @override
  String get readingFindClose => 'Close find';

  @override
  String get readingFindNoMatch => 'No matches';

  @override
  String readingFindMatchCount(int index, int total) {
    return 'Match $index of $total';
  }

  @override
  String get readingFindNext => 'Next match';

  @override
  String get readingFindPrevious => 'Previous match';

  @override
  String get readingCodeCopy => 'Copy code';

  @override
  String get readingCodeCopied => 'Code copied';

  @override
  String get readingCodePlainText => 'plain text';

  @override
  String get readingCodeCollapse => 'Collapse';

  @override
  String readingCodeExpand(int lines) {
    return 'Expand ($lines lines)';
  }

  @override
  String get readingMathUnsupported =>
      'This formula could not be rendered; the source is shown instead';

  @override
  String readingMathUnsupportedReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get readingImagePlaceholder => 'Image placeholder';

  @override
  String get readingImageNotice =>
      'Remote image loading and caching ship in T021; only a placeholder box is shown for now.';

  @override
  String readingLinkBlocked(String reason) {
    return 'Blocked: $reason';
  }

  @override
  String get readingLinkCopy => 'Copy link';

  @override
  String get readingLinkCopied => 'Link copied';

  @override
  String get readingLinkOpenHint =>
      'Opening links in the browser ships in T020; you can copy the address now.';

  @override
  String get readingRichBodyUnavailable =>
      'This body can only be shown as plain text (no renderable controlled document structure).';

  @override
  String readingRichBodyBlockReason(String reason) {
    return 'Could not parse this block; showing the source text: $reason';
  }

  @override
  String readingByAuthor(String author, String feed) {
    return '$author · $feed';
  }

  @override
  String readingFindScopeNote(String query) {
    return 'Matches for \"$query\" are highlighted; the outline and previous/next still work.';
  }

  @override
  String get readingBackToList => 'Back to list';
}
