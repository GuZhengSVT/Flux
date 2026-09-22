// 同步快照：跨设备交换的**唯一内容形态**（T043；架构 5.1 的 Feed/ArticleState、
// 架构 5.2 的「不可变快照 + 共享 manifest」与「下载共同基线→三方比较」）。
//
// 为什么快照必须是一个**规范化、内容寻址**的纯数据文档，而不是「把几张表序列化一下」：
//
//   1) **它决定合并的输入**。三方合并（[threeWayMerge]）要拿「共同基线 / 本机当前 /
//      远端当前」三份同形态的数据做字段级比较；如果快照形态随实现漂移，三份输入就不再
//      可比，而症状是「某一台的改动被静默丢掉」——没有任何报错。
//   2) **它决定快照文件名**（T042：名字即内容）。因此编码必须**确定性**：同一份内容
//      永远编出同一串字节（键排序、无时间戳抖动），否则同一份内容会有两个哈希，
//      「读回校验」与「按版本幂等确认」都会失效。
//   3) **它决定什么会离开本机**。纳入的字段清单来自 T041 的 [SyncProjection]
//      （C 类设置、订阅/分组、三态与收藏、新闻规则），本文件只负责承载它们，
//      **不自己判断**哪些字段敏感——判断只有一处（投影），这里多写一份就迟早漂移。
//
// 三条刻意的取舍：
//   * **不含任何墙钟时间**（除了 prompt 版本的 createdAt，它只是内容的一部分，
//     不参与先后判定）。架构 5.2 明确「不得……仅比较设备墙钟」，因此最省事的做法是
//     让快照里根本没有可用于比较的时间戳；
//   * **删除是独立的一节**（[SyncDeletion]）：删除不能被表达成「字段变成空」——
//     空字段会被合并规则当成一次编辑，而删除是跨设备不得复活的事实（墓碑）；
//   * **缺失 ≠ 删除**：某个键在远端快照里没有出现，只说明远端没报告它，不说明远端删了它。
//     把「没出现」当成删除会让一台只同步了部分内容的设备把另一台的内容清空。
library;

import 'dart:convert';

import 'webdav.dart';

/// 一个实体的**字段级**内容（`kind` + 跨设备稳定键 + 字段表）。
final class SyncEntity {
  /// 构造实体。
  const SyncEntity({
    required this.kind,
    required this.key,
    required this.fields,
  });

  /// 实体类别（取值见 `SyncEntityKind`）。
  final String kind;

  /// 跨设备稳定键（订阅/分组用 syncId，设置用 SET 编号，文章状态用同步键）。
  final String key;

  /// 字段表；**键不存在表示该字段没有值**（与「值为 null」不同）。
  final Map<String, Object?> fields;

  /// 该字段是否有值。
  bool hasField(String field) => fields.containsKey(field);

  /// 复制并替换字段表。
  SyncEntity withFields(Map<String, Object?> next) =>
      SyncEntity(kind: kind, key: key, fields: next);

  @override
  String toString() => 'SyncEntity($kind/$key, ${fields.length} fields)';
}

/// 一条删除事实（墓碑 + 架构 5.2 的「删除操作元数据」）。
///
/// [keepFavorites] 是架构 5.2「删除订阅的保留收藏选择进入同步操作元数据」的落点：
/// 别的设备在应用这次删除**之前**必须能展示它的破坏性影响（会清掉多少、保留多少），
/// 因此这个选择必须随删除事实一起传播，而不是各设备按自己的默认值处理。
final class SyncDeletion {
  /// 构造删除事实。
  const SyncDeletion({
    required this.kind,
    required this.key,
    this.keepFavorites,
    this.displayName,
    this.revision = 0,
  });

  /// 实体类别。
  final String kind;

  /// 实体键。
  final String key;

  /// 删除时是否选择保留收藏；null 表示该删除不涉及这个选择（或未知）。
  final bool? keepFavorites;

  /// 删除时的显示名（让别的设备能向用户说明「删的是哪一个」）。
  final String? displayName;

  /// 记录这次删除的本地修订号（**不是**墙钟；仅用于诊断与幂等比较）。
  final int revision;

  /// 快照内的定位键。
  String get mapKey => deletionKey(kind: kind, key: key);

  @override
  String toString() => 'SyncDeletion($kind/$key)';
}

/// 删除事实在快照内的定位键（用 `\u0000` 分隔，避免 kind/key 拼串歧义）。
String deletionKey({required String kind, required String key}) =>
    '$kind\u0000$key';

