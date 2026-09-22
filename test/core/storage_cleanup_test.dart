// T047：清理的**纯规则**（架构 5.3 的清理段、SET-077/078）。
//
// 这些规则不碰文件系统、不碰数据库，因此可以逐条钉住「哪一类算占用、谁被保护、天数边界怎么
// 算、孤儿快照什么条件下才可回收」。把它们埋在实现里就只能靠「造一堆真实文件再数一遍」验证，
// 那样既慢又会随实现细节漂移。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

void main() {
  group('自动清理策略（SET-077 默认全关）', () {
    test('默认值：三个开关全关、天数 30/90/365、保护规则关闭', () {
      const AutoCleanupPolicy policy = AutoCleanupPolicy.defaults;
      expect(policy.isFullyDisabled, isTrue);
      expect(policy.mediaEnabled, isFalse);
      expect(policy.articleEnabled, isFalse);
      expect(policy.summaryEnabled, isFalse);
      expect(policy.mediaDays, 30);
      expect(policy.articleDays, 90);
      expect(policy.summaryDays, 365);
      expect(policy.includeFavorite, isFalse);
      expect(policy.includeLater, isFalse);
    });

    test('设置读成策略：缺字段逐项回退默认值（不整块失败）', () {
      final AutoCleanupPolicy policy = AutoCleanupPolicy.fromSettings(
        <String, Object?>{'mediaEnabled': true, 'mediaDays': 7},
        null,
      );
      expect(policy.mediaEnabled, isTrue);
      expect(policy.mediaDays, 7);
      // 未提供的字段回退到注册表默认值，而不是变空/变 0。
      expect(policy.articleDays, 90);
      expect(policy.summaryDays, 365);
      expect(policy.articleEnabled, isFalse);
      expect(policy.isFullyDisabled, isFalse, reason: '有一个开关打开就不算全关');
    });

    test('非法类型与越界天数都逐项回退（一个坏字段不影响其余字段）', () {
      final AutoCleanupPolicy policy = AutoCleanupPolicy.fromSettings(
        <String, Object?>{
          'mediaEnabled': 'yes', // 类型错
          'mediaDays': 0, // 越界（注册表下限 1）
          'articleEnabled': true,
          'articleDays': 120,
        },
        <String, Object?>{'includeFavorite': true, 'includeLater': 'x'},
      );
      expect(policy.mediaEnabled, isFalse, reason: '类型不对按默认值（关）');
      expect(policy.mediaDays, 30, reason: '0 天不是合法保留期，回退默认 30');
      expect(policy.articleEnabled, isTrue);
      expect(policy.articleDays, 120, reason: '另一个字段的合法值不受影响');
      expect(policy.includeFavorite, isTrue);
      expect(policy.includeLater, isFalse);
    });
  });

  group('天数边界', () {
    final DateTime now = DateTime.utc(2026, 9, 22, 12);

    test('截止时刻 = 现在 - 天数（按时长，不按本地日期）', () {
      expect(
        cleanupCutoff(days: 30, nowUtc: now),
        DateTime.utc(2026, 8, 23, 12),
      );
      // 天数下限夹紧到 1：0 或负数不表示「立刻全删」。
      expect(
        cleanupCutoff(days: 0, nowUtc: now),
        DateTime.utc(2026, 9, 21, 12),
      );
    });

    test('到期判定严格早于截止时刻（恰好等于边界不倒）', () {
      final DateTime cutoff = cleanupCutoff(days: 30, nowUtc: now);
      expect(
        isCleanupExpired(
          at: cutoff.subtract(const Duration(seconds: 1)),
          cutoffUtc: cutoff,
        ),
        isTrue,
      );
      expect(isCleanupExpired(at: cutoff, cutoffUtc: cutoff), isFalse);
      expect(
        isCleanupExpired(
          at: cutoff.add(const Duration(seconds: 1)),
          cutoffUtc: cutoff,
        ),
        isFalse,
      );
    });

    test('没有时间戳的行**不猜**（缺席不等于到期）', () {
      expect(
        isCleanupExpired(at: null, cutoffUtc: now),
        isFalse,
        reason: '用当前时间顶上去会让缺时间的旧文章在第一次自动清理时立刻被删',
      );
    });
  });

  group('保护规则（SET-078：收藏与 later 默认保护）', () {
    test('默认：收藏与 later 都被保护', () {
      expect(
        protectsFromAutoCleanup(
          favorite: true,
          later: false,
          includeFavorite: false,
          includeLater: false,
        ),
        isTrue,
      );
      expect(
        protectsFromAutoCleanup(
          favorite: false,
          later: true,
          includeFavorite: false,
          includeLater: false,
        ),
        isTrue,
      );
      expect(
        protectsFromAutoCleanup(
          favorite: false,
          later: false,
          includeFavorite: false,
          includeLater: false,
        ),
        isFalse,
        reason: '普通文章不在保护范围内',
      );
    });

    test('两个开关**互相独立**：打开收藏不影响 later 的保护', () {
      expect(
        protectsFromAutoCleanup(
          favorite: true,
          later: true,
          includeFavorite: true,
          includeLater: false,
        ),
        isTrue,
        reason: '收藏已解禁，但 later 仍在保护中',
      );
      expect(
        protectsFromAutoCleanup(
          favorite: true,
          later: true,
          includeFavorite: true,
          includeLater: true,
        ),
        isFalse,
      );
    });
  });

  group('孤儿快照的可回收判定（T042 遗留）', () {
    final DateTime now = DateTime.utc(2026, 9, 22);

    test('只回收「未被引用 + 超过保留天数」的快照', () {
      final List<String> collectable = orphanSnapshotsToCollect(
        remoteSnapshotNames: const <String>[
          'snapshot-current.json',
          'snapshot-referenced.json',
          'snapshot-old-orphan.json',
          'snapshot-new-orphan.json',
        ],
        referencedNames: const <String>{
          'snapshot-current.json',
          'snapshot-referenced.json',
        },
        lastModifiedByName: <String, DateTime>{
          'snapshot-current.json': now.subtract(const Duration(days: 400)),
          'snapshot-referenced.json': now.subtract(const Duration(days: 400)),
          'snapshot-old-orphan.json': now.subtract(const Duration(days: 200)),
          'snapshot-new-orphan.json': now.subtract(const Duration(days: 1)),
        },
        retentionDays: 90,
        nowUtc: now,
      );
      expect(collectable, <String>['snapshot-old-orphan.json']);
    });

    test('刚上传、manifest 还没写的孤儿**不回收**（避免与正在发布的设备赛跑）', () {
      final List<String> collectable = orphanSnapshotsToCollect(
        remoteSnapshotNames: const <String>['snapshot-just-uploaded.json'],
        referencedNames: const <String>{},
        lastModifiedByName: <String, DateTime>{
          'snapshot-just-uploaded.json': now.subtract(
            const Duration(minutes: 5),
          ),
        },
        retentionDays: 90,
        nowUtc: now,
      );
      expect(collectable, isEmpty);
    });

    test('拿不到修改时间的快照**不回收**（不猜）', () {
      final List<String> collectable = orphanSnapshotsToCollect(
        remoteSnapshotNames: const <String>['snapshot-no-time.json'],
        referencedNames: const <String>{},
        lastModifiedByName: const <String, DateTime>{},
        retentionDays: 90,
        nowUtc: now,
      );
      expect(collectable, isEmpty);
    });
  });

  group('占用与影响的形状', () {
    test('合计与取用：缺某类时返回 0 而不是抛错', () {
      final StorageUsageReport report = StorageUsageReport(
        measuredAt: DateTime.utc(2026, 9, 22),
        categories: const <StorageCategoryUsage>[
          StorageCategoryUsage(
            category: StorageCategory.mediaCache,
            byteCount: 1024,
            itemCount: 3,
          ),
          StorageCategoryUsage(
            category: StorageCategory.articleBody,
            byteCount: 2048,
            itemCount: 2,
          ),
        ],
      );
      expect(report.totalBytes, 3072);
      expect(report.usageOf(StorageCategory.mediaCache).itemCount, 3);
      expect(
        report.usageOf(StorageCategory.newsSummary).byteCount,
        0,
        reason: '少一类不该让整页失败，缺的按 0 显示',
      );
    });

    test('影响为空只有「确实什么都不动」时才成立', () {
      const CleanupImpact empty = CleanupImpact();
      expect(empty.isEmpty, isTrue);
      expect(empty.totalBytes, 0);
      // 只有「保护跳过」不为空的影响仍然是空的：跳过不等于删了东西。
      expect(const CleanupImpact(protectedArticles: 5).isEmpty, isTrue);
      expect(const CleanupImpact(aiCacheEntries: 1).isEmpty, isFalse);
      expect(
        const CleanupImpact(summaryBytes: 4096).isEmpty,
        isTrue,
        reason: 'isEmpty 判的是「有没有条目被删」，而字节只在有条目时才非零',
      );
    });

    test('彻底删除的关联判定', () {
      const ArticlePurgeImpact bare = ArticlePurgeImpact(
        articleId: 1,
        title: '无关联',
      );
      expect(bare.hasRelated, isFalse);
      expect(
        const ArticlePurgeImpact(
          articleId: 1,
          title: 'x',
          citations: 1,
        ).hasRelated,
        isTrue,
      );
    });
  });
}
