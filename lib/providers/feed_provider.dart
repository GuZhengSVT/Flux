import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../models/article.dart';
import 'core_providers.dart';
import '../models/feed.dart';
import '../services/feed_fetcher.dart';
import '../services/full_text_extractor.dart';
import '../services/opml_service.dart';

enum FeedFilter { all, unread, favorites, readLater }

enum FeedSort { name, lastUpdated }

enum ArticleSort { newestFirst, oldestFirst }

enum ArticleLayout { single, double, masonry }

enum TimeRange { all, today, week }

class FeedLibraryState {
  const FeedLibraryState({
    this.loading = false,
    this.error,
    this.feeds = const [],
    this.articles = const [],
    this.groups = const [],
    this.filter = FeedFilter.all,
    this.selectedFeedId,
    this.selectedGroup = '',
    this.query = '',
    this.feedSort = FeedSort.name,
    this.feedTimeRange = TimeRange.all,
    this.articleTimeRange = TimeRange.all,
    this.articleSort = ArticleSort.newestFirst,
    this.articleLayout = ArticleLayout.single,
    this.articleLimit = 1000,
    this.hasMoreArticles = false,
  });

  final bool loading;
  final String? error;
  final List<Feed> feeds;
  final List<Article> articles;
  final List<String> groups;
  final FeedFilter filter;
  final int? selectedFeedId;
  final String? selectedGroup;
  final String query;
  final FeedSort feedSort;
  final TimeRange feedTimeRange;
  final TimeRange articleTimeRange;
  final ArticleSort articleSort;
  final ArticleLayout articleLayout;

  /// 当前文章列表每页加载数量，默认与数据库单次查询上限一致。
  final int articleLimit;
  final bool hasMoreArticles;

  FeedLibraryState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<Feed>? feeds,
    List<Article>? articles,
    List<String>? groups,
    FeedFilter? filter,
    int? selectedFeedId,
    String? selectedGroup,
    String? query,
    FeedSort? feedSort,
    TimeRange? feedTimeRange,
    TimeRange? articleTimeRange,
    ArticleSort? articleSort,
    ArticleLayout? articleLayout,
    int? articleLimit,
    bool? hasMoreArticles,
  }) {
    return FeedLibraryState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      feeds: feeds ?? this.feeds,
      articles: articles ?? this.articles,
      groups: groups ?? this.groups,
      filter: filter ?? this.filter,
      selectedFeedId: selectedFeedId ?? this.selectedFeedId,
      selectedGroup: selectedGroup ?? this.selectedGroup,
      query: query ?? this.query,
      feedSort: feedSort ?? this.feedSort,
      feedTimeRange: feedTimeRange ?? this.feedTimeRange,
      articleTimeRange: articleTimeRange ?? this.articleTimeRange,
      articleSort: articleSort ?? this.articleSort,
      articleLayout: articleLayout ?? this.articleLayout,
      articleLimit: articleLimit ?? this.articleLimit,
      hasMoreArticles: hasMoreArticles ?? this.hasMoreArticles,
    );
  }
}

class FeedController extends StateNotifier<FeedLibraryState> {
  FeedController(this._db, this._fetcher, this._fullTextExtractor)
    : super(const FeedLibraryState()) {
    load();
  }

  final AppDatabase _db;
  final FeedFetcher _fetcher;
  final FullTextExtractor _fullTextExtractor;

  /// 搜索输入防抖定时器，静默一段时间后才触发重查。
  Timer? _searchDebounce;