/// 一份同步快照。
final class SyncSnapshot {
  /// 构造快照。
  const SyncSnapshot({required this.entities, required this.deletions});

  /// 空快照（首次同步时的「共同基线」与「远端还没有内容」两种情形都用它）。
  static const SyncSnapshot empty = SyncSnapshot(
    entities: <String, Map<String, SyncEntity>>{},
    deletions: <String, SyncDeletion>{},
  );

  /// 实体：kind → key → 实体。
  final Map<String, Map<String, SyncEntity>> entities;

  /// 删除事实：`kind\u0000key` → 删除事实。
  final Map<String, SyncDeletion> deletions;

  /// 是否没有任何内容。
  bool get isEmpty => entities.isEmpty && deletions.isEmpty;

  /// 全部实体（顺序稳定：先按 kind 排序，再按 key 排序）。
  Iterable<SyncEntity> get allEntities sync* {
    for (final String kind in sortedKinds) {
      final Map<String, SyncEntity> byKey = entities[kind]!;
      for (final String key in sortedKeysOf(byKey)) {
        yield byKey[key]!;
      }
    }
  }

  /// 已出现的实体类别（排序后）。
  List<String> get sortedKinds => sortedKeysOf(entities);

  /// 全部删除事实（顺序稳定）。
  List<SyncDeletion> get allDeletions =>
      sortedKeysOf(deletions)
          .map((String key) => deletions[key]!)
          .toList(growable: false);

  /// 实体数量。
  int get entityCount => entities.values.fold(
    0,
    (int sum, Map<String, SyncEntity> m) => sum + m.length,
  );

  /// 某一类别的实体数量。
  int entityCountOfKind(String kind) => entities[kind]?.length ?? 0;

  /// 取一个实体；没有则 null。
  SyncEntity? entity(String kind, String key) => entities[kind]?[key];

  /// 是否存在某个键（任意类别）。
  bool hasEntity(String kind, String key) =>
      entities[kind]?.containsKey(key) ?? false;

  /// 取一条删除事实。
  SyncDeletion? deletion(String kind, String key) =>
      deletions[deletionKey(kind: kind, key: key)];

  /// 是否已有该键的删除事实。
  bool hasDeletion(String kind, String key) =>
      deletions.containsKey(deletionKey(kind: kind, key: key));

  /// 与另一份快照是否**内容相同**（规范化比较，忽略插入顺序）。
  bool sameContentAs(SyncSnapshot other) => encode() == other.encode();

