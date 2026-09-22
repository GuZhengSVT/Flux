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
  String placeholderPageBody(String tasks) {
    return 'This page is an app-shell placeholder with no data or interaction. Planned tasks: $tasks.';
  }

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
      'Remote images load on demand and are cached on this device (SET-080 limit); tap to open the viewer.';

  @override
  String get readingImageRetry => 'Reload this image';

  @override
  String get readingImageBlockedPrivate =>
      'Blocked: this image address points at your device or private network.';

  @override
  String get readingImageTooLarge =>
      'This image exceeds the per-image size limit and was not downloaded.';

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
  String get readingCopyAll => 'Copy article text';

  @override
  String readingCopyAllDone(int characters) {
    return 'Article text copied ($characters characters)';
  }

  @override
  String get readingCopyAllEmpty => 'This article has no body text to copy.';

  @override
  String get readingSelectionExplain => 'Explain';

  @override
  String get readingSelectionExplainNoAiTitle => 'No AI service configured yet';

  @override
  String readingSelectionExplainNoAiBody(int limit) {
    return 'Explaining a selection needs an AI service. Only the selected text plus one short paragraph of context on each side (at most $limit characters) is sent.';
  }

  @override
  String get readingSelectionExplainGoSettings => 'Open settings';

  @override
  String get readingSelectionExplainPending =>
      'Explaining a selection needs an AI service; the call itself is T034. This round only adds the entry point and notice, and sends no request.';

  @override
  String get readingImageAnalyzeAction => 'Analyze this image';

  @override
  String get visionConsentTitle => 'First time sending images to this service';

  @override
  String visionConsentBody(String endpoint) {
    return 'This image will be sent to $endpoint for analysis. It leaves your device and cannot be recalled; the result is generated by that model and may be wrong. The acknowledgement is stored on this device only, and you will be asked again if the endpoint changes.';
  }

  @override
  String get visionConsentConfirm => 'Agree and analyze';

  @override
  String get visionConsentCancel => 'Cancel';

  @override
  String get visionAnalysisTitle => 'Image analysis';

  @override
  String get visionAnalysisRunning => 'Analyzing this image…';

  @override
  String get visionAnalysisDownsampled =>
      '(This image exceeds the single-image upload limit and was downsampled before sending: detail may be lost.)';

  @override
  String visionAnalysisSentTo(String endpoint) {
    return 'Sent to $endpoint';
  }

  @override
  String get visionAnalysisNoModel =>
      'No model on this device declares vision capability, so image analysis was skipped; the article and text tasks are unaffected. You can enable vision for a model in settings.';

  @override
  String get visionAnalysisDisabled =>
      'Image analysis is currently off and the setting could not be written back; enable it in settings and try again.';

  @override
  String get visionAnalysisImageUnavailable =>
      'This image could not be loaded or failed validation, so it was not sent for analysis.';

  @override
  String visionAnalysisFailed(String reason) {
    return 'Image analysis failed: $reason';
  }

  @override
  String get visionAnalysisClose => 'Close';

  @override
  String get visionAnalysisCancelAction => 'Cancel analysis';

  @override
  String get visionAnalysisCancelled =>
      'Image analysis cancelled; the article is unchanged.';

  @override
  String get aiVisionSettingHint =>
      'The image-analysis switch, per-image limit and dedicated vision model live in settings; without a vision model, image analysis is skipped and text tasks continue.';

  @override
  String get readingSummaryAction => 'Summary';

  @override
  String get readingSummaryTitle => 'AI summary';

  @override
  String get readingSummaryRunning => 'Generating summary…';

  @override
  String get readingSummaryCancelAction => 'Cancel summary';

  @override
  String get readingSummaryCancelled =>
      'Summary generation cancelled; the article is unchanged.';

  @override
  String readingAiSummaryLabel(String model, String date) {
    return 'AI summary · $model · $date';
  }

  @override
  String get readingSummaryTruncatedNotice =>
      'The article exceeds the single-article budget (SET-061, 8000 characters), so the summary only uses the first part.';

  @override
  String get readingSummarySourceKept =>
      'The source summary is still kept and was not overwritten by the AI summary.';

  @override
  String get readingSummaryNoBody =>
      'This article has no body to summarize (the source only provided a summary); the source summary is kept.';

  @override
  String get readingSummaryNoModelBody =>
      'Summaries need an AI service. Configure at least one enabled model first; without one the list falls back to an excerpt of the body.';

  @override
  String readingSummaryFailed(String reason) {
    return 'Summary failed: $reason';
  }

  @override
  String get readingSummaryAutoToggleLabel =>
      'Auto AI summary for missing summaries';

  @override
  String get readingSummaryAutoToggleHint =>
      'Off by default. When on, missing summaries are filled only during a list refresh; each summary is billed separately and is capped by the daily limit (SET-064, default 50). When off, the list uses an excerpt of the body as a fallback.';

  @override
  String get readingSummaryAutoToggleDone =>
      'Auto summary enabled; missing summaries will be filled on the next refresh.';

  @override
  String readingSummaryAutoBatchReport(
    int succeeded,
    int failed,
    int cached,
    int limit,
  ) {
    return 'Auto summary: $succeeded succeeded, $failed failed, $cached from cache (daily limit $limit).';
  }

  @override
  String readingSummaryAutoQuotaReached(int limit) {
    return 'Today\'s auto-summary quota is used up ($limit); manual summaries are not affected.';
  }

  @override
  String readingSelectionExplainTitle(String selection) {
    return 'Explain \"$selection\"';
  }

  @override
  String get readingSelectionExplainRunning => 'Explaining…';

  @override
  String readingSelectionExplainSent(int characters) {
    return 'Sent the selection plus surrounding context, $characters characters in total; the article was not modified.';
  }

  @override
  String readingSelectionExplainSentTruncated(int characters) {
    return 'Sent the selection plus surrounding context, $characters characters in total (context was truncated); the article was not modified.';
  }

  @override
  String get readingSelectionExplainFailedUnknown =>
      'Explanation failed, please try again later; the article was not modified.';

  @override
  String get readingSelectionCopy => 'Copy';

  @override
  String get readingLinkPanelTitle => 'External link';

  @override
  String get readingLinkCopyAction => 'Copy address';

  @override
  String get readingLinkOpenAction => 'Open in browser';

  @override
  String readingLinkOpenFailed(String reason) {
    return 'Could not open this address: $reason';
  }

  @override
  String get readingImageViewerTitle => 'Image';

  @override
  String get readingImageCloseAction => 'Close (Esc)';

  @override
  String get readingImageSaveAction => 'Save image';

  @override
  String get readingImageShareAction => 'Share';

  @override
  String readingImageSavedTo(String path) {
    return 'Image saved to $path';
  }

  @override
  String readingImageSaveFailed(String reason) {
    return 'Save failed: $reason';
  }

  @override
  String get readingImageLoadFailed => 'Image failed to load.';

  @override
  String get readingImageTapToDownload => 'Tap to download this image';

  @override
  String get readingImageAutoLoadOff =>
      'Loading remote images automatically is off (SET-012); tap an image to download that one.';

  @override
  String get readingShareUnavailable =>
      'System share is unavailable; copied instead.';

  @override
  String get readingShareDone => 'System share opened.';

  @override
  String get readingShareFailed =>
      'Share did not complete; copied to the clipboard instead.';

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

  @override
  String get searchFieldHint => 'Search all articles';

  @override
  String get searchFieldLabel => 'Search';

  @override
  String get searchClear => 'Clear search';

  @override
  String get searchClose => 'Close search';

  @override
  String get searchOpen => 'Search articles';

  @override
  String get searchIdleTitle => 'Type a keyword to search';

  @override
  String get searchIdleBody =>
      'Search covers titles, authors, sources, summaries and stored bodies. Chinese and English both match as case-insensitive substrings.';

  @override
  String get searchEmptyTitle => 'No matching articles';

  @override
  String get searchEmptyBody =>
      'Try a shorter keyword. Search only looks at articles already stored on this device and never visits web pages.';

  @override
  String searchFailed(String reason) {
    return 'Search failed: $reason';
  }

  @override
  String get searchRetry => 'Retry';

  @override
  String searchResultsCount(int count) {
    return '$count matches';
  }

  @override
  String get searchScopeAll => 'All articles';

  @override
  String get searchScopeFiltered => 'Current filter';

  @override
  String get searchScopeLabel => 'Scope';

  @override
  String get statsPageTitle => 'Reading stats';

  @override
  String get statsHeatmapTitle => 'Year heatmap';

  @override
  String get statsHeatmapLegendLess => 'Less';

  @override
  String get statsHeatmapLegendMore => 'More';

  @override
  String statsHeatmapCellTooltip(Object date, Object minutes) {
    return '$date: $minutes min';
  }

  @override
  String get statsHeatmapEmpty => 'No reading recorded for this year yet.';

  @override
  String get statsWeeklyTitle => 'Last 7 days';

  @override
  String get statsWeeklyEmpty => 'No reading recorded in the last 7 days.';

  @override
  String get statsYearLabel => 'Year';

  @override
  String statsYearTotal(Object minutes) {
    return '$minutes min total this year';
  }

  @override
  String statsActiveDays(Object days) {
    return '$days days with activity';
  }

  @override
  String get statsWeekdayMon => 'Mon';

  @override
  String get statsWeekdayTue => 'Tue';

  @override
  String get statsWeekdayWed => 'Wed';

  @override
  String get statsWeekdayThu => 'Thu';

  @override
  String get statsWeekdayFri => 'Fri';

  @override
  String get statsWeekdaySat => 'Sat';

  @override
  String get statsWeekdaySun => 'Sun';

  @override
  String get statsTodayLabel => 'Today';

  @override
  String statsDateLabel(Object day, Object month) {
    return '$month/$day';
  }

  @override
  String get statsClearAction => 'Clear stats';

  @override
  String get statsClearConfirmTitle => 'Clear reading stats?';

  @override
  String get statsClearConfirmBody =>
      'This deletes every reading session and duration stored on this device; the year heatmap and history will be emptied. Articles, reading state and favorites are not affected. This cannot be undone.';

  @override
  String get statsClearConfirmYes => 'Clear';

  @override
  String get statsClearCancel => 'Cancel';

  @override
  String statsClearDone(Object count) {
    return 'Cleared $count reading sessions.';
  }

  @override
  String statsClearFailed(Object reason) {
    return 'Clear failed: $reason';
  }

  @override
  String get statsRecordToggleLabel => 'Record reading time';

  @override
  String get statsRecordToggleHint =>
      'Turning this off stops recording new reading time; existing history is kept and can be cleared at any time.';

  @override
  String statsIdlePauseLabel(Object minutes) {
    return 'Pause after $minutes min idle';
  }

  @override
  String get statsDisabledNotice =>
      'Reading stats are off (SET-015); this page shows the history already recorded.';

  @override
  String statsLoadFailed(Object reason) {
    return 'Could not load stats: $reason';
  }

  @override
  String get statsRetry => 'Retry';

  @override
  String get statsEstimateNote =>
      'Stats are a local estimate: time only counts while visible and active, and is never summed across devices.';

  @override
  String get settingsStatsEntryTitle => 'Reading stats';

  @override
  String get settingsStatsEntrySubtitle =>
      'Year heatmap and last-7-day reading time';

  @override
  String get readingFetchFullTextAction => 'Fetch full text from source';

  @override
  String get readingFetchFullTextLoading => 'Fetching the source page…';

  @override
  String readingFetchFullTextDone(Object chars) {
    return 'Extracted source text ($chars chars)';
  }

  @override
  String readingFetchFullTextFailed(Object reason) {
    return 'Could not fetch the source text: $reason';
  }

  @override
  String get readingFetchFullTextViewOriginal => 'View original';

  @override
  String get readingFetchFullTextViewExtracted => 'View extracted';

  @override
  String get readingFetchFullTextPaywall =>
      'The source may require payment or sign-in, so full text may be unavailable.';

  @override
  String get readingFetchFullTextShort =>
      'The extracted text is very short; the source may need script rendering.';

  @override
  String get readingFetchFullTextOpenExternal => 'Open in browser';

  @override
  String get readingFetchFullTextNoUrl =>
      'This article has no reachable source address.';

  @override
  String get readingFetchFullTextNoScript =>
      'HTTP fetch and static parsing only: no scripts are run and no paywall or sign-in is bypassed.';

  @override
  String get readingFetchFullTextButtonHint =>
      'Fetches the source only when you click, never automatically or in the background.';

  @override
  String get settingsAiEntryTitle => 'AI services';

  @override
  String get settingsAiEntrySubtitle =>
      'Providers, models, capabilities and credentials (SET-030-033)';

  @override
  String get aiPageTitle => 'AI services';

  @override
  String get aiModelsSection => 'Models and providers';

  @override
  String get aiEmptyNotice =>
      'No model is configured yet. Add a provider and a model ID before AI features can be used.';

  @override
  String get aiAddModel => 'Add model';

  @override
  String get aiEditModel => 'Edit';

  @override
  String get aiDeleteModel => 'Delete';

  @override
  String get aiProtocolLabel => 'Protocol';

  @override
  String get aiProtocolHint =>
      'The protocol decides the request and event-stream shapes; different paths on the same host are not interchangeable.';

  @override
  String get aiProtocolPendingSuffix => ' (adapter pending)';

  @override
  String get aiPresetLabel => 'Provider preset';

  @override
  String get aiPresetCustom => 'Custom (no preset)';

  @override
  String get aiPresetHint =>
      'A preset fills in only the protocol and Base URL, never a key; the key is always typed by hand and stored only in secure storage.';

  @override
  String get aiPresetEndpointLabel => 'Will request';

  @override
  String get aiPresetStatusLive => 'live-tested';

  @override
  String get aiPresetStatusFixture => 'fixture passed';

  @override
  String get aiPresetStatusUnverified => 'unverified';

  @override
  String get aiPresetStatusLiveHint =>
      'A real call to this endpoint was made from this machine and succeeded (see the round record).';

  @override
  String get aiPresetStatusFixtureHint =>
      'The protocol adapter has full fixture-level evidence, but no real call was made to this endpoint this round.';

  @override
  String get aiPresetStatusUnverifiedHint =>
      'No real call has been made to this endpoint (usually because there is no credential); do not treat it as verified.';

  @override
  String get aiPresetMatrixTitle => 'Preset verification status';

  @override
  String get aiPresetMatrixHint =>
      'Only live-tested scope is claimed as supported; fixture-passed does not mean really usable.';

  @override
  String get aiPresetNoLiveNotice =>
      'No preset has been live-tested on this machine yet.';

  @override
  String get aiAliasLabel => 'Provider alias';

  @override
  String get aiAliasHint =>
      'Unique on this device; identifies this credential and labels the model list and failover order.';

  @override
  String get aiBaseUrlLabel => 'Base URL';

  @override
  String get aiBaseUrlHint =>
      'Host or shared prefix only, for example https://api.deepseek.com; the adapter appends the protocol path.';

  @override
  String get aiModelIdLabel => 'Model ID';

  @override
  String get aiModelIdHint =>
      'You can type it by hand when no list endpoint exists; it must match the provider\'s model name exactly.';

  @override
  String get aiApiKeyLabel => 'API key (SET-031)';

  @override
  String aiApiKeyConfigured(String preview) {
    return 'Configured: $preview';
  }

  @override
  String get aiApiKeyNotConfigured => 'Not configured';

  @override
  String get aiApiKeyHint =>
      'Written only to the system secure store (Keychain): never the database, logs, sync or backups.';

  @override
  String get aiApiKeyReplace => 'Replace key';

  @override
  String get aiApiKeyClear => 'Delete key';

  @override
  String get aiApiKeyUnavailable =>
      'Secure storage is unavailable on this device; a key entered now will not be saved.';

  @override
  String get aiCapabilitySection => 'Capabilities (SET-033)';

  @override
  String get aiCapabilityHint =>
      'You declare capabilities; they are never inferred from the model name. A model without vision will not receive images.';

  @override
  String get aiCapabilityText => 'Text';

  @override
  String get aiCapabilityVision => 'Vision';

  @override
  String get aiCapabilityStreaming => 'Streaming';

  @override
  String get aiCapabilityTools => 'Tool calling';

  @override
  String get aiCapabilityStructured => 'Structured output';

  @override
  String get aiContextWindowLabel => 'Context limit (tokens)';

  @override
  String get aiOutputBudgetLabel => 'Output limit (tokens)';

  @override
  String aiBudgetConservativeHint(int context, int output) {
    return 'Empty means undeclared: the conservative budget is used (context $context, output $output). This is not a real capability expansion.';
  }

  @override
  String get aiEnabledLabel => 'Enabled';

  @override
  String get aiDefaultForTasksLabel => 'Set as default model for tasks';

  @override
  String get aiDefaultForTasksBadge => 'Default';

  @override
  String get aiMoveUp => 'Move up (failover order)';

  @override
  String get aiMoveDown => 'Move down (failover order)';

  @override
  String get aiSortHint =>
      'Order decides the failover sequence (SET-032/035); disabled models do not take part.';

  @override
  String get aiSaveAction => 'Save';

  @override
  String get aiCancelAction => 'Cancel';

  @override
  String aiFormInvalid(String detail) {
    return 'Please check: $detail';
  }

  @override
  String get aiTestButton => 'Test connection and minimal generation';

  @override
  String get aiTestCostTitle => 'This test costs money';

  @override
  String aiTestCostBody(String provider, int tokens) {
    return 'The test sends one real generation request to $provider (output limit $tokens tokens). It may be billed, and a protocol without idempotency keys cannot guarantee exactly-once billing. Continue?';
  }

  @override
  String get aiTestCostConfirm => 'Confirm and test';

  @override
  String get aiTestRunning => 'Testing…';

  @override
  String aiTestSuccess(int elapsedMs, int chars) {
    return 'Test passed: $elapsedMs ms, $chars characters returned';
  }

  @override
  String aiTestSuccessWithUsage(
    int elapsedMs,
    int inputTokens,
    int outputTokens,
    int chars,
  ) {
    return 'Test passed: $elapsedMs ms, $inputTokens input / $outputTokens output tokens, $chars characters returned';
  }

  @override
  String aiTestFailed(String reason) {
    return 'Test failed: $reason';
  }

  @override
  String get aiFailureAuth =>
      'Authentication failed: the key may be wrong, or the account is out of credit.';

  @override
  String get aiFailureRateLimited =>
      'The provider is rate limiting; try again later.';

  @override
  String get aiFailureContentFiltered =>
      'The provider refused the content. This is not a network problem, and switching providers cannot circumvent it.';

  @override
  String aiFailureNetwork(String reason) {
    return 'Network request failed: $reason';
  }

  @override
  String get aiFailureTimeout => 'The request timed out.';

  @override
  String get aiFailureCancelled => 'Cancelled.';

  @override
  String get aiFailureAdapterMissing =>
      'No adapter is implemented for this protocol yet, so it cannot be called.';

  @override
  String get aiFailureCredentialMissing => 'No API key is configured.';

  @override
  String get aiFailureDisabled => 'This model is currently disabled.';

  @override
  String aiFailureValidation(String reason) {
    return 'Invalid configuration: $reason';
  }

  @override
  String get aiFailureStorage =>
      'Writing to local storage failed; this change was not saved.';

  @override
  String aiFailureUnknown(String reason) {
    return 'Call failed: $reason';
  }

  @override
  String aiDeleteConfirmTitle(String alias) {
    return 'Delete model “$alias”?';
  }

  @override
  String get aiDeleteConfirmBody =>
      'This model record will no longer be usable. Its API key is not deleted.';

  @override
  String aiDeleteInUseBody(String references) {
    return 'This model is still referenced by: $references. After deletion those settings point at a model that no longer exists, and you must fix them by hand.';
  }

  @override
  String get aiReferenceDefaultForTasks => 'Default model for tasks';

  @override
  String get aiReferenceVisionModel => 'SET-034 vision model';

  @override
  String get aiReferenceFailover => 'SET-035 failover allow list';

  @override
  String get aiDeleteConfirmYes => 'Delete anyway';

  @override
  String get aiDeleteCancel => 'Cancel';

  @override
  String aiDeleteFailed(String reason) {
    return 'Delete failed: $reason';
  }

  @override
  String get aiSavedNotice => 'Saved.';

  @override
  String aiLoadFailed(String reason) {
    return 'Could not load the model list: $reason';
  }

  @override
  String get aiPlannedNotice =>
      'The automatic-summary switch (SET-037) belongs to T034; this page only configures providers and models. The five-no-response failover rule, total timeout and token budget are implemented by T029 (see Settings → AI tasks).';

  @override
  String get aiTaskListTitle => 'AI tasks';

  @override
  String get settingsAiTasksEntryTitle => 'AI tasks';

  @override
  String get settingsAiTasksEntrySubtitle =>
      'Review past tasks and interruptions; restart them by hand';

  @override
  String get aiTaskListEmpty => 'No AI tasks yet.';

  @override
  String aiTaskListLoadFailed(String reason) {
    return 'Could not load AI tasks: $reason';
  }

  @override
  String get aiTaskRestart => 'Restart';

  @override
  String get aiTaskRestartBlocked =>
      'This task is still running; it cannot be started again';

  @override
  String get aiTaskRestartSuccess =>
      'A new task finished; the original record is unchanged';

  @override
  String get aiTaskFromCache => 'Cache hit (no request sent)';

  @override
  String aiTaskMeta(int tokens, int attempts) {
    return '$tokens tokens total · $attempts attempts';
  }

  @override
  String get aiTaskStatusQueued => 'Queued';

  @override
  String get aiTaskStatusRunning => 'Running';

  @override
  String get aiTaskStatusWaitingConfiguration => 'Waiting for configuration';

  @override
  String get aiTaskStatusWaitingNetwork => 'Waiting for network';

  @override
  String get aiTaskStatusSucceeded => 'Succeeded';

  @override
  String get aiTaskStatusPartial => 'Partially finished';

  @override
  String get aiTaskStatusFailed => 'Failed';

  @override
  String get aiTaskStatusCancelled => 'Cancelled';

  @override
  String get aiTaskStatusInterrupted =>
      'Interrupted (not resent automatically)';

  @override
  String get aiTaskKindSummary => 'Daily summary';

  @override
  String get aiTaskKindExplain => 'Explain selection';

  @override
  String get aiTaskKindTranslate => 'Full translation';

  @override
  String get aiTaskKindNews => 'Today\'s news';

  @override
  String get aiTaskKindOther => 'Other task';

  @override
  String get searchPageTitle => 'Search services';

  @override
  String get settingsSearchEntryTitle => 'Search services';

  @override
  String get settingsSearchEntrySubtitle =>
      'Endpoints and credentials for Tavily / Brave / self-hosted SearXNG';

  @override
  String get searchAddService => 'Add search service';

  @override
  String get searchEditService => 'Edit search service';

  @override
  String get searchServicesSection => 'Configured search services';

  @override
  String get searchSortHint =>
      'The order is the order the tool executor picks services in; a disabled service is skipped.';

  @override
  String get searchEmptyNotice =>
      'No search service is configured yet. Without one, web-search tasks say configuration is missing instead of silently skipping search.';

  @override
  String searchLoadFailed(String reason) {
    return 'Could not load search services: $reason';
  }

  @override
  String get searchDefaultBadge => 'Task default';

  @override
  String get searchDefaultLabel => 'Default for tasks';

  @override
  String searchBudgetHint(int maxResults, int timeoutSeconds) {
    return '$maxResults results per query · ${timeoutSeconds}s timeout (SET-040)';
  }

  @override
  String get searchPrivateApproved =>
      'Private/HTTP endpoint explicitly approved (SET-041)';

  @override
  String get searchCredentialMissingHint =>
      'No credential yet: this protocol always fails without a key, so the test button is disabled.';

  @override
  String get searchTestDisabledNoCredential =>
      'Save a credential first; this protocol cannot be called without a key';

  @override
  String get searchTestButton => 'Test';

  @override
  String get searchTestConfirmTitle => 'Send one real search?';

  @override
  String searchTestConfirmBody(String protocol, String endpoint) {
    return 'This sends the query to the $protocol endpoint $endpoint and may incur cost. The query leaves this device.';
  }

  @override
  String get searchTestConfirmYes => 'Send';

  @override
  String get searchTestConfirmCancel => 'Cancel';

  @override
  String searchTestSuccess(int elapsedMs, int count) {
    return 'Search succeeded: $elapsedMs ms, $count result(s)';
  }

  @override
  String searchDeleteConfirmTitle(String label) {
    return 'Delete search service \"$label\"?';
  }

  @override
  String get searchDeleteConfirmBody =>
      'This search service becomes unavailable. The stored key is not deleted.';

  @override
  String searchDeleteInUseBody(String references) {
    return 'This search service is still referenced by: $references. After deletion those settings point at a service that no longer exists, and you must fix them by hand.';
  }

  @override
  String get searchDeleteConfirmYes => 'Delete anyway';

  @override
  String get searchDeleteCancel => 'Cancel';

  @override
  String searchDeleteFailed(String reason) {
    return 'Delete failed: $reason';
  }

  @override
  String get searchSaveService => 'Save';

  @override
  String get searchLabelField => 'Service name';

  @override
  String get searchProtocolField => 'Protocol';

  @override
  String get searchEndpointField => 'Endpoint';

  @override
  String get searchEndpointRequiredHint =>
      'A self-hosted SearXNG has no default address; enter your own instance URL.';

  @override
  String searchEndpointResolved(String endpoint) {
    return 'Will request: $endpoint';
  }

  @override
  String get searchKeyField => 'API key / instance auth';

  @override
  String get searchKeyConfigured =>
      'Configured (never echoed; leave empty to keep it)';

  @override
  String get searchKeyNotConfigured => 'Not configured';

  @override
  String get searchKeyOptionalHint =>
      'Credential is optional for this protocol: leaving it empty sends no auth header (typical when a reverse proxy authenticates the instance).';

  @override
  String get searchDeleteKey => 'Delete stored credential';

  @override
  String get searchMaxResultsField => 'Results per query (1–20)';

  @override
  String get searchTimeoutField => 'Timeout seconds (5–60)';

  @override
  String get searchAllowPrivateLabel => 'Allow private/HTTP endpoint (SET-041)';

  @override
  String get searchAllowPrivateHint =>
      'Turn this on only for a self-hosted instance on your LAN or over plain HTTP. Without approval the endpoint is rejected by the URL guard and no request is sent.';

  @override
  String get searchPlannedNotice =>
      'The query keyword list (SET-052), forbidden query terms and topic filters (SET-053), and the daily-news search orchestration (T036/T037) come later; this page only manages the search services themselves.';

  @override
  String get readingTranslateAction => 'Translate';

  @override
  String get readingTranslateTitle => 'Full translation';

  @override
  String readingTranslateRunning(int done, int total) {
    return 'Translating paragraph by paragraph… ($done/$total done)';
  }

  @override
  String readingTranslateDone(int done, int total) {
    return 'Translation finished: $done/$total paragraphs done.';
  }

  @override
  String readingTranslatePartial(int done, int total, int failed) {
    return 'Translation finished: $done/$total paragraphs done, $failed failed (you can retry only the failures).';
  }

  @override
  String get readingTranslateCancelAction => 'Cancel translation';

  @override
  String get readingTranslateCancelled =>
      'Translation cancelled. Finished paragraphs are kept; the rest show the original.';

  @override
  String readingTranslateRetryFailed(int count) {
    return 'Retry failed paragraphs ($count)';
  }

  @override
  String get readingTranslateRetryHint =>
      'Only failed paragraphs are re-run; finished translations are kept.';

  @override
  String get readingTranslateSegmentFailed =>
      'This paragraph failed to translate; the original text is still shown.';

  @override
  String get readingTranslateShowOriginal => 'Show original';

  @override
  String get readingTranslateShowTranslation => 'Show translation';

  @override
  String get readingTranslateSourceKept =>
      'The original is always kept; switching only changes what is displayed.';

  @override
  String get readingTranslateTruncatedNotice =>
      'Some paragraphs exceed the single-material budget (SET-061, 8000 characters) and were only translated in part.';

  @override
  String get readingTranslateStale =>
      'The body changed after this translation; the text below corresponds to the previous version.';

  @override
  String get readingTranslateSummaryOnly =>
      'The source only provides a summary (summary only), so there is no full text to translate; a summary is not treated as a body.';

  @override
  String get readingTranslateNoBody =>
      'This article has no body to translate; the source summary is kept.';

  @override
  String get readingTranslateNoModelBody =>
      'Translation needs AI services. Configure at least one enabled model first.';

  @override
  String get readingTranslateNoText =>
      'This body has no translatable paragraphs (for example, it contains only an image).';

  @override
  String readingTranslateFailed(String reason) {
    return 'Translation failed: $reason';
  }

  @override
  String readingTranslateSavedLabel(String model, String date) {
    return 'Translation · $model · $date';
  }

  @override
  String readingTranslateLanguage(String language) {
    return 'Target language: $language';
  }

  @override
  String get readingTranslateInterrupted =>
      'The previous translation did not finish (the process was interrupted). Finished paragraphs are kept; you can retry the failures.';

  @override
  String get newsSettingsEntryTitle => 'News generation';

  @override
  String get newsSettingsEntrySubtitle =>
      'Source selection, required sites, keywords and the overall prompt (SET-050–055); the daily-news pipeline itself comes with T037–T040.';

  @override
  String get newsPageTitle => 'News sources and prompt';

  @override
  String newsLoadingFailed(String reason) {
    return 'Failed to load configuration: $reason; what follows is this run\'s initial value, not your saved configuration.';
  }

  @override
  String get newsGlobalSwitchLabel =>
      'Let RSS subscriptions feed the news selection';

  @override
  String get newsGlobalSwitchHint =>
      'When off, no subscription content is used at all; the per-source switches only affect a single source and are unrelated to starring.';

  @override
  String get newsFeedSectionTitle => 'Per-source switches (SET-050)';

  @override
  String get newsFeedSectionHint =>
      '\"Follow\" defers to the source\'s subscription refresh state; you can exclude a source from the news while keeping its refresh.';

  @override
  String get newsFeedFollow => 'Follow subscription';

  @override
  String get newsFeedInclude => 'Include in news';

  @override
  String get newsFeedExclude => 'Exclude from news';

  @override
  String get newsFeedDisabledHint => ' (subscription refresh is off)';

  @override
  String get newsFeedEmpty =>
      'No subscriptions yet; add one and you can configure it per source here.';

  @override
  String get newsRequiredSectionTitle => 'Required sites (SET-051)';

  @override
  String get newsRequiredSectionHint =>
      'Each site is fetched individually during the task and written into the overall prompt one by one; disabled sites stay out of the prompt.';

  @override
  String get newsRequiredEmpty => 'No required sites configured yet.';

  @override
  String get newsRequiredAdd => 'Add site';

  @override
  String get newsRequiredNameField => 'Site name';

  @override
  String get newsRequiredUrlField => 'Site URL';

  @override
  String get newsRequiredSaved => 'Required sites saved.';

  @override
  String newsRequiredSaveFailed(String reason) {
    return 'Save failed: $reason';
  }

  @override
  String get newsListKeywordsTitle => 'Search keywords (SET-052)';

  @override
  String get newsListKeywordsHint =>
      'With an empty list and no RSS material, the task reports missing input instead of inventing news.';

  @override
  String get newsListBlockedTitle => 'Blocked query terms (SET-053)';

  @override
  String get newsListBlockedHint =>
      'Queries containing these terms are never sent to search services (substring match); this does not affect which topics are excluded.';

  @override
  String get newsListTopicsTitle => 'Excluded topics (SET-053)';

  @override
  String get newsListTopicsHint =>
      'These topics are kept out of the result; this is a separate list from the blocked query terms above.';

  @override
  String get newsListEmpty => 'The list is empty.';

  @override
  String get newsListAddHint => 'Type and press Enter to add';

  @override
  String get newsListSaved => 'List saved.';

  @override
  String newsListSaveFailed(String reason) {
    return 'Save failed: $reason';
  }

  @override
  String get newsPromptModeTitle => 'Overall prompt mode (SET-055)';

  @override
  String get newsPromptModeComposed => 'Composed';

  @override
  String get newsPromptModeAdvanced => 'Advanced override';

  @override
  String get newsPromptModeComposedHint =>
      'Composed from task + sources + spec + fixed protocol; the preview below is exactly what will be sent.';

  @override
  String get newsPromptModeAdvancedHint =>
      'Edit the overall prompt directly. The fixed citation protocol is still appended, and missing required sites are reported.';

  @override
  String get newsPromptTaskField => 'Task instruction';

  @override
  String get newsPromptSpecField => 'Output spec';

  @override
  String get newsPromptAdvancedField => 'Overall prompt (advanced override)';

  @override
  String get newsPromptCitationFixed =>
      'Fixed output protocol (cannot be removed; always appended)';

  @override
  String get newsPromptRestoreDefaults => 'Restore default template';

  @override
  String get newsPromptRestored =>
      'Built-in template restored (not saved yet).';

  @override
  String get newsPromptSaveVersion => 'Save as new version';

  @override
  String newsPromptVersionSaved(int version) {
    return 'Saved as version $version.';
  }

  @override
  String newsPromptSaveFailed(String reason) {
    return 'Save failed: $reason';
  }

  @override
  String get newsPromptVersionsTitle => 'Versions (roll back any time)';

  @override
  String get newsPromptVersionNone =>
      'No saved versions yet; the built-in template is in use.';

  @override
  String newsPromptVersionItem(int version, String mode) {
    return 'Version $version · $mode';
  }

  @override
  String get newsPromptVersionUse => 'Load this version';

  @override
  String newsPromptVersionLoaded(int version) {
    return 'Version $version loaded; save it to make it current.';
  }

  @override
  String get newsPromptVersionDelete => 'Delete this version';

  @override
  String get newsPromptDiffTitle => 'Missing required-site tasks';

  @override
  String newsPromptDiffMissing(String sites) {
    return 'These required sites do not appear in your overall prompt: $sites. They are still listed as required tasks and will be fetched one by one; confirm that is what you want.';
  }

  @override
  String get newsPromptDiffCitationMissing =>
      'Your overall prompt has no citation marker (like [sourceId]); the fixed protocol is still appended when sending, but keeping your own citation requirement is recommended.';

  @override
  String get newsPromptPreviewTitle => 'Prompt that will actually be sent';

  @override
  String get newsPromptPreviewHint =>
      'Below is the full composed or overridden text (including the fixed protocol). Copy it to verify what will actually be requested.';

  @override
  String get newsEffectiveQueriesTitle =>
      'Queries that will actually be sent (blocked terms applied)';

  @override
  String get newsEffectiveQueriesEmpty =>
      'There are no sendable queries right now (keywords are empty or all blocked).';

  @override
  String get newsPlannedNotice =>
      'Daily-news retrieval orchestration and drafting (T037), source verification (T038) and scheduling (T040) come later; this page only covers the SET-050–055 configuration.';

  @override
  String get todayGenerate => 'Generate today\'s news';

  @override
  String get todayRegenerate => 'Generate again';

  @override
  String get todayCancelGenerate => 'Cancel generation';

  @override
  String get todayDateLabel => 'Date';

  @override
  String get todayPreviousDay => 'Previous day';

  @override
  String get todayNextDay => 'Next day';

  @override
  String get todayProgressTitle => 'Progress';

  @override
  String get todayStageSnapshot => 'Freezing the input snapshot';

  @override
  String get todayStageRequiredSites => 'Fetching required sites';

  @override
  String get todayStageSearch => 'Searching the web';

  @override
  String get todayStageGenerate => 'Drafting';

  @override
  String get todayStageVerify => 'Verifying independent sources';

  @override
  String get todayStageSave => 'Saving the version';

  @override
  String get todayNoVersionTitle => 'No news for this day yet';

  @override
  String get todayNoVersionBody =>
      'News is produced only when you press Generate: it uses the configured required sites, search keywords and model, and builds cited items from your local articles plus fetched material. Until then this page stays empty instead of inventing content.';

  @override
  String todayMaterialCount(int count) {
    return '$count input materials this run';
  }

  @override
  String todayRejectedCount(int count) {
    return '$count items were dropped for citing material that does not exist';
  }

  @override
  String get todaySiteFailedTitle => 'Required sites';

  @override
  String todaySiteOk(int chars) {
    return 'Fetched ($chars characters)';
  }

  @override
  String get todaySiteTimeout => 'Timed out';

  @override
  String todaySiteFailed(String reason) {
    return 'Failed ($reason)';
  }

  @override
  String get todaySiteSkipped => 'Not attempted';

  @override
  String get todayLabelSingleSource => 'Single source';

  @override
  String get todayLabelInsufficient => 'Insufficient material';

  @override
  String get todayLabelConflict => 'Sources conflict';

  @override
  String get todayLabelNotVerified => 'Not verified online';

  @override
  String get todayLabelLegend =>
      'Labels: single source = only one independent source found; insufficient material = verification got no usable result; sources conflict = a second source explicitly denies the claim; not verified online = no search service is configured. These describe the verification process, not a guarantee of truth.';

  @override
  String get todayCitationLocal => 'Local article';

  @override
  String get todayCitationOpen => 'Open in browser';

  @override
  String get todayCitationRss => 'RSS';

  @override
  String get todayCitationFetch => 'Fetched page';

  @override
  String get todayCitationSearch => 'Search snippet';

  @override
  String todayCitationIncomplete(String fields) {
    return 'This citation is missing: $fields';
  }

  @override
  String todayUnknownCitation(String ids) {
    return 'The model cited material that does not exist; those items were dropped: $ids';
  }

  @override
  String get todayVersionsTitle => 'Versions';

  @override
  String todayVersionItem(int version, String status) {
    return 'Version $version ($status)';
  }

  @override
  String get todayVersionCurrent => 'Shown now';

  @override
  String get todayVersionUse => 'Show this version';

  @override
  String todayVersionSwitched(int version) {
    return 'Switched to version $version';
  }

  @override
  String get todayDraftLabel => 'Draft';

  @override
  String get todayVerifiedLabel => 'Verified';

  @override
  String todayModelLabel(String model) {
    return 'Model: $model';
  }

  @override
  String todayVerificationMethod(String method) {
    return 'Verification method: $method';
  }

  @override
  String get todayCostConfirmTitle => 'Confirm generation (this costs money)';

  @override
  String todayCostConfirmBody(int articles, int sites, int queries) {
    return 'Generation uses model calls and web searches and may cost money: up to $articles articles, $sites required sites and $queries queries this run, bounded by the time limit and the token budget. It is a real network request that sends data.';
  }

  @override
  String get todayCostConfirmRegenerate =>
      'This day already has a generated version; generating again adds a version and costs money again.';

  @override
  String get todayCostConfirmSend => 'Generate';

  @override
  String get todayCostConfirmCancel => 'Not now';

  @override
  String todayGenerateFailed(String reason) {
    return 'Generation did not finish: $reason';
  }

  @override
  String todayGenerateSucceeded(int version) {
    return 'Saved as version $version';
  }

  @override
  String get todayShortfallNoInput =>
      'There was no usable input this run (no articles selected for news, no keywords, and no required site returned content), so nothing was generated. Check the SET-050 per-feed switches, the required-sites list, and whether your articles have been refreshed.';

  @override
  String get todayShortfallGlobalDisabled =>
      'The RSS master switch is off and there is no other input (keywords or required sites), so nothing was generated. You can turn it on in Settings → News generation.';

  @override
  String get todayJournalNotice =>
      'Labels, versions and materials all come from local records; model output is not a guarantee of truth — check the citations yourself.';

  @override
  String get todayRecentLabel => 'Last 7 days';

  @override
  String get todayPickDate => 'Pick a date';

  @override
  String get todayTodayChip => 'Today';

  @override
  String get todayIsToday => 'Today';

  @override
  String todayHistoryBanner(String date) {
    return 'You are viewing versions for $date. Historical records keep the device time zone in effect when they were generated; changing time zones now does not rewrite them.';
  }

  @override
  String get todaySitesProgressTitle => 'Required sites (per site)';

  @override
  String get todaySitePending => 'Waiting';

  @override
  String get todayCancelling => 'Cancelling…';

  @override
  String get todayStatusTitle => 'This run\'s status';

  @override
  String get todayStatusCancelled =>
      'This run was cancelled. Stage information already completed is kept in the record below.';

  @override
  String get todayStatusInterrupted =>
      'This task was terminated by the system before it finished (app quit or crash). It is not retried automatically, so a request that may already have been billed is not sent twice; you can generate again manually when you want.';

  @override
  String get todayStatusWaitingConfiguration =>
      'Required configuration is missing (no enabled AI model, or the first-time cost notice has not been confirmed), so no request was sent. Generate again after you finish the setup.';

  @override
  String get todayStatusWaitingNetwork =>
      'The device had no network while generating; the task paused and ended without a usable result. Generate again once you are online.';

  @override
  String get todayStatusRunning =>
      'A task record is still marked as running. If the app was force-quit, it has been marked interrupted and will not be retried automatically.';

  @override
  String todayStatusFailed(String reason) {
    return 'This run failed: $reason. The last successful summary is unaffected.';
  }

  @override
  String get todayStatusInsufficient =>
      'Insufficient material: there was not enough input (no articles selected for news, no keywords, and no required site returned content), so no items were generated and nothing was invented.';

  @override
  String todayStatusStage(String stage) {
    return 'Stopped at the \"$stage\" step.';
  }

  @override
  String get todayNoResultYet =>
      'This day\'s generation has not produced any usable items yet.';

  @override
  String todayVersionItemDetail(
    int version,
    String status,
    String time,
    String model,
  ) {
    return 'Version $version · $status · $time · $model';
  }

  @override
  String get todayVersionModelUnknown => 'model not recorded';

  @override
  String get todayVersionDelete => 'Delete';

  @override
  String get todayVersionDeleteTooltip =>
      'Delete this historical version (the currently shown version cannot be deleted)';

  @override
  String todayVersionDeleteConfirmTitle(int version) {
    return 'Delete version $version?';
  }

  @override
  String todayVersionDeleteConfirmBody(int version) {
    return 'This permanently deletes version $version for this day. The currently shown version is not deleted and other versions and material records are unaffected.';
  }

  @override
  String get todayVersionDeleteConfirmOk => 'Delete';

  @override
  String get todayVersionDeleteCancel => 'Cancel';

  @override
  String todayVersionDeleted(int version) {
    return 'Deleted version $version';
  }

  @override
  String todayVersionDeleteFailed(String reason) {
    return 'Delete failed: $reason';
  }

  @override
  String get todayCitationContentCleared =>
      'This local article\'s body has been cleared (for example by cache cleanup); only the minimal excerpt saved at the time can be shown.';

  @override
  String get todayCitationExcerptCleared =>
      'The original has been cleared; only the minimal excerpt is kept.';

  @override
  String todayCacheClearedNotice(int count) {
    return 'On this day, $count cited local articles have had their bodies cleared; the minimal excerpts saved at the time are still shown.';
  }
}
