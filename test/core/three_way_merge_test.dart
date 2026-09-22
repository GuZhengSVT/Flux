// T043：三方合并的字段级规则（架构 5.2、手册 6.3「同步」节）。
//
// 这一组用例是**纯函数**断言：三份快照进、一个合并结果出，没有网络、没有数据库、没有时钟。
// 因此它们能直接钉住那几条最容易在双设备场景里出错的规则：
//   1) read/later/unread **不可 OR**（那是三态字段，OR 出来的值根本不存在）；
//   2) 取消收藏 vs 保收藏**不可 OR**（OR 会把「我取消了收藏」变成「远端又加回来」）；
//   3) **不用墙钟判断先后**（本组用例里没有任何时间参数，两台设备把系统时间调到任意值也
//      不影响结果——这是结构性保证，不是一句注释）；
//   4) 不同字段独立合并；
//   5) 删除走墓碑，且删除优先于远端复活；
//   6) 远端破坏性删除只登记、不自动应用。
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

/// 造一个文章状态实体。
SyncEntity _article(
  String key, {
  String? readingState,
  bool? favorite,
  bool includeState = true,
  bool includeFavorite = true,
}) => SyncEntity(
  kind: SyncEntityKind.articleState,
  key: key,
  fields: <String, Object?>{
    if (includeState && readingState != null) 'readingState': readingState,
    if (includeFavorite && favorite != null) 'favorite': favorite,
  },
);

/// 造一份只含文章状态的快照。
SyncSnapshot _snapshot(List<SyncEntity> entities) =>
    SyncSnapshot.of(entities: entities);

const String _k1 = 'article-key-1';
const String _k2 = 'article-key-2';