  /// 规范编码（确定性：键排序、无空白抖动）。
  ///
  /// 缩进只为人工诊断可读（快照会被下载下来看）；哈希与比较都用同一串字节，
  /// 因此「可读」与「确定性」不冲突。
  String encode() {
    final Map<String, Object?> encodedEntities = <String, Object?>{};
    for (final String kind in sortedKinds) {
      final Map<String, Object?> byKey = <String, Object?>{};
      final Map<String, SyncEntity> source = entities[kind]!;
      for (final String key in sortedKeysOf(source)) {
        final Map<String, Object?> fields = <String, Object?>{};
        final Map<String, Object?> raw = source[key]!.fields;
        for (final String field in sortedKeysOf(raw)) {
          fields[field] = _canonicalValue(raw[field]);
        }
        byKey[key] = fields;
      }
      encodedEntities[kind] = byKey;
    }
    final List<Object?> encodedDeletions = <Object?>[];
    for (final SyncDeletion deletion in allDeletions) {
      encodedDeletions.add(<String, Object?>{
        'kind': deletion.kind,
        'key': deletion.key,
        if (deletion.keepFavorites != null)
          'keepFavorites': deletion.keepFavorites,
        if (deletion.displayName != null) 'displayName': deletion.displayName,
        'revision': deletion.revision,
      });
    }
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'protocol': syncProtocolVersion,
      'entities': encodedEntities,
      'deletions': encodedDeletions,
    });
  }

  /// 解析快照。
  ///
  /// 任何结构问题都返回 **null**（调用方按「远端快照不可用」处理），而不是用默认值凑一份：
  /// 凑出来的快照会把整片内容当作「远端没有」，于是本机的下一次发布把远端内容全部覆盖掉
  /// （与 `SyncManifest.decode` 对更高协议版本返回 null 同一条纪律）。
  static SyncSnapshot? decode(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final Object? protocol = decoded['protocol'];
    if (protocol != null && protocol != syncProtocolVersion) {
      return null;
    }
    final Object? rawEntities = decoded['entities'];
    final Object? rawDeletions = decoded['deletions'];
    if (rawEntities is! Map<String, Object?> ||
        rawDeletions is! List<Object?>) {
      return null;
    }
    final Map<String, Map<String, SyncEntity>> entities =
        <String, Map<String, SyncEntity>>{};
    for (final MapEntry<String, Object?> kindEntry in rawEntities.entries) {
      final Object? byKey = kindEntry.value;
      if (byKey is! Map<String, Object?>) {
        return null;
      }
      final Map<String, SyncEntity> bucket = <String, SyncEntity>{};
      for (final MapEntry<String, Object?> entityEntry in byKey.entries) {
        final Object? fields = entityEntry.value;
        if (fields is! Map<String, Object?>) {
          return null;
        }
        bucket[entityEntry.key] = SyncEntity(
          kind: kindEntry.key,
          key: entityEntry.key,
          fields: Map<String, Object?>.unmodifiable(fields),
        );
      }
      entities[kindEntry.key] = bucket;
    }
    final Map<String, SyncDeletion> deletions = <String, SyncDeletion>{};
    for (final Object? raw in rawDeletions) {
      if (raw is! Map<String, Object?>) {
        return null;
      }
      final Object? kind = raw['kind'];
      final Object? key = raw['key'];
      final Object? keepFavorites = raw['keepFavorites'];
      final Object? displayName = raw['displayName'];
      final Object? revision = raw['revision'];
      if (kind is! String || key is! String) {
        return null;
      }
      if (keepFavorites != null && keepFavorites is! bool) {
        return null;
      }
      if (displayName != null && displayName is! String) {
        return null;
      }
      if (revision != null && revision is! int) {
        return null;
      }
      deletions[deletionKey(kind: kind, key: key)] = SyncDeletion(
        kind: kind,
        key: key,
        keepFavorites: keepFavorites as bool?,
        displayName: displayName as String?,
        revision: revision as int? ?? 0,
      );
    }
    return SyncSnapshot(
      entities: Map<String, Map<String, SyncEntity>>.unmodifiable(
        entities.map(
          (String kind, Map<String, SyncEntity> value) =>
              MapEntry<String, Map<String, SyncEntity>>(
                kind,
                Map<String, SyncEntity>.unmodifiable(value),
              ),
        ),
      ),
      deletions: Map<String, SyncDeletion>.unmodifiable(deletions),
    );
  }

  /// 由实体列表构造（便于用例与端口实现拼装）。
  static SyncSnapshot of({
    required Iterable<SyncEntity> entities,
    Iterable<SyncDeletion> deletions = const <SyncDeletion>[],
  }) {
    final Map<String, Map<String, SyncEntity>> byKind =
        <String, Map<String, SyncEntity>>{};
    for (final SyncEntity entity in entities) {
      (byKind[entity.kind] ??= <String, SyncEntity>{})[entity.key] = entity;
    }
    final Map<String, SyncDeletion> deletionMap = <String, SyncDeletion>{};
    for (final SyncDeletion deletion in deletions) {
      deletionMap[deletion.mapKey] = deletion;
    }
    return SyncSnapshot(entities: byKind, deletions: deletionMap);
  }
}

/// 排序后的键列表（规范化编码与遍历顺序的唯一来源）。
List<String> sortedKeysOf(Map<String, Object?> map) {
  final List<String> keys = map.keys.toList(growable: false);
  keys.sort();
  return keys;
}

/// 一个值能否在快照里**稳定比较**。
///
/// 比较用的是规范 JSON 文本而不是 `==`：`Map`/`List` 的 `==` 是引用相等，直接用它
/// 会让「两份内容相同的快照」被判成不同，于是每一轮同步都产生一次假冲突。
String canonicalSyncValue(Object? value) => jsonEncode(_canonicalValue(value));

/// 两个字段值是否相同（**字段缺失**由调用方用 [containsKey] 单独判断）。
bool sameSyncValue(Object? a, Object? b) =>
    canonicalSyncValue(a) == canonicalSyncValue(b);

Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final Map<String, Object?> out = <String, Object?>{};
    final List<Object?> keys = value.keys.toList(growable: false)
      ..sort((Object? a, Object? b) => '$a'.compareTo('$b'));
    for (final Object? key in keys) {
      out['$key'] = _canonicalValue(value[key]);
    }
    return out;
  }
  if (value is List) {
    return value.map(_canonicalValue).toList(growable: false);
  }
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  // 未知类型（枚举、DateTime 等）一律按其稳定文本参与比较：快照的字段总是由端口实现
  // 显式转成 JSON 基本类型，走到这里说明某个端口漏了转换，用文本兜底比抛错更安全。
  return value.toString();
}
