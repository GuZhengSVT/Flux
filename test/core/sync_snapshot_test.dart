// T043：快照的确定性与解析防御（架构 5.2 的「不可变快照」）。
//
// 为什么快照的编码必须**确定性**：T042 的快照是**内容寻址**的（名字 = 内容哈希），
// 而 T043 的幂等恢复判据正是「远端版本的内容哈希 == 本机当前内容」。编码一旦随插入
// 顺序或空白抖动，同一份内容就会得到两个哈希，「读回校验」与「按版本幂等确认」同时失效。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

SyncEntity _feed(String key, String name) => SyncEntity(
  kind: SyncEntityKind.feed,
  key: key,
  fields: <String, Object?>{
    'syncId': key,
    'name': name,
    'normalizedUrl': 'https://example.com/$key.xml',
  },
);

void main() {
  group('确定性编码', () {
    test('插入顺序不同、内容相同的两份快照编码逐字相同', () {
      final SyncSnapshot first = SyncSnapshot.of(
        entities: <SyncEntity>[_feed('feed.b', 'B'), _feed('feed.a', 'A')],
      );
      final SyncSnapshot second = SyncSnapshot.of(
        entities: <SyncEntity>[_feed('feed.a', 'A'), _feed('feed.b', 'B')],
      );
      expect(first.encode(), second.encode());
      expect(first.sameContentAs(second), isTrue);
      // 内容寻址的前提：同一内容 → 同一哈希。
      expect(
        snapshotContentHash(utf8.encode(first.encode())),
        snapshotContentHash(utf8.encode(second.encode())),
      );
    });

    test('字段插入顺序不同也编码相同（字段按名字排序）', () {
      final SyncSnapshot a = SyncSnapshot.of(
        entities: <SyncEntity>[
          const SyncEntity(
            kind: SyncEntityKind.feed,
            key: 'feed.x',
            fields: <String, Object?>{'name': 'X', 'syncId': 'feed.x'},
          ),
        ],
      );
      final SyncSnapshot b = SyncSnapshot.of(
        entities: <SyncEntity>[
          const SyncEntity(
            kind: SyncEntityKind.feed,
            key: 'feed.x',
            fields: <String, Object?>{'syncId': 'feed.x', 'name': 'X'},
          ),
        ],
      );
      expect(a.encode(), b.encode());
    });

    test('列表值的顺序**不**被排序（顺序是内容的一部分）', () {
      final SyncSnapshot a = SyncSnapshot.of(
        entities: <SyncEntity>[
          const SyncEntity(
            kind: SyncEntityKind.newsListEntry,
            key: NewsListCategory.keywords,
            fields: <String, Object?>{
              'values': <Object?>['第一', '第二'],
            },
          ),
        ],
      );
      final SyncSnapshot b = SyncSnapshot.of(
        entities: <SyncEntity>[
          const SyncEntity(
            kind: SyncEntityKind.newsListEntry,
            key: NewsListCategory.keywords,
            fields: <String, Object?>{
              'values': <Object?>['第二', '第一'],
            },
          ),
        ],
      );
      expect(a.sameContentAs(b), isFalse, reason: '顺序是用户给的，不能被规范化掉');
    });

    test('往返：编码→解析→再编码逐字相同', () {
      final SyncSnapshot original = SyncSnapshot.of(
        entities: <SyncEntity>[
          _feed('feed.a', 'A'),
          const SyncEntity(
            kind: SyncEntityKind.articleState,
            key: 'key-1',
            fields: <String, Object?>{
              'readingState': 'later',
              'favorite': true,
            },
          ),
        ],
        deletions: <SyncDeletion>[
          const SyncDeletion(
            kind: SyncEntityKind.feed,
            key: 'feed.gone',
            keepFavorites: true,
            displayName: '删掉的源',
          ),
        ],
      );
      final SyncSnapshot decoded = SyncSnapshot.decode(original.encode())!;
      expect(decoded.encode(), original.encode());
      expect(
        decoded.deletion(SyncEntityKind.feed, 'feed.gone')!.keepFavorites,
        isTrue,
      );
    });
  });

  group('解析防御（读不懂就返回 null，不当成「没有内容」）', () {
    test('非 JSON / 结构不符 / 协议更高版本都返回 null', () {
      expect(SyncSnapshot.decode('not json'), isNull);
      expect(SyncSnapshot.decode('[]'), isNull);
      expect(SyncSnapshot.decode('{}'), isNull);
      expect(
        SyncSnapshot.decode(
          '{"protocol":"flux-sync-99","entities":{},"deletions":[]}',
        ),
        isNull,
        reason: '更高协议版本不得按旧形状解读',
      );
    });

    test('实体字段不是对象、删除项缺字段都返回 null', () {
      expect(
        SyncSnapshot.decode(
          '{"entities":{"feed":{"k":"oops"}},"deletions":[]}',
        ),
        isNull,
      );
      expect(
        SyncSnapshot.decode('{"entities":{},"deletions":[{"key":"x"}]}'),
        isNull,
        reason: '缺 kind 的删除项无法定位',
      );
      expect(
        SyncSnapshot.decode(
          '{"entities":{},"deletions":[{"kind":"feed","key":"x","revision":"9"}]}',
        ),
        isNull,
        reason: 'revision 类型错',
      );
    });

    test('保留字段类型不符也算读不懂（keepFavorites 只能是布尔或缺失）', () {
      expect(
        SyncSnapshot.decode(
          '{"entities":{},"deletions":[{"kind":"feed","key":"x","keepFavorites":"yes"}]}',
        ),
        isNull,
      );
    });

    test('protocol 缺失被接受（向前兼容：只有**更高**版本才拒绝）', () {
      final SyncSnapshot? snapshot = SyncSnapshot.decode(
        '{"entities":{},"deletions":[]}',
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.isEmpty, isTrue);
    });

    test('空快照的编码可被解析，且 isEmpty 为真', () {
      expect(SyncSnapshot.empty.isEmpty, isTrue);
      expect(SyncSnapshot.decode(SyncSnapshot.empty.encode())!.isEmpty, isTrue);
    });
  });

  group('缺省字段与空值语义', () {
    test('缺失字段不进编码，显式 null 进编码（两者可区分）', () {
      final SyncSnapshot missing = SyncSnapshot.of(
        entities: <SyncEntity>[
          const SyncEntity(
            kind: SyncEntityKind.feed,
            key: 'feed.x',
            fields: <String, Object?>{'syncId': 'feed.x'},
          ),
        ],
      );
      final SyncSnapshot explicitNull = SyncSnapshot.of(
        entities: <SyncEntity>[
          const SyncEntity(
            kind: SyncEntityKind.feed,
            key: 'feed.x',
            fields: <String, Object?>{'syncId': 'feed.x', 'sourceName': null},
          ),
        ],
      );
      expect(missing.sameContentAs(explicitNull), isFalse);
      expect(
        SyncSnapshot.decode(missing.encode())!
            .entity(SyncEntityKind.feed, 'feed.x')!
            .hasField('sourceName'),
        isFalse,
      );
      expect(
        SyncSnapshot.decode(explicitNull.encode())!
            .entity(SyncEntityKind.feed, 'feed.x')!
            .hasField('sourceName'),
        isTrue,
      );
    });
  });

  group('版本 ↔ 快照文件名（内容寻址的派生关系）', () {
    test('由版本号能找到唯一快照文件名', () {
      final String hash = snapshotContentHash(utf8.encode('content'));
      final String name = snapshotFileName(hash);
      expect(
        snapshotNameForVersion(
          version: versionForSnapshot(hash),
          availableNames: <String>[name],
        ),
        name,
      );
    });

    test('找不到时返回 null（不猜一个文件名）', () {
      expect(
        snapshotNameForVersion(
          version: 'v-ffffffffffffffffffffffffffffffff',
          availableNames: <String>['snapshot-abcdef.json'],
        ),
        isNull,
      );
    });

    test('同一版本对应多个文件（异常情形）返回 null 而不是挑一个', () {
      expect(
        snapshotNameForVersion(
          version: 'v-abc',
          availableNames: <String>[
            'snapshot-abc1111111111111111111111111111.json',
            'snapshot-abc2222222222222222222222222222.json',
          ],
        ),
        isNull,
      );
    });
  });
}
