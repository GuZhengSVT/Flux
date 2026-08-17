import 'dart:io';

import 'package:test/test.dart';

import 'package:flux/data/app_database.dart';
import 'package:flux/models/article.dart';
import 'package:flux/models/feed.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late AppDatabase db;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('flux_test_');
    dbPath = '${tempDir.path}/test.sqlite3';
    db = AppDatabase.open(dbPath);
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  test('insertFeed and getFeeds round trip', () {
    final id = db.insertFeed(
      Feed(title: 'Example', url: 'https://example.com/feed'),
    );
    final feeds = db.getFeeds();
    expect(feeds, hasLength(1));
    expect(feeds.first.id, id);
    expect(feeds.first.title, 'Example');
    expect(feeds.first.url, 'https://example.com/feed');
  });

  test('articles without link are deduplicated by unique index', () {
    final feedId = db.insertFeed(
      Feed(title: 'Example', url: 'https://example.com/feed'),
    );
    const title = 'No Link Article';
    db.insertArticles([
      Article(feedId: feedId, title: title, fetchedAt: DateTime.now()),
    ]);
    db.insertArticles([
      Article(feedId: feedId, title: title, fetchedAt: DateTime.now()),
    ]);
    final articles = db.getArticles(feedId: feedId);
    expect(
      articles.where((a) => a.link == null && a.title == title),
      hasLength(1),
    );
  });

  test('updateFeedCategory sets null to move to ungrouped', () {
    final id = db.insertFeed(
      Feed(title: 'Example', url: 'https://example.com/feed', category: 'Tech'),
    );
    db.updateFeedCategory(id, null);
    final feed = db.getFeedById(id)!;
    expect(feed.category, isNull);
  });

  test('deleteFeed cascades articles', () {
    final feedId = db.insertFeed(
      Feed(title: 'Example', url: 'https://example.com/feed'),
    );
    db.insertArticles([
      Article(feedId: feedId, title: 'A', fetchedAt: DateTime.now()),
    ]);
    db.deleteFeed(feedId);
    expect(db.getArticles(feedId: feedId), isEmpty);
  });
}