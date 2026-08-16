import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../models/article.dart';
import '../models/feed.dart';

/// Flux 本地 SQLite 数据层。
///
/// 使用 Flutter 端由 sqlite3_flutter_libs 提供的原生 SQLite，
/// 避免引入代码生成/ORM，降低构建复杂度。
class AppDatabase {
  AppDatabase(this._db);

  final Database _db;

  factory AppDatabase.open(String dbPath) {
    if (p.extension(dbPath) != '.sqlite3') {
      dbPath = p.setExtension(dbPath, '.sqlite3');
    }
    Directory(p.dirname(dbPath)).createSync(recursive: true);
    final db = sqlite3.open(dbPath);
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA synchronous = NORMAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    final database = AppDatabase(db);
    database._migrate();
    return database;
  }

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS feeds (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        url TEXT NOT NULL UNIQUE,
        site_url TEXT,
        description TEXT,
        category TEXT,
        icon_url TEXT,
        last_fetched_at TEXT
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feed_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        link TEXT,
        author TEXT,
        published_at TEXT,
        content TEXT,
        summary TEXT,
        image_url TEXT,
        categories TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_read_later INTEGER NOT NULL DEFAULT 0,
        fetched_at TEXT,
        FOREIGN KEY(feed_id) REFERENCES feeds(id) ON DELETE CASCADE
      );
    ''');

    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_articles_feed ON articles(feed_id);',
    );
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_articles_read ON articles(is_read);',
    );
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_articles_published ON articles(published_at DESC);',
    );
    _db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_articles_feed_link_title '
      'ON articles(feed_id, link, title);',
    );

    _ensureColumn('feeds', 'is_favorite', 'INTEGER NOT NULL DEFAULT 0');
    _ensureColumn('feeds', 'rating', 'INTEGER NOT NULL DEFAULT 0');
    _ensureColumn('feeds', 'is_pinned', 'INTEGER NOT NULL DEFAULT 0');
  }

  void _ensureColumn(String table, String column, String definition) {
    final columns = _db
        .select('PRAGMA table_info($table)')
        .map((row) => row['name'] as String)
        .toList();
    if (!columns.contains(column)) {
      _db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  void close() => _db.close();

  // ============ Feeds ============

  int insertFeed(Feed feed) {
    _db.execute(
      '''
      INSERT INTO feeds (title, url, site_url, description, category, icon_url, last_fetched_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        feed.title,
        feed.url,
        feed.siteUrl,
        feed.description,
        feed.category,
        feed.iconUrl,
        feed.lastFetchedAt?.toIso8601String(),
      ],
    );
    return _db.lastInsertRowId;
  }

  void updateFeed(Feed feed) {
    _db.execute(
      '''
      UPDATE feeds
      SET title = ?, url = ?, site_url = ?, description = ?, category = ?,
          icon_url = ?, last_fetched_at = ?, is_favorite = ?, rating = ?, is_pinned = ?
      WHERE id = ?
      ''',
      [
        feed.title,
        feed.url,
        feed.siteUrl,
        feed.description,
        feed.category,
        feed.iconUrl,
        feed.lastFetchedAt?.toIso8601String(),
        feed.isFavorite ? 1 : 0,
        feed.rating,
        feed.isPinned ? 1 : 0,
        feed.id,
      ],
    );
  }

  void deleteFeed(int feedId) {
    _db.execute('DELETE FROM feeds WHERE id = ?', [feedId]);
  }

  List<Feed> getFeeds() {
    final rows = _db.select(
      'SELECT * FROM feeds ORDER BY title COLLATE NOCASE',
    );
    return rows.map(Feed.fromMap).toList();
  }

  int feedCountForUrl(String url) {
    final rows = _db.select('SELECT COUNT(*) AS c FROM feeds WHERE url = ?', [
      url,
    ]);
    return rows.first['c'] as int;
  }

  // ============ Groups ============

  List<String> getGroups() {
    final rows = _db.select('''
      SELECT name FROM (
        SELECT name FROM groups
        UNION
        SELECT DISTINCT category AS name FROM feeds
        WHERE category IS NOT NULL AND category != ''
      )
      ORDER BY name COLLATE NOCASE
    ''');
    return rows.map((row) => row['name'] as String).toList();
  }

  void addGroup(String name) {
    final clean = name.trim();
    if (clean.isEmpty) {
      return;
    }
    _db.execute('INSERT OR IGNORE INTO groups (name) VALUES (?)', [clean]);
  }

  void ensureGroup(String? name) {
    final clean = name?.trim();
    if (clean == null || clean.isEmpty) {
      return;
    }
    _db.execute('INSERT OR IGNORE INTO groups (name) VALUES (?)', [clean]);
  }

  void renameGroup(String oldName, String newName) {
    final clean = newName.trim();
    if (clean.isEmpty || clean == oldName) {
      return;
    }
    _db.execute('UPDATE groups SET name = ? WHERE name = ?', [clean, oldName]);
    _db.execute('UPDATE feeds SET category = ? WHERE category = ?', [
      clean,
      oldName,
    ]);
  }

  /// 删除分组。
  ///
  /// [deleteFeeds] 为 true 时同时删除该分组下的订阅；为 false 时
  /// 只把订阅移到“未分组”（category 置空）。
  void deleteGroup(String name, {required bool deleteFeeds}) {
    if (deleteFeeds) {
      final rows = _db.select('SELECT id FROM feeds WHERE category = ?', [
        name,
      ]);
      for (final row in rows) {
        _db.execute('DELETE FROM feeds WHERE id = ?', [row['id']]);
      }
    } else {
      _db.execute('UPDATE feeds SET category = NULL WHERE category = ?', [
        name,
      ]);
    }
    _db.execute('DELETE FROM groups WHERE name = ?', [name]);
  }

  // ============ Articles ============

  void insertArticles(List<Article> articles) {
    _db.execute('BEGIN');
    try {
      for (final article in articles) {
        _db.execute(
          '''
          INSERT OR IGNORE INTO articles (
            feed_id, title, link, author, published_at, content, summary,
            image_url, categories, is_read, is_favorite, is_read_later, fetched_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, ?)
          ''',
          [
            article.feedId,
            article.title,
            article.link,
            article.author,
            article.publishedAt?.toIso8601String(),
            article.contentHtml,
            article.summary,
            article.imageUrl,
            article.categories?.join('|'),
            article.fetchedAt?.toIso8601String(),
          ],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<Article> getArticles({
    int? feedId,
    bool? unreadOnly,
    bool? favoritesOnly,
    bool? readLaterOnly,
    String? query,
    int limit = 500,
  }) {
    final where = <String>[];
    final args = <Object?>[];

    if (feedId != null) {
      where.add('feed_id = ?');
      args.add(feedId);
    }
    if (unreadOnly == true) {
      where.add('is_read = 0');
    }
    if (favoritesOnly == true) {
      where.add('is_favorite = 1');
    }
    if (readLaterOnly == true) {
      where.add('is_read_later = 1');
    }
    if (query != null && query.trim().isNotEmpty) {
      where.add('(title LIKE ? OR summary LIKE ? OR content LIKE ?)');
      final like = '%${query.trim()}%';
      args.addAll([like, like, like]);
    }

    final sql =
        '''
      SELECT a.*, f.title AS feed_title, f.icon_url AS feed_icon_url
      FROM articles a
      LEFT JOIN feeds f ON f.id = a.feed_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY COALESCE(a.published_at, a.fetched_at) DESC
      LIMIT ?
    ''';
    args.add(limit);

    final rows = _db.select(sql, args);
    return rows.map(Article.fromMap).toList();
  }

  void updateArticle(Article article) {
    _db.execute(
      '''
      UPDATE articles
      SET is_read = ?, is_favorite = ?, is_read_later = ?
      WHERE id = ?
      ''',
      [
        article.isRead ? 1 : 0,
        article.isFavorite ? 1 : 0,
        article.isReadLater ? 1 : 0,
        article.id,
      ],
    );
  }

  void updateArticleContent(int articleId, String contentHtml) {
    _db.execute('UPDATE articles SET content = ? WHERE id = ?', [
      contentHtml,
      articleId,
    ]);
  }

  void markAllRead(int? feedId) {
    if (feedId == null) {
      _db.execute('UPDATE articles SET is_read = 1');
    } else {
      _db.execute('UPDATE articles SET is_read = 1 WHERE feed_id = ?', [
        feedId,
      ]);
    }
  }

  void deleteArticlesForFeed(int feedId) {
    _db.execute('DELETE FROM articles WHERE feed_id = ?', [feedId]);
  }

  /// 删除早于 [retention] 的文章（文本保存策略）。
  ///
  /// 使用 `fetched_at`，缺失时回退到 `published_at`。
  int deleteArticlesOlderThan(Duration retention) {
    final cutoff = DateTime.now().subtract(retention).toIso8601String();
    _db.execute(
      'DELETE FROM articles WHERE COALESCE(fetched_at, published_at) < ?',
      [cutoff],
    );
    return _db.updatedRows;
  }

  int unreadCount() {
    final rows = _db.select(
      'SELECT COUNT(*) AS c FROM articles WHERE is_read = 0',
    );
    return rows.first['c'] as int;
  }
}
