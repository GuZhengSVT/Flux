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

  FeedLibraryState copyWith({
    bool? loading,
    String? error,
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
  }) {
    return FeedLibraryState(
      loading: loading ?? this.loading,
      error: error ?? this.error,
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

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    _reload();
  }

  void _reload({String? error}) {
    state = state.copyWith(
      loading: false,
      error: error,
      feeds: _applyFeedPreferences(_db.getFeeds()),
      groups: _db.getGroups(),
      articles: _applyGroupFilter(
        _applyArticleTimeRange(
          _db.getArticles(
            feedId: state.selectedFeedId,
            unreadOnly: state.filter == FeedFilter.unread ? true : null,
            favoritesOnly: state.filter == FeedFilter.favorites ? true : null,
            readLaterOnly: state.filter == FeedFilter.readLater ? true : null,
            query: state.query,
          ),
        ),
      ),
    );
  }

  List<Article> _applyGroupFilter(List<Article> articles) {
    final group = state.selectedGroup;
    if (group == null || group.isEmpty) {
      return articles;
    }
    final feeds = _db.getFeeds();
    final Set<int> feedIds;
    if (group == '__ungrouped__') {
      feedIds = feeds
          .where((f) => f.category == null || f.category!.trim().isEmpty)
          .map((f) => f.id!)
          .toSet();
    } else {
      feedIds = feeds
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
    _reload();
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
    for (final feed in feeds) {
      await _refreshOne(feed, notify: false);
    }
    _reload();
  }

  Future<void> refreshFeed(int feedId) async {
    final feeds = _db.getFeeds();
    Feed? feed;
    for (final f in feeds) {
      if (f.id == feedId) {
        feed = f;
        break;
      }
    }
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

  void renameFeed(int feedId, String newTitle) {
    final feeds = _db.getFeeds();
    for (final feed in feeds) {
      if (feed.id == feedId) {
        _db.updateFeed(feed.copyWith(title: newTitle.trim()));
        break;
      }
    }
    _reload();
  }

  void updateFeedCategory(int feedId, String? category) {
    final clean = category?.trim();
    final normalized = (clean == null || clean.isEmpty) ? null : clean;
    if (normalized != null) {
      _db.ensureGroup(normalized);
    }
    final feeds = _db.getFeeds();
    for (final feed in feeds) {
      if (feed.id == feedId) {
        _db.updateFeed(feed.copyWith(category: normalized));
        break;
      }
    }
    _reload();
  }

  void updateFeedUrl(int feedId, String newUrl) {
    final clean = newUrl.trim();
    if (clean.isEmpty) {
      return;
    }
    final feeds = _db.getFeeds();
    for (final feed in feeds) {
      if (feed.id == feedId) {
        _db.updateFeed(feed.copyWith(url: clean));
        break;
      }
    }
    _reload();
  }

  void toggleFeedFavorite(int feedId) {
    final feeds = _db.getFeeds();
    for (final feed in feeds) {
      if (feed.id == feedId) {
        _db.updateFeed(feed.copyWith(isFavorite: !feed.isFavorite));
        break;
      }
    }
    _reload();
  }

  void setFeedRating(int feedId, int rating) {
    final clamped = rating.clamp(0, 5);
    final feeds = _db.getFeeds();
    for (final feed in feeds) {
      if (feed.id == feedId) {
        _db.updateFeed(feed.copyWith(rating: clamped));
        break;
      }
    }
    _reload();
  }

  void toggleFeedPinned(int feedId) {
    final feeds = _db.getFeeds();
    for (final feed in feeds) {
      if (feed.id == feedId) {
        _db.updateFeed(feed.copyWith(isPinned: !feed.isPinned));
        break;
      }
    }
    _reload();
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
    for (final feed in feeds) {
      await _refreshOne(feed, notify: false);
    }
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
        final feedId = _db.insertFeed(
          Feed(
            title: parsed.title.isNotEmpty ? parsed.title : item.title,
            url: parsed.sourceUrl,
            siteUrl: parsed.siteUrl,
            description: parsed.description,
            iconUrl: parsed.iconUrl,
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
    final updated = article.copyWith(isRead: read);
    _db.updateArticle(updated);
    _reload();
  }

  void markAllRead() {
    _db.markAllRead(state.selectedFeedId);
    _reload();
  }

  void toggleFavorite(Article article) {
    final updated = article.copyWith(isFavorite: !article.isFavorite);
    _db.updateArticle(updated);
    _reload();
  }

  void toggleReadLater(Article article) {
    final updated = article.copyWith(isReadLater: !article.isReadLater);
    _db.updateArticle(updated);
    _reload();
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