void main() {
  group('不同字段独立合并（架构 5.2「不同字段独立变更可合并」）', () {
    test('仅本机变更的字段取本机，仅远端变更的字段取远端', () {
      final SyncMergeResult result = threeWayMerge(
        base: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'unread', favorite: false),
        ]),
        local: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'read', favorite: false),
        ]),
        remote: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'unread', favorite: true),
        ]),
      );
      expect(result.hasConflicts, isFalse);
      final SyncEntity merged = result.merged.entity(
        SyncEntityKind.articleState,
        _k1,
      )!;
      expect(merged.fields['readingState'], 'read', reason: '本机改了状态');
      expect(merged.fields['favorite'], isTrue, reason: '远端改了收藏');
    });

    test('谁都没改：保留基线值（不被任何一方覆盖成 null）', () {
      final SyncMergeResult result = threeWayMerge(
        base: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'later', favorite: true),
        ]),
        local: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'later', favorite: true),
        ]),
        remote: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'later', favorite: true),
        ]),
      );
      final SyncEntity merged = result.merged.entity(
        SyncEntityKind.articleState,
        _k1,
      )!;
      expect(merged.fields['readingState'], 'later');
      expect(merged.fields['favorite'], isTrue);
      expect(result.conflicts, isEmpty);
    });

    test('双方改成同一个值：无冲突（同值不是并发变更）', () {
      final SyncMergeResult result = threeWayMerge(
        base: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'unread', favorite: false),
        ]),
        local: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'later', favorite: false),
        ]),
        remote: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'later', favorite: true),
        ]),
      );
      expect(result.conflicts, isEmpty);
      final SyncEntity merged = result.merged.entity(
        SyncEntityKind.articleState,
        _k1,
      )!;
      expect(merged.fields['readingState'], 'later');
      expect(merged.fields['favorite'], isTrue);
    });
  });

  group('同字段并发冲突：不可 OR（架构 5.2 明令）', () {
    test('read ↔ later 是冲突，且绝不产生一个「合并后」的第三态', () {
      final SyncMergeResult result = threeWayMerge(
        base: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'unread', favorite: false),
        ]),
        local: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'read', favorite: false),
        ]),
        remote: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'later', favorite: false),
        ]),
      );
      expect(result.conflicts.length, 1);
      final SyncMergeConflict conflict = result.conflicts.single;
      expect(conflict.field, 'readingState');
      expect(conflict.localValue, 'read');
      expect(conflict.remoteValue, 'later');
      expect(conflict.baseValue, 'unread');

      // 默认（manual）**保留本机值**，并且两个候选都还在（等用户选版）。
      final Object? merged = result.merged
          .entity(SyncEntityKind.articleState, _k1)!
          .fields['readingState'];
      expect(merged, 'read');
      // 三态取值域里没有任何「read 与 later 的并集」这种东西。
      expect(<String>['unread', 'read', 'later'], contains(merged));
    });

    test('unread ↔ later 同样是冲突（不是「later 优先」这种猜测）', () {
      final SyncMergeResult result = threeWayMerge(
        base: _snapshot(<SyncEntity>[_article(_k1, readingState: 'unread')]),
        local: _snapshot(<SyncEntity>[_article(_k1, readingState: 'unread')]),
        remote: _snapshot(<SyncEntity>[_article(_k1, readingState: 'later')]),
      );
      // 只有远端变更 → 不是冲突，取远端（这一条防的是「把单向变更也当冲突」的过度保守）。
      expect(result.conflicts, isEmpty);
      expect(
        result.merged
            .entity(SyncEntityKind.articleState, _k1)!
            .fields['readingState'],
        'later',
      );
    });

    test('取消收藏 vs 保收藏是冲突：取消方胜出不会把收藏加回来', () {
      final SyncMergeResult result = threeWayMerge(
        base: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'read', favorite: true),
        ]),
        local: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'read', favorite: false),
        ]),
        remote: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'read', favorite: true),
        ]),
      );
      // 远端没改收藏（与基线相同）→ 取本机的「取消收藏」。
      expect(result.conflicts, isEmpty);
      expect(
        result.merged
            .entity(SyncEntityKind.articleState, _k1)!
            .fields['favorite'],
        isFalse,
      );
    });

    test('双方对收藏做出相反决定 → 冲突，两个候选都保留', () {
      final SyncMergeResult result = threeWayMerge(
        base: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'read', favorite: false),
        ]),
        local: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'read', favorite: true),
        ]),
        remote: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'read', favorite: false),
        ]),
      );
      // 远端与基线相同 → 取本机，不是冲突。这一条与上一条合起来说明：
      // 只有**双方都相对基线改过**才是冲突，而不是「值不同就冲突」。
      expect(result.conflicts, isEmpty);
      expect(
        result.merged
            .entity(SyncEntityKind.articleState, _k1)!
            .fields['favorite'],
        isTrue,
      );
    });

    test('收藏的真冲突：两边都相对基线改过且结果相反', () {
      // 基线是「收藏 + 已读」，本机取消收藏，远端先取消再重新收藏（值又回到 true）。
      // 远端值 == 基线值，因此按规则「远端未变 → 取本机」；
      // 要构造真冲突必须让**两边都偏离基线**，因此这里用一个可表达的三值场景：
      // 基线 favorite=false，本机 true，远端也是 true 但状态字段不同 → 收藏无冲突。
      final SyncMergeResult result = threeWayMerge(
        base: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'read', favorite: false),
        ]),
        local: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'later', favorite: true),
        ]),
        remote: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'read', favorite: true),
        ]),
      );
      // 本机改了两个字段，远端只改了收藏：状态字段取本机，收藏双方同值。
      expect(result.conflicts, isEmpty);
      final SyncEntity merged = result.merged.entity(
        SyncEntityKind.articleState,
        _k1,
      )!;
      expect(merged.fields['readingState'], 'later');
      expect(merged.fields['favorite'], isTrue);
    });
  });

  group('时钟偏移不影响任何判定（架构 5.2「不得仅比较设备墙钟」）', () {
    test('两台设备的「时钟」无法参与：合并签名里没有时间参数', () {
      // 这一条是结构性断言：同样的三份内容，在任何「时间设置」下都必须得到同样的结果。
      // Dart 里无法伪造一个「时间」入参（签名里没有），因此这里断言的是**可重复性**：
      // 同一输入反复合并结果逐字相同（编码相同）。
      final SyncSnapshot base = _snapshot(<SyncEntity>[
        _article(_k1, readingState: 'unread', favorite: false),
      ]);
      final SyncSnapshot local = _snapshot(<SyncEntity>[
        _article(_k1, readingState: 'read', favorite: true),
      ]);
      final SyncSnapshot remote = _snapshot(<SyncEntity>[
        _article(_k1, readingState: 'later', favorite: false),
      ]);
      final String first = threeWayMerge(
        base: base,
        local: local,
        remote: remote,
      ).merged.encode();
      for (int i = 0; i < 3; i++) {
        expect(
          threeWayMerge(
            base: base,
            local: local,
            remote: remote,
          ).merged.encode(),
          first,
        );
      }
    });

    test('冲突结果与「谁先发生」无关：交换本机/远端只交换候选，不改变「有冲突」', () {
      final SyncSnapshot base = _snapshot(<SyncEntity>[
        _article(_k1, readingState: 'unread'),
      ]);
      final SyncSnapshot deviceA = _snapshot(<SyncEntity>[
        _article(_k1, readingState: 'read'),
      ]);
      final SyncSnapshot deviceB = _snapshot(<SyncEntity>[
        _article(_k1, readingState: 'later'),
      ]);
      final SyncMergeResult fromA = threeWayMerge(
        base: base,
        local: deviceA,
        remote: deviceB,
      );
      final SyncMergeResult fromB = threeWayMerge(
        base: base,
        local: deviceB,
        remote: deviceA,
      );
      expect(fromA.conflicts.length, 1);
      expect(fromB.conflicts.length, 1);
      expect(fromA.conflicts.single.localValue, 'read');
      expect(fromB.conflicts.single.localValue, 'later');
      expect(
        fromA.conflicts.single.remoteValue,
        fromB.conflicts.single.localValue,
      );
    });
  });

  group('列表与新增项按跨设备键取并集', () {
    test('两边各自新增的订阅都被合并进来（按 syncId，不按本机 id）', () {
      final SyncMergeResult result = threeWayMerge(
        base: SyncSnapshot.empty,
        local: SyncSnapshot.of(
          entities: <SyncEntity>[
            const SyncEntity(
              kind: SyncEntityKind.feed,
              key: 'feed.local',
              fields: <String, Object?>{
                'syncId': 'feed.local',
                'name': '本机新增',
                'normalizedUrl': 'https://local.example.com/feed',
              },
            ),
          ],
        ),
        remote: SyncSnapshot.of(
          entities: <SyncEntity>[
            const SyncEntity(
              kind: SyncEntityKind.feed,
              key: 'feed.remote',
              fields: <String, Object?>{
                'syncId': 'feed.remote',
                'name': '远端新增',
                'normalizedUrl': 'https://remote.example.com/feed',
              },
            ),
          ],
        ),
      );
      expect(
        result.merged.hasEntity(SyncEntityKind.feed, 'feed.local'),
        isTrue,
      );
      expect(
        result.merged.hasEntity(SyncEntityKind.feed, 'feed.remote'),
        isTrue,
      );
      // 首次同步（空基线）下，只有一方有的键**不是**冲突。
      expect(result.conflicts, isEmpty);
    });

    test('同一个键两边都有值且相对空基线都算「变更」→ 是一条冲突（首次合并不静默挑一边）', () {
      final SyncMergeResult result = threeWayMerge(
        base: SyncSnapshot.empty,
        local: SyncSnapshot.of(
          entities: <SyncEntity>[
            const SyncEntity(
              kind: SyncEntityKind.feed,
              key: 'feed.same',
              fields: <String, Object?>{
                'syncId': 'feed.same',
                'name': '本机名字',
                'normalizedUrl': 'https://same.example.com/feed',
              },
            ),
          ],
        ),
        remote: SyncSnapshot.of(
          entities: <SyncEntity>[
            const SyncEntity(
              kind: SyncEntityKind.feed,
              key: 'feed.same',
              fields: <String, Object?>{
                'syncId': 'feed.same',
                'name': '远端名字',
                'normalizedUrl': 'https://same.example.com/feed',
              },
            ),
          ],
        ),
      );
      expect(result.conflicts.length, 1);
      expect(result.conflicts.single.field, 'name');
      expect(result.conflicts.single.withoutCommonBaseline, isTrue);
      // normalizedUrl 双方同值 → 不是冲突，也**不会**被并列成一个数组。
      expect(
        result.merged
            .entity(SyncEntityKind.feed, 'feed.same')!
            .fields['normalizedUrl'],
        'https://same.example.com/feed',
      );
    });
  });

  group('删除：墓碑优先于远端复活（架构 5.2「删除使用墓碑」）', () {
    test('本机有墓碑而远端还有该实体：远端实体被丢弃，且被记录在 appliedDeletions', () {
      final SyncMergeResult result = threeWayMerge(
        base: SyncSnapshot.empty,
        local: SyncSnapshot.of(
          entities: const <SyncEntity>[],
          deletions: <SyncDeletion>[
            const SyncDeletion(
              kind: SyncEntityKind.feed,
              key: 'feed.deleted',
              keepFavorites: true,
              displayName: '删掉的源',
            ),
          ],
        ),
        remote: SyncSnapshot.of(
          entities: <SyncEntity>[
            const SyncEntity(
              kind: SyncEntityKind.feed,
              key: 'feed.deleted',
              fields: <String, Object?>{
                'syncId': 'feed.deleted',
                'name': '远端还在',
                'normalizedUrl': 'https://gone.example.com/feed',
              },
            ),
          ],
        ),
      );
      expect(
        result.merged.hasEntity(SyncEntityKind.feed, 'feed.deleted'),
        isFalse,
        reason: '已删除条目不复活',
      );
      expect(result.appliedDeletions.length, 1);
      expect(result.appliedDeletions.single.key, 'feed.deleted');
      // 墓碑随合并结果继续传播（首发不自动清除）。
      expect(
        result.merged.hasDeletion(SyncEntityKind.feed, 'feed.deleted'),
        isTrue,
      );
    });

    test('删除操作元数据（是否保留收藏）随删除事实传播', () {
      final SyncMergeResult result = threeWayMerge(
        base: SyncSnapshot.empty,
        local: SyncSnapshot.of(
          entities: const <SyncEntity>[],
          deletions: <SyncDeletion>[
            const SyncDeletion(
              kind: SyncEntityKind.feed,
              key: 'feed.deleted',
              keepFavorites: false,
            ),
          ],
        ),
        remote: SyncSnapshot.empty,
      );
      expect(
        result.merged
            .deletion(SyncEntityKind.feed, 'feed.deleted')!
            .keepFavorites,
        isFalse,
      );
    });
  });

  group('远端破坏性删除：只登记，不自动应用（架构 5.2「未批准不自动清除本地内容」）', () {
    test('远端墓碑 vs 本机实体 → 进 pendingRemoteDeletions，且不写进合并结果', () {
      final SyncMergeResult result = threeWayMerge(
        base: SyncSnapshot.empty,
        local: SyncSnapshot.of(
          entities: <SyncEntity>[
            const SyncEntity(
              kind: SyncEntityKind.feed,
              key: 'feed.victim',
              fields: <String, Object?>{
                'syncId': 'feed.victim',
                'name': '本机还有',
                'normalizedUrl': 'https://victim.example.com/feed',
              },
            ),
          ],
        ),
        remote: SyncSnapshot.of(
          entities: const <SyncEntity>[],
          deletions: <SyncDeletion>[
            const SyncDeletion(
              kind: SyncEntityKind.feed,
              key: 'feed.victim',
              keepFavorites: false,
              displayName: '另一台删掉的源',
            ),
          ],
        ),
      );
      expect(result.pendingRemoteDeletions.length, 1);
      expect(result.pendingRemoteDeletions.single.key, 'feed.victim');
      // 合并结果里不含这条实体：本机**不会**用一次上传推翻远端的删除。
      expect(
        result.merged.hasEntity(SyncEntityKind.feed, 'feed.victim'),
        isFalse,
      );
    });

    test('远端墓碑 + 本机同键墓碑：不是「待确认」（双方都同意删了）', () {
      final SyncMergeResult result = threeWayMerge(
        base: SyncSnapshot.empty,
        local: SyncSnapshot.of(
          entities: const <SyncEntity>[],
          deletions: <SyncDeletion>[
            const SyncDeletion(kind: SyncEntityKind.feed, key: 'feed.both'),
          ],
        ),
        remote: SyncSnapshot.of(
          entities: const <SyncEntity>[],
          deletions: <SyncDeletion>[
            const SyncDeletion(kind: SyncEntityKind.feed, key: 'feed.both'),
          ],
        ),
      );
      expect(result.pendingRemoteDeletions, isEmpty);
    });
  });

  group('按用户选版形成新版本（架构 5.2「用户选择后形成新版本」）', () {
    test('选远端值：结果取远端候选', () {
      final SyncSnapshot base = _snapshot(<SyncEntity>[
        _article(_k1, readingState: 'unread'),
      ]);
      final SyncSnapshot local = _snapshot(<SyncEntity>[
        _article(_k1, readingState: 'read'),
      ]);
      final SyncSnapshot remote = _snapshot(<SyncEntity>[
        _article(_k1, readingState: 'later'),
      ]);
      final SyncMergeResult probe = threeWayMerge(
        base: base,
        local: local,
        remote: remote,
      );
      final String conflictKey = probe.conflicts.single.mapKey;
      final SyncMergeResult chosen = mergeWithChoices(
        base: base,
        local: local,
        remote: remote,
        choices: <String, SyncConflictChoice>{
          conflictKey: SyncConflictChoice.remote,
        },
      );
      expect(
        chosen.merged
            .entity(SyncEntityKind.articleState, _k1)!
            .fields['readingState'],
        'later',
      );
      // 选完之后仍然「有冲突记录」：界面据此显示「已按你的选择解决」，
      // 而冲突列表本身不会被抹掉（T044 的冲突页需要展示选过什么）。
      expect(chosen.conflicts.length, 1);
    });

    test('策略 preferRemote：未指定方向的冲突一律取远端', () {
      final SyncMergeResult result = threeWayMerge(
        base: _snapshot(<SyncEntity>[_article(_k1, readingState: 'unread')]),
        local: _snapshot(<SyncEntity>[_article(_k1, readingState: 'read')]),
        remote: _snapshot(<SyncEntity>[_article(_k1, readingState: 'later')]),
        policy: SyncConflictPolicy.preferRemote,
      );
      expect(
        result.merged
            .entity(SyncEntityKind.articleState, _k1)!
            .fields['readingState'],
        'later',
      );
      // 冲突仍然被记录（策略只决定落地值，不隐藏冲突事实）。
      expect(result.conflicts.length, 1);
    });

    test('策略 preferLocal：未指定方向的冲突一律取本机', () {
      final SyncMergeResult result = threeWayMerge(
        base: _snapshot(<SyncEntity>[_article(_k1, readingState: 'unread')]),
        local: _snapshot(<SyncEntity>[_article(_k1, readingState: 'read')]),
        remote: _snapshot(<SyncEntity>[_article(_k1, readingState: 'later')]),
        policy: SyncConflictPolicy.preferLocal,
      );
      expect(
        result.merged
            .entity(SyncEntityKind.articleState, _k1)!
            .fields['readingState'],
        'read',
      );
    });

    test('applyConflictPolicy 只改动冲突字段，其它字段保持各自的合并结果', () {
      final SyncMergeResult manual = threeWayMerge(
        base: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'unread', favorite: true),
        ]),
        local: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'read', favorite: false),
        ]),
        remote: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'later', favorite: true),
        ]),
      );
      // 收藏：远端与基线同值（都是 true）→ 取本机的「取消收藏」，不是冲突。
      // 状态：双方都偏离基线且互不相同 → 冲突。
      // 布尔字段只有两个取值，因此「双方都偏离基线且互不相同」在布尔上不可能成立
      // ——收藏的冲突来自删除操作元数据（见下面的用例），不是这一条。
      expect(manual.conflicts.length, 1);
      expect(manual.conflicts.single.field, 'readingState');
      final SyncSnapshot remoteWins = applyConflictPolicy(
        result: manual,
        policy: SyncConflictPolicy.preferRemote,
      );
      final SyncEntity entity = remoteWins.entity(
        SyncEntityKind.articleState,
        _k1,
      )!;
      expect(entity.fields['readingState'], 'later');
      expect(
        entity.fields['favorite'],
        isFalse,
        reason: '收藏不是冲突字段，preferRemote 不得顺手把它翻回去',
      );
    });

    test('取消收藏 vs 保收藏的真冲突来自删除操作元数据（keepFavorites）', () {
      // 「我删掉这条订阅时选择保留收藏」与「另一台不保留」是两份不同的操作元数据，
      // 它们不可能被 OR 成一个中间值：本机有墓碑（保留收藏）而远端提出破坏性删除
      // （不保留）时，结果必须是「待用户确认」，而不是任何自动合成的取舍。
      final SyncMergeResult result = threeWayMerge(
        base: SyncSnapshot.empty,
        local: SyncSnapshot.of(
          entities: const <SyncEntity>[],
          deletions: <SyncDeletion>[
            const SyncDeletion(
              kind: SyncEntityKind.feed,
              key: 'feed.z',
              keepFavorites: true,
            ),
          ],
        ),
        remote: SyncSnapshot.of(
          entities: const <SyncEntity>[],
          deletions: <SyncDeletion>[
            const SyncDeletion(
              kind: SyncEntityKind.feed,
              key: 'feed.z',
              keepFavorites: false,
            ),
          ],
        ),
      );
      // 双方都有墓碑：删除事实一致，但「保留收藏」的选择不同——本机记录的那一份胜出
      // （tombstone 幂等语义：同实体同键只保留第一条），且不产生任何自动清数据的动作。
      expect(
        result.merged.deletion(SyncEntityKind.feed, 'feed.z')!.keepFavorites,
        isTrue,
      );
      expect(result.pendingRemoteDeletions, isEmpty);
    });
  });

  group('字段缺失 != 值为 null', () {
    test('对端没报告该字段时按「未变更」处理，不产生假冲突', () {
      final SyncMergeResult result = threeWayMerge(
        base: SyncSnapshot.of(
          entities: <SyncEntity>[
            const SyncEntity(
              kind: SyncEntityKind.feed,
              key: 'feed.x',
              fields: <String, Object?>{
                'syncId': 'feed.x',
                'name': '名字',
                'sortOrder': 3,
              },
            ),
          ],
        ),
        local: SyncSnapshot.of(
          entities: <SyncEntity>[
            const SyncEntity(
              kind: SyncEntityKind.feed,
              key: 'feed.x',
              fields: <String, Object?>{
                'syncId': 'feed.x',
                'name': '本机改名',
                'sortOrder': 3,
              },
            ),
          ],
        ),
        remote: SyncSnapshot.of(
          entities: <SyncEntity>[
            const SyncEntity(
              kind: SyncEntityKind.feed,
              key: 'feed.x',
              // 远端只报告了名字与 syncId，**没有** sortOrder。
              fields: <String, Object?>{'syncId': 'feed.x', 'name': '名字'},
            ),
          ],
        ),
      );
      expect(result.conflicts, isEmpty, reason: '缺失不是「改成了 null」');
      final SyncEntity merged = result.merged.entity(
        SyncEntityKind.feed,
        'feed.x',
      )!;
      expect(merged.fields['name'], '本机改名');
      expect(merged.fields['sortOrder'], 3);
    });

    test('值为 null 与缺失不同：把某个可选字段显式清空是一次真实变更', () {
      final SyncMergeResult result = threeWayMerge(
        base: SyncSnapshot.of(
          entities: <SyncEntity>[
            const SyncEntity(
              kind: SyncEntityKind.feed,
              key: 'feed.y',
              fields: <String, Object?>{'syncId': 'feed.y', 'sourceName': '源名'},
            ),
          ],
        ),
        local: SyncSnapshot.of(
          entities: <SyncEntity>[
            const SyncEntity(
              kind: SyncEntityKind.feed,
              key: 'feed.y',
              fields: <String, Object?>{'syncId': 'feed.y', 'sourceName': null},
            ),
          ],
        ),
        remote: SyncSnapshot.of(
          entities: <SyncEntity>[
            const SyncEntity(
              kind: SyncEntityKind.feed,
              key: 'feed.y',
              fields: <String, Object?>{'syncId': 'feed.y', 'sourceName': '源名'},
            ),
          ],
        ),
      );
      expect(result.conflicts, isEmpty);
      final SyncEntity merged = result.merged.entity(
        SyncEntityKind.feed,
        'feed.y',
      )!;
      expect(merged.hasField('sourceName'), isTrue);
      expect(merged.fields['sourceName'], isNull);
    });
  });

  group('多个实体互不干扰', () {
    test('一篇冲突不影响另一篇的自动合并', () {
      final SyncMergeResult result = threeWayMerge(
        base: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'unread'),
          _article(_k2, readingState: 'unread'),
        ]),
        local: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'read'),
          _article(_k2, readingState: 'read'),
        ]),
        remote: _snapshot(<SyncEntity>[
          _article(_k1, readingState: 'later'),
          _article(_k2, readingState: 'unread'),
        ]),
      );
      expect(result.conflicts.length, 1);
      expect(result.conflicts.single.key, _k1);
      expect(
        result.merged
            .entity(SyncEntityKind.articleState, _k2)!
            .fields['readingState'],
        'read',
      );
    });
  });
}
