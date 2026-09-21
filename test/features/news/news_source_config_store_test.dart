// T036：新闻来源配置存储的真实 SQLite 往返（SET-050–055）。
//
// 三条与实现纪律对应的断言：
//   1) 有序列表整体替换：删掉中间一项后其余项的顺序紧密、不留空洞；
//   2) 两个禁词列表**互不污染**（各自的 kind 分开读回）；
//   3) prompt 版本只增不改：保存两次得到两行，旧版本仍可读回。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/infrastructure/local/news_source_config_store.dart';

void main() {
  late AppDatabase db;
  late DriftNewsSourceConfigStore store;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    store = DriftNewsSourceConfigStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('必访站整体替换并按列表顺序写回', () async {
    await store.replaceRequiredSites(<NewsRequiredSite>[
      const NewsRequiredSite(name: '甲', url: 'https://a.example.com'),
      const NewsRequiredSite(name: '乙', url: 'https://b.example.com'),
      const NewsRequiredSite(
        name: '丙',
        url: 'https://c.example.com',
        enabled: false,
      ),
    ]);
    final List<NewsRequiredSite> loaded = (await store.loadRequiredSites())
        .unwrap();
    expect(loaded.map((NewsRequiredSite s) => s.name).toList(), <String>[
      '甲',
      '乙',
      '丙',
    ]);
    expect(loaded[2].enabled, isFalse);

    // 删掉中间一项：剩下的顺序必须紧密（sort_order 0,1），不留空洞。
    await store.replaceRequiredSites(<NewsRequiredSite>[
      const NewsRequiredSite(name: '甲', url: 'https://a.example.com'),
      const NewsRequiredSite(name: '丙', url: 'https://c.example.com'),
    ]);
    final List<NewsRequiredSite> after = (await store.loadRequiredSites())
        .unwrap();
    expect(after.map((NewsRequiredSite s) => s.name).toList(), <String>[
      '甲',
      '丙',
    ]);
    expect(after.map((NewsRequiredSite s) => s.sortOrder).toList(), <int>[
      0,
      1,
    ], reason: '整体替换后顺序必须重新编号，不留空洞');
  });

  test('三个列表互不污染（同一张表按 kind 分开）', () async {
    await store.replaceList(NewsListCategory.keywords, <String>['甲', '乙']);
    await store.replaceList(NewsListCategory.blockedQueryTerms, <String>['禁一']);
    await store.replaceList(NewsListCategory.excludedTopics, <String>[
      '题一',
      '题二',
    ]);
    expect((await store.loadList(NewsListCategory.keywords)).unwrap(), <String>[
      '甲',
      '乙',
    ]);
    expect(
      (await store.loadList(NewsListCategory.blockedQueryTerms)).unwrap(),
      <String>['禁一'],
    );
    expect(
      (await store.loadList(NewsListCategory.excludedTopics)).unwrap(),
      <String>['题一', '题二'],
    );
  });

  test('替换一个列表不动另外两个（独立入口）', () async {
    await store.replaceList(NewsListCategory.keywords, <String>['原关键词']);
    await store.replaceList(NewsListCategory.blockedQueryTerms, <String>[
      '原禁词',
    ]);
    await store.replaceList(NewsListCategory.keywords, <String>['新关键词']);
    expect((await store.loadList(NewsListCategory.keywords)).unwrap(), <String>[
      '新关键词',
    ]);
    expect(
      (await store.loadList(NewsListCategory.blockedQueryTerms)).unwrap(),
      <String>['原禁词'],
      reason: '改关键词不得动禁词列表',
    );
  });

  test('未知列表类别被明确拒绝（不静默落到某一类）', () async {
    final Result<void> result = await store.replaceList('unknownKind', <String>[
      'x',
    ]);
    expect(result.isErr, isTrue);
    expect(result.errorOrNull, isA<ValidationError>());
  });

  test('prompt 版本只增不改：保存两次得到两行，旧版本可读回', () async {
    await store.savePromptVersion(
      NewsPromptVersion(
        version: 1,
        mode: NewsPromptMode.composed,
        taskInstruction: '第一版',
        outputSpec: '规范一',
        advancedPrompt: '',
        createdAt: DateTime.utc(2026, 9, 22, 1),
        language: NewsPromptLanguage.chinese,
      ),
    );
    await store.savePromptVersion(
      NewsPromptVersion(
        version: 2,
        mode: NewsPromptMode.advancedOverride,
        taskInstruction: '',
        outputSpec: '',
        advancedPrompt: '第二版覆盖',
        createdAt: DateTime.utc(2026, 9, 22, 2),
        language: NewsPromptLanguage.chinese,
        note: '试试高级模式',
      ),
    );
    final List<NewsPromptVersion> versions = (await store.loadPromptVersions(
      NewsPromptLanguage.chinese.code,
    )).unwrap();
    expect(versions, hasLength(2));
    expect(versions.first.version, 2, reason: '列表按版本号倒序');
    expect(versions.first.mode, NewsPromptMode.advancedOverride);
    expect(versions.first.advancedPrompt, '第二版覆盖');
    expect(versions.first.note, '试试高级模式');
    expect(versions.last.version, 1, reason: '旧版本仍在（可回退）');
    expect(versions.last.taskInstruction, '第一版');
  });

  test('中英两个语言的版本互不覆盖', () async {
    await store.savePromptVersion(
      NewsPromptVersion(
        version: 1,
        mode: NewsPromptMode.composed,
        taskInstruction: '中文任务',
        outputSpec: '',
        advancedPrompt: '',
        createdAt: DateTime.utc(2026, 9, 22),
        language: NewsPromptLanguage.chinese,
      ),
    );
    await store.savePromptVersion(
      NewsPromptVersion(
        version: 1,
        mode: NewsPromptMode.composed,
        taskInstruction: 'English task',
        outputSpec: '',
        advancedPrompt: '',
        createdAt: DateTime.utc(2026, 9, 22),
        language: NewsPromptLanguage.english,
      ),
    );
    expect(
      (await store.loadPromptVersions(NewsPromptLanguage.chinese.code))
          .unwrap()
          .single
          .taskInstruction,
      '中文任务',
    );
    expect(
      (await store.loadPromptVersions(NewsPromptLanguage.english.code))
          .unwrap()
          .single
          .taskInstruction,
      'English task',
    );
  });

  test('删除一个版本后其余仍在', () async {
    for (int version = 1; version <= 3; version++) {
      await store.savePromptVersion(
        NewsPromptVersion(
          version: version,
          mode: NewsPromptMode.composed,
          taskInstruction: 'v$version',
          outputSpec: '',
          advancedPrompt: '',
          createdAt: DateTime.utc(2026, 9, 22, version),
          language: NewsPromptLanguage.chinese,
        ),
      );
    }
    await store.deletePromptVersion(
      language: NewsPromptLanguage.chinese.code,
      version: 2,
    );
    final List<NewsPromptVersion> remaining = (await store.loadPromptVersions(
      NewsPromptLanguage.chinese.code,
    )).unwrap();
    expect(remaining.map((NewsPromptVersion v) => v.version).toList(), <int>[
      3,
      1,
    ]);
  });

  group('逐源新闻开关（SET-050 的 feeds.news_enabled）', () {
    test('默认 null（跟随），显式设置后可读回，且可退回跟随', () async {
      final DriftFeedCatalogStore feeds = DriftFeedCatalogStore(db);
      final int feedId = (await feeds.createFeed(
        const FeedInsert(
          syncId: 'feed.news',
          normalizedUrl: 'https://news.example.com/feed.xml',
          name: '新闻源',
        ),
      )).unwrap().id;
      // 新建时为 null：用户从未做过这个选择。
      expect((await feeds.findFeedById(feedId)).unwrap()!.newsEnabled, isNull);
      await feeds.setFeedNewsEnabled(feedId: feedId, newsEnabled: false);
      expect((await feeds.findFeedById(feedId)).unwrap()!.newsEnabled, isFalse);
      await feeds.setFeedNewsEnabled(feedId: feedId, newsEnabled: null);
      expect(
        (await feeds.findFeedById(feedId)).unwrap()!.newsEnabled,
        isNull,
        reason: '三态：必须能退回「跟随」',
      );
    });

    test('新闻开关不影响订阅刷新开关（两列独立）', () async {
      final DriftFeedCatalogStore feeds = DriftFeedCatalogStore(db);
      final int feedId = (await feeds.createFeed(
        const FeedInsert(
          syncId: 'feed.news2',
          normalizedUrl: 'https://news2.example.com/feed.xml',
          name: '新闻源二',
        ),
      )).unwrap().id;
      await feeds.setFeedNewsEnabled(feedId: feedId, newsEnabled: false);
      final FeedRecord record = (await feeds.findFeedById(feedId)).unwrap()!;
      expect(record.enabled, isTrue, reason: '排除新闻不得关掉刷新');
      expect(record.newsEnabled, isFalse);
    });
  });
}