  /// 当前文章列表已加载到的偏移量，供“加载更多”使用。
  int _articleOffset = 0;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    _reload();
  }

  /// 清除当前错误提示（供 UI 上的“知道了”按钮调用）。
  void clearError() {
    if (state.error != null) {
      state = state.copyWith(clearError: true);
    }
  }

  void _reload({String? error}) {
    final feeds = _applyFeedPreferences(_db.getFeeds());
    final articles = _applyGroupFilter(
      _applyArticleTimeRange(
        _db.getArticles(
          feedId: state.selectedFeedId,
          unreadOnly: state.filter == FeedFilter.unread ? true : null,
          favoritesOnly: state.filter == FeedFilter.favorites ? true : null,
          readLaterOnly: state.filter == FeedFilter.readLater ? true : null,
          query: state.query,
          limit: state.articleLimit,
          offset: 0,
        ),
      ),
      feeds: feeds,
    );
    _articleOffset = 0;
    state = state.copyWith(
      loading: false,
      error: error,
      feeds: feeds,
      groups: _db.getGroups(),
      articles: articles,
      hasMoreArticles: articles.length >= state.articleLimit,
    );
  }

  List<Article> _applyGroupFilter(List<Article> articles, {List<Feed>? feeds}) {
    final group = state.selectedGroup;
    if (group == null || group.isEmpty) {
      return articles;
    }
    final sourceFeeds = feeds ?? state.feeds;
    final Set<int> feedIds;
    if (group == '__ungrouped__') {
      feedIds = sourceFeeds
          .where((f) => f.category == null || f.category!.trim().isEmpty)
          .map((f) => f.id!)
          .toSet();
    } else {
      feedIds = sourceFeeds
          .where((f) => f.category == group)
          .map((f) => f.id!)
          .toSet();
    }
    return articles.where((a) => feedIds.contains(a.feedId)).toList();
  }

  List<Feed> _applyFeedPreferences(List<Feed> feeds) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final week = today.subtract(const Duration(days: 7));

    final filtered = feeds.where((feed) {
      final last = feed.lastFetchedAt;
      if (last == null) {
        return state.feedTimeRange == TimeRange.all;
      }
      return switch (state.feedTimeRange) {
        TimeRange.all => true,
        TimeRange.today => !last.isBefore(today),
        TimeRange.week => !last.isBefore(week),
      };
    }).toList();

    filtered.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return switch (state.feedSort) {
        FeedSort.name => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        FeedSort.lastUpdated =>
          (b.lastFetchedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            a.lastFetchedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
      };
    });
    return filtered;
  }

  List<Article> _applyArticleTimeRange(List<Article> articles) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final week = today.subtract(const Duration(days: 7));

    final filtered = articles.where((article) {
      final time = article.publishedAt ?? article.fetchedAt;
      if (time == null) {
        return state.articleTimeRange == TimeRange.all;
      }
      return switch (state.articleTimeRange) {
        TimeRange.all => true,
        TimeRange.today => !time.isBefore(today),
        TimeRange.week => !time.isBefore(week),
      };
    }).toList();

    filtered.sort((a, b) {
      final at =
          a.publishedAt ??
          a.fetchedAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bt =
          b.publishedAt ??
          b.fetchedAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return state.articleSort == ArticleSort.newestFirst
          ? bt.compareTo(at)
          : at.compareTo(bt);
    });
    return filtered;
  }

  void selectFeed(int? feedId) {
    state = state.copyWith(selectedFeedId: feedId, selectedGroup: '');
    _reload();
  }

  void selectGroup(String group) {
    state = state.copyWith(selectedFeedId: null, selectedGroup: group);
    _reload();
  }

  void setFilter(FeedFilter filter) {
    state = state.copyWith(filter: filter);
    _reload();
  }

  void setQuery(String query) {
    state = state.copyWith(query: query);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _reload();
    });
  }

  void setFeedSort(FeedSort sort) {
    state = state.copyWith(feedSort: sort);
    _reload();
  }

  void setFeedTimeRange(TimeRange range) {
    state = state.copyWith(feedTimeRange: range);
    _reload();
  }

  void setArticleTimeRange(TimeRange range) {
    state = state.copyWith(articleTimeRange: range);
    _reload();
  }

  void setArticleSort(ArticleSort sort) {
    state = state.copyWith(articleSort: sort);
    _reload();
  }

  void setArticleLayout(ArticleLayout layout) {
    state = state.copyWith(articleLayout: layout);
    _reload();
  }

  /// 加载下一页文章并追加到当前列表。
  ///
  /// UI 尚未接线；此方法供后续分页 UI 使用，当前保持向后兼容。
  Future<void> loadMore() async {
    if (!state.hasMoreArticles) {
      return;
    }
    final offset = _articleOffset + state.articleLimit;
    final more = _applyGroupFilter(
      _applyArticleTimeRange(
        _db.getArticles(
          feedId: state.selectedFeedId,
          unreadOnly: state.filter == FeedFilter.unread ? true : null,
          favoritesOnly: state.filter == FeedFilter.favorites ? true : null,
          readLaterOnly: state.filter == FeedFilter.readLater ? true : null,
          query: state.query,
          limit: state.articleLimit,
          offset: offset,
        ),
      ),
      feeds: state.feeds,
    );
    _articleOffset = offset;
    state = state.copyWith(
      articles: [...state.articles, ...more],
      hasMoreArticles: more.length >= state.articleLimit,
    );
  }

  Future<void> addFeed(String url) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final parsed = await _fetcher.fetchAndParse(url);
      if (_db.feedCountForUrl(parsed.sourceUrl) > 0) {
        state = state.copyWith(
          loading: false,
          error: '该订阅源已存在：${parsed.title}',
        );
        return;
      }
      final feed = Feed(
        title: parsed.title,
        url: parsed.sourceUrl,
        siteUrl: parsed.siteUrl,
        description: parsed.description,
        iconUrl: parsed.iconUrl,
        lastFetchedAt: DateTime.now(),
      );
      final feedId = _db.insertFeed(feed);
      _db.insertArticles(
        parsed.articles.map((article) => article.toArticle(feedId)).toList(),
      );
      _reload();
    } on FeedFetchException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: '添加订阅失败：$e');
    }
  }

  Future<void> refreshAll() async {
    final feeds = _db.getFeeds();
    if (feeds.isEmpty) {
      return;
    }
    state = state.copyWith(loading: true, error: null);
    await _refreshFeeds(feeds);
    _reload();
  }

  /// 以有界并发方式刷新多个订阅。
  ///
  /// 每次最多并发 [refreshConcurrency] 个，`_refreshOne` 内部已隔离单源异常。
  Future<void> _refreshFeeds(
    List<Feed> feeds, {
    int refreshConcurrency = 4,
  }) async {
    for (var start = 0; start < feeds.length; start += refreshConcurrency) {
      final batch = feeds.skip(start).take(refreshConcurrency).toList();
      await Future.wait(batch.map((feed) => _refreshOne(feed, notify: false)));
    }
  }

  Future<void> refreshFeed(int feedId) async {
    final feed = _db.getFeedById(feedId);
    if (feed == null) {
      return;
    }
    state = state.copyWith(loading: true, error: null);
    await _refreshOne(feed, notify: true);
  }

  Future<void> _refreshOne(Feed feed, {required bool notify}) async {
    try {
      final parsed = await _fetcher.fetchAndParse(feed.url);
      final updatedFeed = feed.copyWith(
        title: parsed.title,
        siteUrl: parsed.siteUrl,
        description: parsed.description,
        iconUrl: parsed.iconUrl ?? feed.iconUrl,
        lastFetchedAt: DateTime.now(),
      );
      _db.updateFeed(updatedFeed);
      _db.insertArticles(
        parsed.articles.map((a) => a.toArticle(feed.id!)).toList(),
      );
      if (notify) {
        _reload();
      }
    } on FeedFetchException catch (e) {
      if (notify) {
        _reload(error: '刷新失败：${e.message}');
      }
    } catch (e) {
      if (notify) {
        _reload(error: '刷新失败：$e');
      }
    }
  }

  void deleteFeed(int feedId) {
    _db.deleteFeed(feedId);
    if (state.selectedFeedId == feedId) {
      state = state.copyWith(selectedFeedId: null);
    }
    _reload();
  }

  /// 按 id 更新单个订阅；订阅不存在时静默跳过。
  void _updateFeedById(int feedId, Feed Function(Feed feed) update) {
    final feed = _db.getFeedById(feedId);
    if (feed == null) {
      return;
    }
    _db.updateFeed(update(feed));
    _reload();
  }

  void renameFeed(int feedId, String newTitle) {
    _updateFeedById(feedId, (feed) => feed.copyWith(title: newTitle.trim()));
  }

  void updateFeedCategory(int feedId, String? category) {
    final clean = category?.trim();
    final normalized = (clean == null || clean.isEmpty) ? null : clean;
    if (normalized != null) {
      _db.ensureGroup(normalized);
    }
    // 直写 SQL：`Feed.copyWith` 无法把可空字段置回 null，
    // 走 copyWith 会导致“移到未分组”静默失败。
    _db.updateFeedCategory(feedId, normalized);
    _reload();
  }

  void updateFeedUrl(int feedId, String newUrl) {
    final clean = newUrl.trim();
    if (clean.isEmpty) {
      return;
    }
    _updateFeedById(feedId, (feed) => feed.copyWith(url: clean));
  }

  void toggleFeedFavorite(int feedId) {
    _updateFeedById(
      feedId,
      (feed) => feed.copyWith(isFavorite: !feed.isFavorite),
    );
  }

  void setFeedRating(int feedId, int rating) {
    final clamped = rating.clamp(0, 5);
    _updateFeedById(feedId, (feed) => feed.copyWith(rating: clamped));
  }

  void toggleFeedPinned(int feedId) {
    _updateFeedById(feedId, (feed) => feed.copyWith(isPinned: !feed.isPinned));
  }

  void createGroup(String name) {
    _db.addGroup(name);
    _reload();
  }

  void renameGroup(String oldName, String newName) {
    final cleanNew = newName.trim();
    if (cleanNew.isEmpty) {
      return;
    }
    _db.renameGroup(oldName, cleanNew);
    _reload();
  }

  void deleteGroup(String groupName) {
    _db.deleteGroup(groupName, deleteFeeds: false);
    _reload();
  }

  void deleteGroupWithOption(String groupName, {required bool deleteFeeds}) {
    _db.deleteGroup(groupName, deleteFeeds: deleteFeeds);
    _reload();
  }

  Future<void> refreshGroup(String groupName) async {
    final feeds = _db.getFeeds().where((f) => f.category == groupName).toList();
    if (feeds.isEmpty) {
      return;
    }
    state = state.copyWith(loading: true, error: null);
    await _refreshFeeds(feeds);
    _reload();
  }

  Future<int> importOpml(String xml) async {
    final items = const OpmlService().parse(xml);
    if (items.isEmpty) {
      state = state.copyWith(error: 'OPML 中没有找到可导入的订阅');
      return 0;
    }

    state = state.copyWith(loading: true, error: null);
    var added = 0;
    for (final item in items) {
      if (_db.feedCountForUrl(item.xmlUrl) > 0) {
        continue;
      }
      try {
        final parsed = await _fetcher.fetchAndParse(item.xmlUrl);
        final category = item.category?.trim();
        if (category != null && category.isNotEmpty) {
          _db.ensureGroup(category);
        }
        final feedId = _db.insertFeed(
          Feed(
            title: parsed.title.isNotEmpty ? parsed.title : item.title,
            url: parsed.sourceUrl,
            siteUrl: parsed.siteUrl,
            description: parsed.description,
            iconUrl: parsed.iconUrl,
            category: category,
            lastFetchedAt: DateTime.now(),
          ),
        );
        _db.insertArticles(
          parsed.articles.map((a) => a.toArticle(feedId)).toList(),
        );
        added++;
      } catch (_) {
        // 单个 OPML 条目失败不中断整体导入。
      }
    }
    _reload(error: added == 0 ? '没有新增订阅（可能已存在或全部抓取失败）' : null);
    return added;
  }

  String exportOpml() {
    return const OpmlService().export(_db.getFeeds());
  }

  void markRead(Article article, bool read) {
    _updateSingleArticle(article.copyWith(isRead: read));
  }

  void markAllRead() {
    _db.markAllRead(state.selectedFeedId);
    _reload();
  }

  void toggleFavorite(Article article) {
    _updateSingleArticle(article.copyWith(isFavorite: !article.isFavorite));
  }

  void toggleReadLater(Article article) {
    _updateSingleArticle(article.copyWith(isReadLater: !article.isReadLater));
  }

  /// 单条文章操作后的内存更新。
  ///
  /// 先写库，再在 `state.articles` 中替换对应项；若当前筛选（未读/收藏/稍后读）
  /// 不再满足，则从当前列表移除。由于操作只改变布尔状态，不改变 feed/分组/
  /// 时间/搜索条件，无需重查 feeds/groups 或全量文章。
  /// 若文章不在当前列表（例如从外部打开的文章），回退到全量 `_reload()`。
  void _updateSingleArticle(Article updated) {
    _db.updateArticle(updated);
    final index = state.articles.indexWhere((a) => a.id == updated.id);
    if (index == -1) {
      _reload();
      return;
    }

    final nextArticles = [...state.articles];
    nextArticles[index] = updated;
    final filtered = nextArticles.where((a) {
      return switch (state.filter) {
        FeedFilter.all => true,
        FeedFilter.unread => !a.isRead,
        FeedFilter.favorites => a.isFavorite,
        FeedFilter.readLater => a.isReadLater,
      };
    }).toList();

    state = state.copyWith(articles: filtered);
  }

  /// 抓取原文全文并更新本地缓存。
  ///
  /// 返回更新后的 Article；失败时返回 null。
  Future<Article?> fetchFullText(Article article) async {
    if (article.link == null || article.id == null) {
      return null;
    }
    try {
      final content = await _fullTextExtractor.extract(article.link!);
      _db.updateArticleContent(article.id!, content);
      final updated = article.copyWith(contentHtml: content);
      _reload();
      return updated;
    } catch (_) {
      return null;
    }
  }
}

final feedControllerProvider =
    StateNotifierProvider<FeedController, FeedLibraryState>((ref) {
      return FeedController(
        ref.watch(databaseProvider),
        ref.watch(feedFetcherProvider),
        ref.watch(fullTextExtractorProvider),
      );
    });
