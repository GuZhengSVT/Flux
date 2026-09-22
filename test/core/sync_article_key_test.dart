// T041：跨设备文章同步键的确定性与订阅对齐（架构 5.2、手册 6.3「身份」节）。
//
// 三条被钉住的不变量：
//   1) **同输入同键**：两台设备算出同一个键（否则状态同步不到一起）；
//   2) **异输入异键**：源不同、证据类型不同、证据值不同都必须是不同的键；
//   3) **无身份不给键**：三个证据都缺失时返回 null 而不是编一个键。
//
// 全部是纯函数断言，不连库、不连网、不需要两台设备就能验证「两台设备会对齐」。
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

const String _feedA = 'feed.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _feedB = 'feed.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  group('稳定文章键的确定性', () {
    test('同输入同键：两台设备（同源同 GUID）算出同一个键', () {
      final String? deviceOne = syncArticleKey(
        feedSyncId: _feedA,
        guid: 'post-1234',
        normalizedLink: 'https://a.example.com/p/1',
      );
      final String? deviceTwo = syncArticleKey(
        feedSyncId: _feedA,
        guid: 'post-1234',
        normalizedLink: 'https://a.example.com/p/1',
      );
      expect(deviceOne, isNotNull);
      expect(deviceOne, deviceTwo);
      expect(deviceOne!.length, syncArticleKeyLength);
    });

    test('键只由「源 + 证据」决定：同一证据重复计算恒等', () {
      final String? first = syncArticleKey(
        feedSyncId: _feedA,
        normalizedLink: 'https://a.example.com/p/2',
      );
      for (int i = 0; i < 5; i++) {
        expect(
          syncArticleKey(
            feedSyncId: _feedA,
            normalizedLink: 'https://a.example.com/p/2',
          ),
          first,
        );
      }
    });

    test('异源同 GUID 是**不同的键**（很多源用同一套模板生成 GUID）', () {
      final String? fromA = syncArticleKey(
        feedSyncId: _feedA,
        guid: 'same-guid',
      );
      final String? fromB = syncArticleKey(
        feedSyncId: _feedB,
        guid: 'same-guid',
      );
      expect(fromA, isNot(fromB));
    });

    test('异 GUID 是异键', () {
      expect(
        syncArticleKey(feedSyncId: _feedA, guid: 'g1'),
        isNot(syncArticleKey(feedSyncId: _feedA, guid: 'g2')),
      );
    });

    test('**类型标记**参与摘要：GUID 与链接恰好同串时也不撞键', () {
      final String? asGuid = syncArticleKey(feedSyncId: _feedA, guid: 'abc');
      final String? asLink = syncArticleKey(
        feedSyncId: _feedA,
        normalizedLink: 'abc',
      );
      expect(asGuid, isNot(asLink), reason: '不同可靠度的身份证据不得算出同一个键');
    });

    test('优先顺序与架构 4.1 一致：GUID 优先于链接，链接优先于指纹', () {
      final String? fromGuid = syncArticleKeyFor(
        feedSyncId: _feedA,
        basis: IdentityBasis.guid,
        guid: 'g',
      );
      final String? fromLink = syncArticleKeyFor(
        feedSyncId: _feedA,
        basis: IdentityBasis.normalizedLink,
        normalizedLink: 'g',
      );
      expect(fromGuid, isNot(fromLink));
      expect(
        syncArticleKeyFor(
          feedSyncId: _feedA,
          basis: IdentityBasis.guid,
          guid: 'g',
          normalizedLink: 'l',
        ),
        fromGuid,
        reason: '有 GUID 时不看链接（与 identityBasis 的判定顺序一致）',
      );
    });

    test('兜底指纹的可靠度参与摘要（不可靠身份在键空间里可见）', () {
      final String? reliable = syncArticleKeyFor(
        feedSyncId: _feedA,
        basis: IdentityBasis.fingerprint,
        fallbackFingerprint: 'fp-1',
        reliability: FingerprintReliability.reliable,
      );
      final String? unreliable = syncArticleKeyFor(
        feedSyncId: _feedA,
        basis: IdentityBasis.fingerprint,
        fallbackFingerprint: 'fp-1',
        reliability: FingerprintReliability.unreliable,
      );
      expect(reliable, isNotNull);
      expect(reliable, isNot(unreliable));
    });

    test('三个证据都缺失时不给键（不编一个键让无关文章互相覆盖状态）', () {
      expect(syncArticleKey(feedSyncId: _feedA), isNull);
      expect(
        syncArticleKey(feedSyncId: _feedA, guid: '   ', normalizedLink: ''),
        isNull,
        reason: '空白证据等于没有证据',
      );
      expect(
        syncArticleKeyFor(feedSyncId: _feedA, basis: IdentityBasis.remote),
        isNull,
        reason: '占位行的键由远端键承接，不由本机推导',
      );
    });

    test('证据两端空白不改变键（同一篇文章的标题风格差异不该分成两篇）', () {
      expect(
        syncArticleKey(feedSyncId: _feedA, guid: '  post-1  '),
        syncArticleKey(feedSyncId: _feedA, guid: 'post-1'),
      );
    });

    test('键是十六进制摘要，不含源标识原文（快照里不泄露本机数据）', () {
      final String key = syncArticleKey(feedSyncId: _feedA, guid: 'post-1')!;
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(key), isTrue, reason: key);
      expect(key, isNot(contains('feed.')));
      expect(key, isNot(contains('post-1')));
    });
  });

  group('占位行（远端状态到达但本机没有正文）', () {
    test('本机没有该行 → 建占位行；本机已有 → 只应用状态', () {
      expect(
        planRemoteStateArrival(hasLocalRow: false),
        SyncRemoteStateAction.createPlaceholder,
      );
      expect(
        planRemoteStateArrival(hasLocalRow: true),
        SyncRemoteStateAction.applyStateOnly,
      );
    });

    test('占位键由远端键与订阅 syncId 派生，同输入同键', () {
      final String a = syncPlaceholderKey(feedSyncId: _feedA, remoteKey: 'r1');
      final String b = syncPlaceholderKey(feedSyncId: _feedA, remoteKey: 'r1');
      expect(a, b);
      expect(a, isNot(syncPlaceholderKey(feedSyncId: _feedB, remoteKey: 'r1')));
      expect(a, isNot(syncPlaceholderKey(feedSyncId: _feedA, remoteKey: 'r2')));
    });

    test('占位行只是占位：它的键与 GUID/链接/指纹键空间不同', () {
      final String placeholder = syncPlaceholderKey(
        feedSyncId: _feedA,
        remoteKey: 'r1',
      );
      for (final String? other in <String?>[
        syncArticleKey(feedSyncId: _feedA, guid: 'r1'),
        syncArticleKey(feedSyncId: _feedA, normalizedLink: 'r1'),
        syncArticleKey(feedSyncId: _feedA, fallbackFingerprint: 'r1'),
      ]) {
        expect(placeholder, isNot(other));
      }
    });

    test('抓取补上身份：remote 只能升级为真实依据，绝不反向', () {
      expect(
        upgradedIdentityBasis(current: IdentityBasis.remote, guid: 'g-1'),
        IdentityBasis.guid,
      );
      expect(
        upgradedIdentityBasis(
          current: IdentityBasis.remote,
          normalizedLink: 'https://a.example.com/p/1',
        ),
        IdentityBasis.normalizedLink,
      );
      expect(
        upgradedIdentityBasis(
          current: IdentityBasis.remote,
          fallbackFingerprint: 'fp-1',
        ),
        IdentityBasis.fingerprint,
      );
      expect(
        upgradedIdentityBasis(current: IdentityBasis.remote),
        isNull,
        reason: '这次抓取没有带来证据：保持原样（仍显示正文未同步）',
      );
      for (final IdentityBasis current in <IdentityBasis>[
        IdentityBasis.guid,
        IdentityBasis.normalizedLink,
        IdentityBasis.fingerprint,
      ]) {
        expect(
          upgradedIdentityBasis(
            current: current,
            normalizedLink: 'https://a.example.com/p/1',
          ),
          isNull,
          reason: '真实依据不退回 remote：${current.name}',
        );
      }
    });
  });

  group('订阅对齐（两台设备独立导入同一源）', () {
    test('syncId 相等即对齐（优先于 URL 匹配）', () {
      final List<FeedAlignment> alignments = alignFeeds(
        remote: <SyncFeedCandidate>[
          const SyncFeedCandidate(
            syncId: _feedA,
            normalizedUrl: 'https://a.example.com/feed.xml',
          ),
        ],
        local: <SyncFeedCandidate>[
          const SyncFeedCandidate(
            syncId: _feedA,
            normalizedUrl: 'https://a.example.com/feed.xml?x=1',
            localFeedId: 7,
          ),
        ],
      );
      expect(alignments.length, 1);
      expect(alignments.single.localFeedId, 7);
      expect(
        alignments.single.matchedByNormalizedUrl,
        isFalse,
        reason: 'syncId 相等时不算 URL 匹配，因此不需要写别名',
      );
    });
    test('syncId 不同但规范化 URL 相同 → 对齐并产生别名', () {
      final List<FeedAlignment> alignments = alignFeeds(
        remote: <SyncFeedCandidate>[
          const SyncFeedCandidate(
            syncId: _feedB,
            normalizedUrl: 'https://a.example.com/feed.xml',
          ),
        ],
        local: <SyncFeedCandidate>[
          const SyncFeedCandidate(
            syncId: _feedA,
            normalizedUrl: 'https://a.example.com/feed.xml',
            localFeedId: 3,
          ),
        ],
      );
      expect(alignments.length, 1);
      expect(alignments.single.localFeedId, 3);
      expect(alignments.single.matchedByNormalizedUrl, isTrue);
      expect(alignments.single.createsAlias, isTrue);
    });

    test('URL 有歧义（本机重复添加过同一地址）时不对齐，而不是挑一个', () {
      final List<FeedAlignment> alignments = alignFeeds(
        remote: <SyncFeedCandidate>[
          const SyncFeedCandidate(
            syncId: _feedB,
            normalizedUrl: 'https://dup.example.com/feed.xml',
          ),
        ],
        local: <SyncFeedCandidate>[
          const SyncFeedCandidate(
            syncId: _feedA,
            normalizedUrl: 'https://dup.example.com/feed.xml',
            localFeedId: 1,
          ),
          const SyncFeedCandidate(
            syncId: 'feed.cccccccccccccccccccccccccccccccc',
            normalizedUrl: 'https://dup.example.com/feed.xml',
            localFeedId: 2,
          ),
        ],
      );
      expect(alignments, isEmpty, reason: '两条本机订阅都可能匹配：挑一个会把远端状态写进错误的订阅');
    });

    test('一条本机订阅只被对齐一次（远端两条指向同一本机订阅）', () {
      final List<FeedAlignment> alignments = alignFeeds(
        remote: <SyncFeedCandidate>[
          const SyncFeedCandidate(
            syncId: _feedB,
            normalizedUrl: 'https://a.example.com/feed.xml',
          ),
          const SyncFeedCandidate(
            syncId: 'feed.cccccccccccccccccccccccccccccccc',
            normalizedUrl: 'https://a.example.com/feed.xml',
          ),
        ],
        local: <SyncFeedCandidate>[
          const SyncFeedCandidate(
            syncId: _feedA,
            normalizedUrl: 'https://a.example.com/feed.xml',
            localFeedId: 5,
          ),
        ],
      );
      expect(alignments.length, 1);
      expect(alignments.single.localFeedId, 5);
    });

    test('不存在的源不对齐（返回空而不是凭空配对）', () {
      expect(
        alignFeeds(
          remote: <SyncFeedCandidate>[
            const SyncFeedCandidate(
              syncId: _feedB,
              normalizedUrl: 'https://nowhere.example.com/feed.xml',
            ),
          ],
          local: <SyncFeedCandidate>[
            const SyncFeedCandidate(
              syncId: _feedA,
              normalizedUrl: 'https://a.example.com/feed.xml',
              localFeedId: 1,
            ),
          ],
        ),
        isEmpty,
      );
    });

    test('别名只在 URL 匹配时产生，且已存在的不重复写', () {
      const List<FeedAlignment> alignments = <FeedAlignment>[
        FeedAlignment(
          remoteSyncId: _feedB,
          localFeedId: 3,
          matchedByNormalizedUrl: true,
        ),
        FeedAlignment(
          remoteSyncId: _feedA,
          localFeedId: 9,
          matchedByNormalizedUrl: false,
        ),
      ];
      final List<SyncFeedAlias> first = aliasesToPersist(
        alignments: alignments,
        existing: const <SyncFeedAlias>[],
      );
      expect(first.length, 1, reason: 'syncId 相等的对齐不需要别名');
      expect(first.single.syncId, _feedB);
      expect(first.single.localFeedId, 3);

      final List<SyncFeedAlias> second = aliasesToPersist(
        alignments: alignments,
        existing: first,
      );
      expect(second, isEmpty, reason: '同一条别名不重复写');
    });

    test('别名表双向查询可用（两端各自认得出对方）', () {
      const List<SyncFeedAlias> aliases = <SyncFeedAlias>[
        SyncFeedAlias(syncId: _feedB, localFeedId: 3),
      ];
      expect(localFeedIdForSyncId(syncId: _feedB, aliases: aliases), 3);
      expect(syncIdForLocalFeedId(localFeedId: 3, aliases: aliases), _feedB);
      expect(localFeedIdForSyncId(syncId: _feedA, aliases: aliases), isNull);
      expect(syncIdForLocalFeedId(localFeedId: 4, aliases: aliases), isNull);
    });
  });

  group('私密订阅地址的拆分（SET-027、架构 5.2）', () {
    test('秘密参数被剥离、留在本机凭据引用里，其他设备需要补填', () {
      final SyncFeedUrlPlan plan = planSyncFeedUrl(
        rawUrl:
            'https://private.example.com/feed.xml?token=SECRETVALUE&format=rss',
        feedSyncId: _feedA,
      );
      expect(plan.syncableUrl, isNot(contains('SECRETVALUE')));
      expect(plan.syncableUrl, isNot(contains('token')));
      expect(plan.syncableUrl, contains('format=rss'), reason: '非秘密参数必须保留');
      expect(plan.strippedParams, contains('token'));
      expect(plan.needsCredentialPrompt, isTrue);
      expect(plan.credentialRef, contains(_feedA));
      expect(
        plan.credentialRef,
        isNot(contains('SECRETVALUE')),
        reason: '凭据引用只带定位键，不带值',
      );
    });

    test('userinfo 里的账号密码同样被剥离（不在查询串里）', () {
      final SyncFeedUrlPlan plan = planSyncFeedUrl(
        rawUrl: 'https://user:pass@private.example.com/feed.xml',
        feedSyncId: _feedA,
      );
      expect(plan.syncableUrl, isNot(contains('pass')));
      expect(plan.syncableUrl, isNot(contains('user')));
      expect(plan.strippedParams, contains(userInfoSecretParam));
      expect(plan.needsCredentialPrompt, isTrue);
    });

    test('公开源不需要补填凭据（不提示用户去填一个不存在的 token）', () {
      final SyncFeedUrlPlan plan = planSyncFeedUrl(
        rawUrl: 'https://public.example.com/feed.xml?cat=tech',
        feedSyncId: _feedA,
      );
      expect(plan.syncableUrl, 'https://public.example.com/feed.xml?cat=tech');
      expect(plan.strippedParams, isEmpty);
      expect(plan.needsCredentialPrompt, isFalse);
    });

    test('凭据引用按订阅区分（同类别不同源不互相覆盖）', () {
      final SyncFeedUrlPlan a = planSyncFeedUrl(
        rawUrl: 'https://a.example.com/feed.xml?token=x',
        feedSyncId: _feedA,
      );
      final SyncFeedUrlPlan b = planSyncFeedUrl(
        rawUrl: 'https://b.example.com/feed.xml?token=y',
        feedSyncId: _feedB,
      );
      expect(a.credentialRef, isNot(b.credentialRef));
      expect(a.credentialRef, startsWith('$feedAuthCredentialCategory:'));
    });
  });
}
