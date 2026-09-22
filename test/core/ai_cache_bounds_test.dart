// T047：AI 结果缓存的容量上限与淘汰顺序（补 T030 遗留的「缓存没有上限与淘汰策略」）。
//
// 判定是纯函数，因此可以逐条钉住最难验证的三件事：淘汰顺序**确定**、本次刚写入的条目**不被删**、
// 两个上限（条数 + 字节）**都要满足**。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

/// 造一条事实（时间用序号表达，便于读）。
AiCacheEntryFact _fact({
  required String key,
  required int bytes,
  required int usedOrder,
}) => AiCacheEntryFact(
  key: key,
  byteLength: bytes,
  createdAt: DateTime.utc(2026, 1, 1),
  // 用小时序号表达「谁更近用过」：数字越大越近。
  lastUsedAt: DateTime.utc(2026, 1, 1).add(Duration(hours: usedOrder)),
);

void main() {
  group('UTF-8 字节长度（与落库口径一致）', () {
    test('ASCII 每字符 1 字节，CJK 每字符 3 字节', () {
      expect(utf8ByteLength('abc'), 3);
      expect(utf8ByteLength('你好世界'), 12, reason: '4 个汉字 = 12 字节');
      expect(
        utf8ByteLength('a好'),
        4,
        reason: '混合文本按字符类别分别计；用 String.length 会算成 2',
      );
      expect(utf8ByteLength(''), 0);
    });

    test('两字节与四字节字符', () {
      // é 的 UTF-8 是 2 字节。
      expect(utf8ByteLength('é'), 2);
      // 😀（U+1F600）是代理对，UTF-8 下 4 字节；Dart 的 length 是 2。
      expect(utf8ByteLength('😀'), 4);
      expect('😀'.length, 2, reason: '证明 Dart 的 length 不是字节数');
    });
  });

  group('淘汰计划', () {
    test('在两个上限内时一条都不删', () {
      final AiCacheEvictionPlan plan = planAiCacheEviction(
        entries: <AiCacheEntryFact>[
          _fact(key: 'a', bytes: 100, usedOrder: 1),
          _fact(key: 'b', bytes: 100, usedOrder: 2),
        ],
        limits: const AiCacheLimits(maxEntries: 10, maxBytes: 1000),
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.retainedCount, 2);
      expect(plan.totalBytes, 200);
    });

    test('按**最近使用**升序淘汰（最久没用的先走），不是按创建时间', () {
      final AiCacheEvictionPlan plan = planAiCacheEviction(
        entries: <AiCacheEntryFact>[
          _fact(key: 'recent', bytes: 10, usedOrder: 5),
          _fact(key: 'oldest', bytes: 10, usedOrder: 1),
          _fact(key: 'middle', bytes: 10, usedOrder: 3),
        ],
        limits: const AiCacheLimits(maxEntries: 2, maxBytes: 1000),
      );
      expect(plan.keysToDelete, <String>['oldest']);
      expect(plan.retainedCount, 2);
    });

    test('条数上限与字节上限**都要满足**（只满足一个不算够）', () {
      // 条数已够（3 条 <= 3），但字节超限：必须继续删到字节也满足。
      final AiCacheEvictionPlan byBytes = planAiCacheEviction(
        entries: <AiCacheEntryFact>[
          _fact(key: 'a', bytes: 900, usedOrder: 1),
          _fact(key: 'b', bytes: 900, usedOrder: 2),
          _fact(key: 'c', bytes: 900, usedOrder: 3),
        ],
        limits: const AiCacheLimits(maxEntries: 3, maxBytes: 1000),
      );
      expect(byBytes.keysToDelete, <String>[
        'a',
        'b',
      ], reason: '删到只剩 900 字节（c）才同时满足两个上限');
      expect(byBytes.totalBytes, 900);

      // 字节已够（200 <= 10000），但条数超限：必须按条数删。
      final AiCacheEvictionPlan byCount = planAiCacheEviction(
        entries: <AiCacheEntryFact>[
          _fact(key: 'a', bytes: 100, usedOrder: 1),
          _fact(key: 'b', bytes: 100, usedOrder: 2),
        ],
        limits: const AiCacheLimits(maxEntries: 1, maxBytes: 10000),
      );
      expect(byCount.keysToDelete, <String>['a']);
      expect(byCount.retainedCount, 1);
    });

    test('本次刚写入的条目**不被淘汰**（即便它是最久没用的那条时间戳）', () {
      final AiCacheEntryFact incoming = _fact(
        key: 'incoming',
        bytes: 900,
        usedOrder: 0,
      );
      final AiCacheEvictionPlan plan = planAiCacheEviction(
        entries: <AiCacheEntryFact>[
          _fact(key: 'existing', bytes: 900, usedOrder: 5),
        ],
        limits: const AiCacheLimits(maxEntries: 1, maxBytes: 1000),
        extra: incoming,
      );
      expect(plan.keysToDelete, <String>[
        'existing',
      ], reason: '删掉刚写入的结果等于让这次缓存写入白做（下一次同输入还要真实再付一次费）');
      expect(plan.retainedCount, 1);
    });

    test('淘汰顺序**确定**：同一时刻按键排序（两次运行结果相同）', () {
      final List<AiCacheEntryFact> entries = <AiCacheEntryFact>[
        _fact(key: 'c', bytes: 10, usedOrder: 1),
        _fact(key: 'a', bytes: 10, usedOrder: 1),
        _fact(key: 'b', bytes: 10, usedOrder: 1),
      ];
      final AiCacheEvictionPlan first = planAiCacheEviction(
        entries: entries,
        limits: const AiCacheLimits(maxEntries: 1, maxBytes: 1000),
      );
      final AiCacheEvictionPlan second = planAiCacheEviction(
        entries: entries.reversed.toList(),
        limits: const AiCacheLimits(maxEntries: 1, maxBytes: 1000),
      );
      expect(first.keysToDelete, <String>['a', 'b']);
      expect(second.keysToDelete, first.keysToDelete);
    });

    test('从未被读过（lastUsedAt 为 null）按**写入时刻**参与淘汰', () {
      // 刚写入、还没被任何任务读到的一批缓存：它们必须参与淘汰，否则「批量写入 1000 条」
      // 时淘汰退化成「只删旧的、留下刚写的一千条」，上限等于失效。
      final AiCacheEntryFact neverUsed = AiCacheEntryFact(
        key: 'never-used',
        byteLength: 10,
        createdAt: DateTime.utc(2026, 1, 1, 1),
      );
      final AiCacheEntryFact used = _fact(key: 'used', bytes: 10, usedOrder: 0);
      final AiCacheEvictionPlan plan = planAiCacheEviction(
        entries: <AiCacheEntryFact>[neverUsed, used],
        limits: const AiCacheLimits(maxEntries: 1, maxBytes: 1000),
      );
      // used 的有效时间戳是 2026-01-01T00:00（usedOrder=0），never-used 是 01:00 → used 更旧，
      // 因此先被删；这证明「从未使用」的行确实参与了排序，而不是被无条件保留。
      expect(plan.keysToDelete, <String>['used']);
    });

    test('上限被夹紧：0 条 / 极小字节不变成「清空一切」', () {
      final AiCacheEvictionPlan plan = planAiCacheEviction(
        entries: <AiCacheEntryFact>[_fact(key: 'a', bytes: 10, usedOrder: 1)],
        limits: const AiCacheLimits(maxEntries: 0, maxBytes: 0),
      );
      // 夹到 1 条 / 1024 字节 → 一条 10 字节的条目仍在上限内，不删。
      expect(plan.isEmpty, isTrue, reason: '被写坏的上限不该让缓存整个失效（那会让每次都真付费）');
    });

    test('单条就超过字节上限时保留它（正确性优先于上限严格性）', () {
      final AiCacheEntryFact huge = _fact(
        key: 'huge',
        bytes: 100000,
        usedOrder: 1,
      );
      final AiCacheEvictionPlan plan = planAiCacheEviction(
        entries: <AiCacheEntryFact>[
          _fact(key: 'small', bytes: 10, usedOrder: 2),
        ],
        limits: const AiCacheLimits(maxEntries: 5, maxBytes: 1024),
        extra: huge,
      );
      // 本次要写入的 hug（100 KB）单独就超过 1 KiB 上限：删掉 small 仍超限，但**不能**删自己
      // （删掉刚写入的结果等于让这次缓存写入白做，下一次同样输入还要真实再付一次费）。
      expect(plan.keysToDelete, <String>['small']);
      expect(plan.retainedCount, 1);
      expect(plan.totalBytes, 100000, reason: '上限被短暂突破是刻意的取舍');
    });
  });
}
