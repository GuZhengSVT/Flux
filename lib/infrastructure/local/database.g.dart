// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $GroupsTable extends Groups with TableInfo<$GroupsTable, Group> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
    'sync_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isReservedMeta = const VerificationMeta(
    'isReserved',
  );
  @override
  late final GeneratedColumn<bool> isReserved = GeneratedColumn<bool>(
    'is_reserved',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_reserved" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    syncId,
    name,
    sortOrder,
    pinned,
    isReserved,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<Group> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(
        _syncIdMeta,
        syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta),
      );
    } else if (isInserting) {
      context.missing(_syncIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('is_reserved')) {
      context.handle(
        _isReservedMeta,
        isReserved.isAcceptableOrUnknown(data['is_reserved']!, _isReservedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Group map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Group(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      syncId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      isReserved: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_reserved'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $GroupsTable createAlias(String alias) {
    return $GroupsTable(attachedDatabase, alias);
  }
}

class Group extends DataClass implements Insertable<Group> {
  final int id;

  /// 跨设备稳定标识（架构 5.1/5.2）。本机自增 [id] 不外传。
  final String syncId;
  final String name;

  /// 排序权重；用户拖动/菜单排序后写入。置顶是独立布尔值，不靠负权重表达。
  final int sortOrder;
  final bool pinned;

  /// 是否为保留组（“未分类”）。保留组不允许删除，只能移动其中订阅。
  final bool isReserved;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Group({
    required this.id,
    required this.syncId,
    required this.name,
    required this.sortOrder,
    required this.pinned,
    required this.isReserved,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['sync_id'] = Variable<String>(syncId);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    map['pinned'] = Variable<bool>(pinned);
    map['is_reserved'] = Variable<bool>(isReserved);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  GroupsCompanion toCompanion(bool nullToAbsent) {
    return GroupsCompanion(
      id: Value(id),
      syncId: Value(syncId),
      name: Value(name),
      sortOrder: Value(sortOrder),
      pinned: Value(pinned),
      isReserved: Value(isReserved),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Group.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Group(
      id: serializer.fromJson<int>(json['id']),
      syncId: serializer.fromJson<String>(json['syncId']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      isReserved: serializer.fromJson<bool>(json['isReserved']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'syncId': serializer.toJson<String>(syncId),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'pinned': serializer.toJson<bool>(pinned),
      'isReserved': serializer.toJson<bool>(isReserved),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Group copyWith({
    int? id,
    String? syncId,
    String? name,
    int? sortOrder,
    bool? pinned,
    bool? isReserved,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Group(
    id: id ?? this.id,
    syncId: syncId ?? this.syncId,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    pinned: pinned ?? this.pinned,
    isReserved: isReserved ?? this.isReserved,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Group copyWithCompanion(GroupsCompanion data) {
    return Group(
      id: data.id.present ? data.id.value : this.id,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      isReserved: data.isReserved.present
          ? data.isReserved.value
          : this.isReserved,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Group(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('pinned: $pinned, ')
          ..write('isReserved: $isReserved, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    syncId,
    name,
    sortOrder,
    pinned,
    isReserved,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Group &&
          other.id == this.id &&
          other.syncId == this.syncId &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.pinned == this.pinned &&
          other.isReserved == this.isReserved &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class GroupsCompanion extends UpdateCompanion<Group> {
  final Value<int> id;
  final Value<String> syncId;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<bool> pinned;
  final Value<bool> isReserved;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const GroupsCompanion({
    this.id = const Value.absent(),
    this.syncId = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.pinned = const Value.absent(),
    this.isReserved = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  GroupsCompanion.insert({
    this.id = const Value.absent(),
    required String syncId,
    required String name,
    this.sortOrder = const Value.absent(),
    this.pinned = const Value.absent(),
    this.isReserved = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : syncId = Value(syncId),
       name = Value(name);
  static Insertable<Group> custom({
    Expression<int>? id,
    Expression<String>? syncId,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<bool>? pinned,
    Expression<bool>? isReserved,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (syncId != null) 'sync_id': syncId,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (pinned != null) 'pinned': pinned,
      if (isReserved != null) 'is_reserved': isReserved,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  GroupsCompanion copyWith({
    Value<int>? id,
    Value<String>? syncId,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<bool>? pinned,
    Value<bool>? isReserved,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return GroupsCompanion(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      pinned: pinned ?? this.pinned,
      isReserved: isReserved ?? this.isReserved,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (isReserved.present) {
      map['is_reserved'] = Variable<bool>(isReserved.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupsCompanion(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('pinned: $pinned, ')
          ..write('isReserved: $isReserved, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $FeedsTable extends Feeds with TableInfo<$FeedsTable, Feed> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FeedsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
    'sync_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedUrlMeta = const VerificationMeta(
    'normalizedUrl',
  );
  @override
  late final GeneratedColumn<String> normalizedUrl = GeneratedColumn<String>(
    'normalized_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceNameMeta = const VerificationMeta(
    'sourceName',
  );
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
    'source_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<int> groupId = GeneratedColumn<int>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES "groups" (id)',
    ),
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _refreshIntervalMinutesMeta =
      const VerificationMeta('refreshIntervalMinutes');
  @override
  late final GeneratedColumn<int> refreshIntervalMinutes = GeneratedColumn<int>(
    'refresh_interval_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _httpEtagMeta = const VerificationMeta(
    'httpEtag',
  );
  @override
  late final GeneratedColumn<String> httpEtag = GeneratedColumn<String>(
    'http_etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _httpLastModifiedMeta = const VerificationMeta(
    'httpLastModified',
  );
  @override
  late final GeneratedColumn<String> httpLastModified = GeneratedColumn<String>(
    'http_last_modified',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _credentialRefMeta = const VerificationMeta(
    'credentialRef',
  );
  @override
  late final GeneratedColumn<String> credentialRef = GeneratedColumn<String>(
    'credential_ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    syncId,
    normalizedUrl,
    name,
    sourceName,
    groupId,
    favorite,
    refreshIntervalMinutes,
    sortOrder,
    httpEtag,
    httpLastModified,
    credentialRef,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'feeds';
  @override
  VerificationContext validateIntegrity(
    Insertable<Feed> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(
        _syncIdMeta,
        syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta),
      );
    } else if (isInserting) {
      context.missing(_syncIdMeta);
    }
    if (data.containsKey('normalized_url')) {
      context.handle(
        _normalizedUrlMeta,
        normalizedUrl.isAcceptableOrUnknown(
          data['normalized_url']!,
          _normalizedUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedUrlMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('source_name')) {
      context.handle(
        _sourceNameMeta,
        sourceName.isAcceptableOrUnknown(data['source_name']!, _sourceNameMeta),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('refresh_interval_minutes')) {
      context.handle(
        _refreshIntervalMinutesMeta,
        refreshIntervalMinutes.isAcceptableOrUnknown(
          data['refresh_interval_minutes']!,
          _refreshIntervalMinutesMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('http_etag')) {
      context.handle(
        _httpEtagMeta,
        httpEtag.isAcceptableOrUnknown(data['http_etag']!, _httpEtagMeta),
      );
    }
    if (data.containsKey('http_last_modified')) {
      context.handle(
        _httpLastModifiedMeta,
        httpLastModified.isAcceptableOrUnknown(
          data['http_last_modified']!,
          _httpLastModifiedMeta,
        ),
      );
    }
    if (data.containsKey('credential_ref')) {
      context.handle(
        _credentialRefMeta,
        credentialRef.isAcceptableOrUnknown(
          data['credential_ref']!,
          _credentialRefMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Feed map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Feed(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      syncId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_id'],
      )!,
      normalizedUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_url'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sourceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_name'],
      ),
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}group_id'],
      ),
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      refreshIntervalMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}refresh_interval_minutes'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      httpEtag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}http_etag'],
      ),
      httpLastModified: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}http_last_modified'],
      ),
      credentialRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}credential_ref'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FeedsTable createAlias(String alias) {
    return $FeedsTable(attachedDatabase, alias);
  }
}

class Feed extends DataClass implements Insertable<Feed> {
  final int id;

  /// 跨设备稳定标识；文章同步键用它（而非本机 id）构造确定性摘要。
  final String syncId;

  /// 规范化 URL：仅用于**匹配与去重**（OPML 往返、重复导入、跨设备对齐），
  /// 不用于请求。带凭据的原始地址见 [credentialRef]，避免秘密进入普通列。
  final String normalizedUrl;

  /// 显示名称（用户可改）。
  final String name;

  /// 源自带名称，与显示名分开保存（架构 5.1）；未解析到时为 null。
  final String? sourceName;

  /// 所属分组；删除分组时由用例层决定移动到未分类或删除订阅，不使用级联。
  final int? groupId;

  /// 加精：只影响显示与强调，不参与新闻选材（架构 4.1）。
  final bool favorite;

  /// 刷新间隔覆盖（分钟）；null 表示跟随全局默认（SET-020 区域）。
  final int? refreshIntervalMinutes;

  /// 组内排序权重（架构 5.1：Feed 含「分组、排序」）。置顶是分组属性，
  /// 加精是独立布尔 [favorite]，三者互不替代。
  final int sortOrder;

  /// 条件请求缓存：强 ETag（架构 4.1「有条件请求」，区分 304 与新内容）。
  final String? httpEtag;

  /// 条件请求缓存：Last-Modified 原文（HTTP 规范要求原样回送）。
  final String? httpLastModified;

  /// 本机安全存储中的凭据引用（T010 落地）；数据库中**不存秘密本身**。
  final String? credentialRef;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Feed({
    required this.id,
    required this.syncId,
    required this.normalizedUrl,
    required this.name,
    this.sourceName,
    this.groupId,
    required this.favorite,
    this.refreshIntervalMinutes,
    required this.sortOrder,
    this.httpEtag,
    this.httpLastModified,
    this.credentialRef,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['sync_id'] = Variable<String>(syncId);
    map['normalized_url'] = Variable<String>(normalizedUrl);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || sourceName != null) {
      map['source_name'] = Variable<String>(sourceName);
    }
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<int>(groupId);
    }
    map['favorite'] = Variable<bool>(favorite);
    if (!nullToAbsent || refreshIntervalMinutes != null) {
      map['refresh_interval_minutes'] = Variable<int>(refreshIntervalMinutes);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || httpEtag != null) {
      map['http_etag'] = Variable<String>(httpEtag);
    }
    if (!nullToAbsent || httpLastModified != null) {
      map['http_last_modified'] = Variable<String>(httpLastModified);
    }
    if (!nullToAbsent || credentialRef != null) {
      map['credential_ref'] = Variable<String>(credentialRef);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  FeedsCompanion toCompanion(bool nullToAbsent) {
    return FeedsCompanion(
      id: Value(id),
      syncId: Value(syncId),
      normalizedUrl: Value(normalizedUrl),
      name: Value(name),
      sourceName: sourceName == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceName),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      favorite: Value(favorite),
      refreshIntervalMinutes: refreshIntervalMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(refreshIntervalMinutes),
      sortOrder: Value(sortOrder),
      httpEtag: httpEtag == null && nullToAbsent
          ? const Value.absent()
          : Value(httpEtag),
      httpLastModified: httpLastModified == null && nullToAbsent
          ? const Value.absent()
          : Value(httpLastModified),
      credentialRef: credentialRef == null && nullToAbsent
          ? const Value.absent()
          : Value(credentialRef),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Feed.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Feed(
      id: serializer.fromJson<int>(json['id']),
      syncId: serializer.fromJson<String>(json['syncId']),
      normalizedUrl: serializer.fromJson<String>(json['normalizedUrl']),
      name: serializer.fromJson<String>(json['name']),
      sourceName: serializer.fromJson<String?>(json['sourceName']),
      groupId: serializer.fromJson<int?>(json['groupId']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      refreshIntervalMinutes: serializer.fromJson<int?>(
        json['refreshIntervalMinutes'],
      ),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      httpEtag: serializer.fromJson<String?>(json['httpEtag']),
      httpLastModified: serializer.fromJson<String?>(json['httpLastModified']),
      credentialRef: serializer.fromJson<String?>(json['credentialRef']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'syncId': serializer.toJson<String>(syncId),
      'normalizedUrl': serializer.toJson<String>(normalizedUrl),
      'name': serializer.toJson<String>(name),
      'sourceName': serializer.toJson<String?>(sourceName),
      'groupId': serializer.toJson<int?>(groupId),
      'favorite': serializer.toJson<bool>(favorite),
      'refreshIntervalMinutes': serializer.toJson<int?>(refreshIntervalMinutes),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'httpEtag': serializer.toJson<String?>(httpEtag),
      'httpLastModified': serializer.toJson<String?>(httpLastModified),
      'credentialRef': serializer.toJson<String?>(credentialRef),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Feed copyWith({
    int? id,
    String? syncId,
    String? normalizedUrl,
    String? name,
    Value<String?> sourceName = const Value.absent(),
    Value<int?> groupId = const Value.absent(),
    bool? favorite,
    Value<int?> refreshIntervalMinutes = const Value.absent(),
    int? sortOrder,
    Value<String?> httpEtag = const Value.absent(),
    Value<String?> httpLastModified = const Value.absent(),
    Value<String?> credentialRef = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Feed(
    id: id ?? this.id,
    syncId: syncId ?? this.syncId,
    normalizedUrl: normalizedUrl ?? this.normalizedUrl,
    name: name ?? this.name,
    sourceName: sourceName.present ? sourceName.value : this.sourceName,
    groupId: groupId.present ? groupId.value : this.groupId,
    favorite: favorite ?? this.favorite,
    refreshIntervalMinutes: refreshIntervalMinutes.present
        ? refreshIntervalMinutes.value
        : this.refreshIntervalMinutes,
    sortOrder: sortOrder ?? this.sortOrder,
    httpEtag: httpEtag.present ? httpEtag.value : this.httpEtag,
    httpLastModified: httpLastModified.present
        ? httpLastModified.value
        : this.httpLastModified,
    credentialRef: credentialRef.present
        ? credentialRef.value
        : this.credentialRef,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Feed copyWithCompanion(FeedsCompanion data) {
    return Feed(
      id: data.id.present ? data.id.value : this.id,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      normalizedUrl: data.normalizedUrl.present
          ? data.normalizedUrl.value
          : this.normalizedUrl,
      name: data.name.present ? data.name.value : this.name,
      sourceName: data.sourceName.present
          ? data.sourceName.value
          : this.sourceName,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      refreshIntervalMinutes: data.refreshIntervalMinutes.present
          ? data.refreshIntervalMinutes.value
          : this.refreshIntervalMinutes,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      httpEtag: data.httpEtag.present ? data.httpEtag.value : this.httpEtag,
      httpLastModified: data.httpLastModified.present
          ? data.httpLastModified.value
          : this.httpLastModified,
      credentialRef: data.credentialRef.present
          ? data.credentialRef.value
          : this.credentialRef,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Feed(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('normalizedUrl: $normalizedUrl, ')
          ..write('name: $name, ')
          ..write('sourceName: $sourceName, ')
          ..write('groupId: $groupId, ')
          ..write('favorite: $favorite, ')
          ..write('refreshIntervalMinutes: $refreshIntervalMinutes, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('httpEtag: $httpEtag, ')
          ..write('httpLastModified: $httpLastModified, ')
          ..write('credentialRef: $credentialRef, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    syncId,
    normalizedUrl,
    name,
    sourceName,
    groupId,
    favorite,
    refreshIntervalMinutes,
    sortOrder,
    httpEtag,
    httpLastModified,
    credentialRef,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Feed &&
          other.id == this.id &&
          other.syncId == this.syncId &&
          other.normalizedUrl == this.normalizedUrl &&
          other.name == this.name &&
          other.sourceName == this.sourceName &&
          other.groupId == this.groupId &&
          other.favorite == this.favorite &&
          other.refreshIntervalMinutes == this.refreshIntervalMinutes &&
          other.sortOrder == this.sortOrder &&
          other.httpEtag == this.httpEtag &&
          other.httpLastModified == this.httpLastModified &&
          other.credentialRef == this.credentialRef &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class FeedsCompanion extends UpdateCompanion<Feed> {
  final Value<int> id;
  final Value<String> syncId;
  final Value<String> normalizedUrl;
  final Value<String> name;
  final Value<String?> sourceName;
  final Value<int?> groupId;
  final Value<bool> favorite;
  final Value<int?> refreshIntervalMinutes;
  final Value<int> sortOrder;
  final Value<String?> httpEtag;
  final Value<String?> httpLastModified;
  final Value<String?> credentialRef;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const FeedsCompanion({
    this.id = const Value.absent(),
    this.syncId = const Value.absent(),
    this.normalizedUrl = const Value.absent(),
    this.name = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.groupId = const Value.absent(),
    this.favorite = const Value.absent(),
    this.refreshIntervalMinutes = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.httpEtag = const Value.absent(),
    this.httpLastModified = const Value.absent(),
    this.credentialRef = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  FeedsCompanion.insert({
    this.id = const Value.absent(),
    required String syncId,
    required String normalizedUrl,
    required String name,
    this.sourceName = const Value.absent(),
    this.groupId = const Value.absent(),
    this.favorite = const Value.absent(),
    this.refreshIntervalMinutes = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.httpEtag = const Value.absent(),
    this.httpLastModified = const Value.absent(),
    this.credentialRef = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : syncId = Value(syncId),
       normalizedUrl = Value(normalizedUrl),
       name = Value(name);
  static Insertable<Feed> custom({
    Expression<int>? id,
    Expression<String>? syncId,
    Expression<String>? normalizedUrl,
    Expression<String>? name,
    Expression<String>? sourceName,
    Expression<int>? groupId,
    Expression<bool>? favorite,
    Expression<int>? refreshIntervalMinutes,
    Expression<int>? sortOrder,
    Expression<String>? httpEtag,
    Expression<String>? httpLastModified,
    Expression<String>? credentialRef,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (syncId != null) 'sync_id': syncId,
      if (normalizedUrl != null) 'normalized_url': normalizedUrl,
      if (name != null) 'name': name,
      if (sourceName != null) 'source_name': sourceName,
      if (groupId != null) 'group_id': groupId,
      if (favorite != null) 'favorite': favorite,
      if (refreshIntervalMinutes != null)
        'refresh_interval_minutes': refreshIntervalMinutes,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (httpEtag != null) 'http_etag': httpEtag,
      if (httpLastModified != null) 'http_last_modified': httpLastModified,
      if (credentialRef != null) 'credential_ref': credentialRef,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  FeedsCompanion copyWith({
    Value<int>? id,
    Value<String>? syncId,
    Value<String>? normalizedUrl,
    Value<String>? name,
    Value<String?>? sourceName,
    Value<int?>? groupId,
    Value<bool>? favorite,
    Value<int?>? refreshIntervalMinutes,
    Value<int>? sortOrder,
    Value<String?>? httpEtag,
    Value<String?>? httpLastModified,
    Value<String?>? credentialRef,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return FeedsCompanion(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      normalizedUrl: normalizedUrl ?? this.normalizedUrl,
      name: name ?? this.name,
      sourceName: sourceName ?? this.sourceName,
      groupId: groupId ?? this.groupId,
      favorite: favorite ?? this.favorite,
      refreshIntervalMinutes:
          refreshIntervalMinutes ?? this.refreshIntervalMinutes,
      sortOrder: sortOrder ?? this.sortOrder,
      httpEtag: httpEtag ?? this.httpEtag,
      httpLastModified: httpLastModified ?? this.httpLastModified,
      credentialRef: credentialRef ?? this.credentialRef,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (normalizedUrl.present) {
      map['normalized_url'] = Variable<String>(normalizedUrl.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<int>(groupId.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (refreshIntervalMinutes.present) {
      map['refresh_interval_minutes'] = Variable<int>(
        refreshIntervalMinutes.value,
      );
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (httpEtag.present) {
      map['http_etag'] = Variable<String>(httpEtag.value);
    }
    if (httpLastModified.present) {
      map['http_last_modified'] = Variable<String>(httpLastModified.value);
    }
    if (credentialRef.present) {
      map['credential_ref'] = Variable<String>(credentialRef.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FeedsCompanion(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('normalizedUrl: $normalizedUrl, ')
          ..write('name: $name, ')
          ..write('sourceName: $sourceName, ')
          ..write('groupId: $groupId, ')
          ..write('favorite: $favorite, ')
          ..write('refreshIntervalMinutes: $refreshIntervalMinutes, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('httpEtag: $httpEtag, ')
          ..write('httpLastModified: $httpLastModified, ')
          ..write('credentialRef: $credentialRef, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ArticlesTable extends Articles with TableInfo<$ArticlesTable, Article> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArticlesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _feedIdMeta = const VerificationMeta('feedId');
  @override
  late final GeneratedColumn<int> feedId = GeneratedColumn<int>(
    'feed_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES feeds (id)',
    ),
  );
  static const VerificationMeta _guidMeta = const VerificationMeta('guid');
  @override
  late final GeneratedColumn<String> guid = GeneratedColumn<String>(
    'guid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _guidPresentMeta = const VerificationMeta(
    'guidPresent',
  );
  @override
  late final GeneratedColumn<bool> guidPresent = GeneratedColumn<bool>(
    'guid_present',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("guid_present" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _normalizedLinkMeta = const VerificationMeta(
    'normalizedLink',
  );
  @override
  late final GeneratedColumn<String> normalizedLink = GeneratedColumn<String>(
    'normalized_link',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceUrlMeta = const VerificationMeta(
    'sourceUrl',
  );
  @override
  late final GeneratedColumn<String> sourceUrl = GeneratedColumn<String>(
    'source_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fallbackFingerprintMeta =
      const VerificationMeta('fallbackFingerprint');
  @override
  late final GeneratedColumn<String> fallbackFingerprint =
      GeneratedColumn<String>(
        'fallback_fingerprint',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumnWithTypeConverter<FingerprintReliability?, String>
  fingerprintReliability =
      GeneratedColumn<String>(
        'fingerprint_reliability',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<FingerprintReliability?>(
        $ArticlesTable.$converterfingerprintReliabilityn,
      );
  @override
  late final GeneratedColumnWithTypeConverter<IdentityBasis, String>
  identityBasis = GeneratedColumn<String>(
    'identity_basis',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<IdentityBasis>($ArticlesTable.$converteridentityBasis);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publishedAtMeta = const VerificationMeta(
    'publishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> publishedAt = GeneratedColumn<DateTime>(
    'published_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<BodyCompleteness, String>
  bodyCompleteness = GeneratedColumn<String>(
    'body_completeness',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'unknown\' CHECK (body_completeness IN (\'sourceBody\', \'summaryOnly\', \'extracted\', \'unknown\'))',
    defaultValue: const CustomExpression('\'unknown\''),
  ).withConverter<BodyCompleteness>($ArticlesTable.$converterbodyCompleteness);
  static const VerificationMeta _bodyHashMeta = const VerificationMeta(
    'bodyHash',
  );
  @override
  late final GeneratedColumn<String> bodyHash = GeneratedColumn<String>(
    'body_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ReadingState, String>
  readingState = GeneratedColumn<String>(
    'reading_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'unread\' CHECK (reading_state IN (\'unread\', \'read\', \'later\'))',
    defaultValue: const CustomExpression('\'unread\''),
  ).withConverter<ReadingState>($ArticlesTable.$converterreadingState);
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    feedId,
    guid,
    guidPresent,
    normalizedLink,
    sourceUrl,
    fallbackFingerprint,
    fingerprintReliability,
    identityBasis,
    title,
    author,
    publishedAt,
    fetchedAt,
    body,
    bodyCompleteness,
    bodyHash,
    summary,
    readingState,
    favorite,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'articles';
  @override
  VerificationContext validateIntegrity(
    Insertable<Article> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('feed_id')) {
      context.handle(
        _feedIdMeta,
        feedId.isAcceptableOrUnknown(data['feed_id']!, _feedIdMeta),
      );
    } else if (isInserting) {
      context.missing(_feedIdMeta);
    }
    if (data.containsKey('guid')) {
      context.handle(
        _guidMeta,
        guid.isAcceptableOrUnknown(data['guid']!, _guidMeta),
      );
    }
    if (data.containsKey('guid_present')) {
      context.handle(
        _guidPresentMeta,
        guidPresent.isAcceptableOrUnknown(
          data['guid_present']!,
          _guidPresentMeta,
        ),
      );
    }
    if (data.containsKey('normalized_link')) {
      context.handle(
        _normalizedLinkMeta,
        normalizedLink.isAcceptableOrUnknown(
          data['normalized_link']!,
          _normalizedLinkMeta,
        ),
      );
    }
    if (data.containsKey('source_url')) {
      context.handle(
        _sourceUrlMeta,
        sourceUrl.isAcceptableOrUnknown(data['source_url']!, _sourceUrlMeta),
      );
    }
    if (data.containsKey('fallback_fingerprint')) {
      context.handle(
        _fallbackFingerprintMeta,
        fallbackFingerprint.isAcceptableOrUnknown(
          data['fallback_fingerprint']!,
          _fallbackFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('published_at')) {
      context.handle(
        _publishedAtMeta,
        publishedAt.isAcceptableOrUnknown(
          data['published_at']!,
          _publishedAtMeta,
        ),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('body_hash')) {
      context.handle(
        _bodyHashMeta,
        bodyHash.isAcceptableOrUnknown(data['body_hash']!, _bodyHashMeta),
      );
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Article map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Article(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      feedId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}feed_id'],
      )!,
      guid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}guid'],
      ),
      guidPresent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}guid_present'],
      )!,
      normalizedLink: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_link'],
      ),
      sourceUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_url'],
      ),
      fallbackFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fallback_fingerprint'],
      ),
      fingerprintReliability: $ArticlesTable.$converterfingerprintReliabilityn
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.string,
              data['${effectivePrefix}fingerprint_reliability'],
            ),
          ),
      identityBasis: $ArticlesTable.$converteridentityBasis.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}identity_basis'],
        )!,
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      publishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}published_at'],
      ),
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      ),
      bodyCompleteness: $ArticlesTable.$converterbodyCompleteness.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}body_completeness'],
        )!,
      ),
      bodyHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_hash'],
      ),
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      ),
      readingState: $ArticlesTable.$converterreadingState.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}reading_state'],
        )!,
      ),
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ArticlesTable createAlias(String alias) {
    return $ArticlesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<FingerprintReliability, String, String>
  $converterfingerprintReliability =
      const EnumNameConverter<FingerprintReliability>(
        FingerprintReliability.values,
      );
  static JsonTypeConverter2<FingerprintReliability?, String?, String?>
  $converterfingerprintReliabilityn = JsonTypeConverter2.asNullable(
    $converterfingerprintReliability,
  );
  static JsonTypeConverter2<IdentityBasis, String, String>
  $converteridentityBasis = const EnumNameConverter<IdentityBasis>(
    IdentityBasis.values,
  );
  static JsonTypeConverter2<BodyCompleteness, String, String>
  $converterbodyCompleteness = const EnumNameConverter<BodyCompleteness>(
    BodyCompleteness.values,
  );
  static JsonTypeConverter2<ReadingState, String, String>
  $converterreadingState = const EnumNameConverter<ReadingState>(
    ReadingState.values,
  );
}

class Article extends DataClass implements Insertable<Article> {
  final int id;

  /// 所属订阅。删除订阅由用例层显式处理（保留收藏、预览影响范围），
  /// 因此这里**不**用级联删除，避免绕过确认直接清空文章。
  final int feedId;

  /// 源内 GUID。可能是 null（源未提供）或空串（源提供了空值），
  /// 后者由 [guidPresent] 区分。
  final String? guid;

  /// GUID 存在性标记：区分“源没给 GUID”与“源给了空/重复 GUID”。
  final bool guidPresent;

  /// 规范化链接：用于身份匹配与去重（仅同 Feed 内唯一）。
  final String? normalizedLink;

  /// 原始链接，**保留全部查询参数**。规范化结果只用于匹配，不覆盖原文，
  /// 以免外开链接时丢失来源要求的参数（架构 4.1）。
  final String? sourceUrl;

  /// 无 GUID 兜底指纹（来源 + 标题 + 时间）；null 表示未走兜底规则。
  final String? fallbackFingerprint;

  /// 兜底指纹可靠度；null 表示该行不是靠指纹识别。发布时间缺失时指纹退化为
  /// 来源 + 标题，被标为 unreliable，同步阶段不得据此静默合并。
  final FingerprintReliability? fingerprintReliability;

  /// 本行实际采用的识别规则，便于导入诊断与冲突排查。
  final IdentityBasis identityBasis;
  final String title;
  final String? author;

  /// 发布时间（UTC）。为 null 表示源未提供，列表按抓取时间排序并注明。
  final DateTime? publishedAt;

  /// 抓取时间（UTC）。
  final DateTime fetchedAt;

  /// 正文（已清洗的受控文档来源文本）。
  final String? body;

  /// 正文完整性四态（架构 4.2）。默认 unknown，由导入流程判定。
  ///
  /// 与 [readingState] 同样的理由把取值域固化进 DDL：四态是本体的一部分，
  /// 非法值若被静默存入，后续渲染与同步都会产生难以追查的错误。
  final BodyCompleteness bodyCompleteness;

  /// 正文哈希：仅用于判断修订（内容变化才更新正文）。
  final String? bodyHash;
  final String? summary;

  /// 单一阅读状态枚举，带数据库 CHECK 约束；默认 unread。
  ///
  /// 这里用 customConstraint 手写 CHECK：枚举取值域必须固化在 DDL 里才能被
  /// 数据库拒绝非法值（drift 的 `.check()` 无法对转换器列稳定地内联字面量）。
  ///
  /// customConstraint 的参数是**列约束片段，不含类型名**（类型仍由 drift 按
  /// 列的 SQL 类型写出），它会整体覆盖 drift 的默认约束，因此 NOT NULL 与
  /// DEFAULT 必须在这里一并写出；约束里的列名用 SQL 名（reading_state）。
  final ReadingState readingState;

  /// 收藏：独立于阅读状态，加精/收藏不改变 read/unread/later（架构 4.1）。
  /// drift 会为布尔列自动附加 CHECK (favorite IN (0, 1))。
  final bool favorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Article({
    required this.id,
    required this.feedId,
    this.guid,
    required this.guidPresent,
    this.normalizedLink,
    this.sourceUrl,
    this.fallbackFingerprint,
    this.fingerprintReliability,
    required this.identityBasis,
    required this.title,
    this.author,
    this.publishedAt,
    required this.fetchedAt,
    this.body,
    required this.bodyCompleteness,
    this.bodyHash,
    this.summary,
    required this.readingState,
    required this.favorite,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['feed_id'] = Variable<int>(feedId);
    if (!nullToAbsent || guid != null) {
      map['guid'] = Variable<String>(guid);
    }
    map['guid_present'] = Variable<bool>(guidPresent);
    if (!nullToAbsent || normalizedLink != null) {
      map['normalized_link'] = Variable<String>(normalizedLink);
    }
    if (!nullToAbsent || sourceUrl != null) {
      map['source_url'] = Variable<String>(sourceUrl);
    }
    if (!nullToAbsent || fallbackFingerprint != null) {
      map['fallback_fingerprint'] = Variable<String>(fallbackFingerprint);
    }
    if (!nullToAbsent || fingerprintReliability != null) {
      map['fingerprint_reliability'] = Variable<String>(
        $ArticlesTable.$converterfingerprintReliabilityn.toSql(
          fingerprintReliability,
        ),
      );
    }
    {
      map['identity_basis'] = Variable<String>(
        $ArticlesTable.$converteridentityBasis.toSql(identityBasis),
      );
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || publishedAt != null) {
      map['published_at'] = Variable<DateTime>(publishedAt);
    }
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    if (!nullToAbsent || body != null) {
      map['body'] = Variable<String>(body);
    }
    {
      map['body_completeness'] = Variable<String>(
        $ArticlesTable.$converterbodyCompleteness.toSql(bodyCompleteness),
      );
    }
    if (!nullToAbsent || bodyHash != null) {
      map['body_hash'] = Variable<String>(bodyHash);
    }
    if (!nullToAbsent || summary != null) {
      map['summary'] = Variable<String>(summary);
    }
    {
      map['reading_state'] = Variable<String>(
        $ArticlesTable.$converterreadingState.toSql(readingState),
      );
    }
    map['favorite'] = Variable<bool>(favorite);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ArticlesCompanion toCompanion(bool nullToAbsent) {
    return ArticlesCompanion(
      id: Value(id),
      feedId: Value(feedId),
      guid: guid == null && nullToAbsent ? const Value.absent() : Value(guid),
      guidPresent: Value(guidPresent),
      normalizedLink: normalizedLink == null && nullToAbsent
          ? const Value.absent()
          : Value(normalizedLink),
      sourceUrl: sourceUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceUrl),
      fallbackFingerprint: fallbackFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(fallbackFingerprint),
      fingerprintReliability: fingerprintReliability == null && nullToAbsent
          ? const Value.absent()
          : Value(fingerprintReliability),
      identityBasis: Value(identityBasis),
      title: Value(title),
      author: author == null && nullToAbsent
          ? const Value.absent()
          : Value(author),
      publishedAt: publishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(publishedAt),
      fetchedAt: Value(fetchedAt),
      body: body == null && nullToAbsent ? const Value.absent() : Value(body),
      bodyCompleteness: Value(bodyCompleteness),
      bodyHash: bodyHash == null && nullToAbsent
          ? const Value.absent()
          : Value(bodyHash),
      summary: summary == null && nullToAbsent
          ? const Value.absent()
          : Value(summary),
      readingState: Value(readingState),
      favorite: Value(favorite),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Article.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Article(
      id: serializer.fromJson<int>(json['id']),
      feedId: serializer.fromJson<int>(json['feedId']),
      guid: serializer.fromJson<String?>(json['guid']),
      guidPresent: serializer.fromJson<bool>(json['guidPresent']),
      normalizedLink: serializer.fromJson<String?>(json['normalizedLink']),
      sourceUrl: serializer.fromJson<String?>(json['sourceUrl']),
      fallbackFingerprint: serializer.fromJson<String?>(
        json['fallbackFingerprint'],
      ),
      fingerprintReliability: $ArticlesTable.$converterfingerprintReliabilityn
          .fromJson(
            serializer.fromJson<String?>(json['fingerprintReliability']),
          ),
      identityBasis: $ArticlesTable.$converteridentityBasis.fromJson(
        serializer.fromJson<String>(json['identityBasis']),
      ),
      title: serializer.fromJson<String>(json['title']),
      author: serializer.fromJson<String?>(json['author']),
      publishedAt: serializer.fromJson<DateTime?>(json['publishedAt']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
      body: serializer.fromJson<String?>(json['body']),
      bodyCompleteness: $ArticlesTable.$converterbodyCompleteness.fromJson(
        serializer.fromJson<String>(json['bodyCompleteness']),
      ),
      bodyHash: serializer.fromJson<String?>(json['bodyHash']),
      summary: serializer.fromJson<String?>(json['summary']),
      readingState: $ArticlesTable.$converterreadingState.fromJson(
        serializer.fromJson<String>(json['readingState']),
      ),
      favorite: serializer.fromJson<bool>(json['favorite']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'feedId': serializer.toJson<int>(feedId),
      'guid': serializer.toJson<String?>(guid),
      'guidPresent': serializer.toJson<bool>(guidPresent),
      'normalizedLink': serializer.toJson<String?>(normalizedLink),
      'sourceUrl': serializer.toJson<String?>(sourceUrl),
      'fallbackFingerprint': serializer.toJson<String?>(fallbackFingerprint),
      'fingerprintReliability': serializer.toJson<String?>(
        $ArticlesTable.$converterfingerprintReliabilityn.toJson(
          fingerprintReliability,
        ),
      ),
      'identityBasis': serializer.toJson<String>(
        $ArticlesTable.$converteridentityBasis.toJson(identityBasis),
      ),
      'title': serializer.toJson<String>(title),
      'author': serializer.toJson<String?>(author),
      'publishedAt': serializer.toJson<DateTime?>(publishedAt),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
      'body': serializer.toJson<String?>(body),
      'bodyCompleteness': serializer.toJson<String>(
        $ArticlesTable.$converterbodyCompleteness.toJson(bodyCompleteness),
      ),
      'bodyHash': serializer.toJson<String?>(bodyHash),
      'summary': serializer.toJson<String?>(summary),
      'readingState': serializer.toJson<String>(
        $ArticlesTable.$converterreadingState.toJson(readingState),
      ),
      'favorite': serializer.toJson<bool>(favorite),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Article copyWith({
    int? id,
    int? feedId,
    Value<String?> guid = const Value.absent(),
    bool? guidPresent,
    Value<String?> normalizedLink = const Value.absent(),
    Value<String?> sourceUrl = const Value.absent(),
    Value<String?> fallbackFingerprint = const Value.absent(),
    Value<FingerprintReliability?> fingerprintReliability =
        const Value.absent(),
    IdentityBasis? identityBasis,
    String? title,
    Value<String?> author = const Value.absent(),
    Value<DateTime?> publishedAt = const Value.absent(),
    DateTime? fetchedAt,
    Value<String?> body = const Value.absent(),
    BodyCompleteness? bodyCompleteness,
    Value<String?> bodyHash = const Value.absent(),
    Value<String?> summary = const Value.absent(),
    ReadingState? readingState,
    bool? favorite,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Article(
    id: id ?? this.id,
    feedId: feedId ?? this.feedId,
    guid: guid.present ? guid.value : this.guid,
    guidPresent: guidPresent ?? this.guidPresent,
    normalizedLink: normalizedLink.present
        ? normalizedLink.value
        : this.normalizedLink,
    sourceUrl: sourceUrl.present ? sourceUrl.value : this.sourceUrl,
    fallbackFingerprint: fallbackFingerprint.present
        ? fallbackFingerprint.value
        : this.fallbackFingerprint,
    fingerprintReliability: fingerprintReliability.present
        ? fingerprintReliability.value
        : this.fingerprintReliability,
    identityBasis: identityBasis ?? this.identityBasis,
    title: title ?? this.title,
    author: author.present ? author.value : this.author,
    publishedAt: publishedAt.present ? publishedAt.value : this.publishedAt,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    body: body.present ? body.value : this.body,
    bodyCompleteness: bodyCompleteness ?? this.bodyCompleteness,
    bodyHash: bodyHash.present ? bodyHash.value : this.bodyHash,
    summary: summary.present ? summary.value : this.summary,
    readingState: readingState ?? this.readingState,
    favorite: favorite ?? this.favorite,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Article copyWithCompanion(ArticlesCompanion data) {
    return Article(
      id: data.id.present ? data.id.value : this.id,
      feedId: data.feedId.present ? data.feedId.value : this.feedId,
      guid: data.guid.present ? data.guid.value : this.guid,
      guidPresent: data.guidPresent.present
          ? data.guidPresent.value
          : this.guidPresent,
      normalizedLink: data.normalizedLink.present
          ? data.normalizedLink.value
          : this.normalizedLink,
      sourceUrl: data.sourceUrl.present ? data.sourceUrl.value : this.sourceUrl,
      fallbackFingerprint: data.fallbackFingerprint.present
          ? data.fallbackFingerprint.value
          : this.fallbackFingerprint,
      fingerprintReliability: data.fingerprintReliability.present
          ? data.fingerprintReliability.value
          : this.fingerprintReliability,
      identityBasis: data.identityBasis.present
          ? data.identityBasis.value
          : this.identityBasis,
      title: data.title.present ? data.title.value : this.title,
      author: data.author.present ? data.author.value : this.author,
      publishedAt: data.publishedAt.present
          ? data.publishedAt.value
          : this.publishedAt,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      body: data.body.present ? data.body.value : this.body,
      bodyCompleteness: data.bodyCompleteness.present
          ? data.bodyCompleteness.value
          : this.bodyCompleteness,
      bodyHash: data.bodyHash.present ? data.bodyHash.value : this.bodyHash,
      summary: data.summary.present ? data.summary.value : this.summary,
      readingState: data.readingState.present
          ? data.readingState.value
          : this.readingState,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Article(')
          ..write('id: $id, ')
          ..write('feedId: $feedId, ')
          ..write('guid: $guid, ')
          ..write('guidPresent: $guidPresent, ')
          ..write('normalizedLink: $normalizedLink, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('fallbackFingerprint: $fallbackFingerprint, ')
          ..write('fingerprintReliability: $fingerprintReliability, ')
          ..write('identityBasis: $identityBasis, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('publishedAt: $publishedAt, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('body: $body, ')
          ..write('bodyCompleteness: $bodyCompleteness, ')
          ..write('bodyHash: $bodyHash, ')
          ..write('summary: $summary, ')
          ..write('readingState: $readingState, ')
          ..write('favorite: $favorite, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    feedId,
    guid,
    guidPresent,
    normalizedLink,
    sourceUrl,
    fallbackFingerprint,
    fingerprintReliability,
    identityBasis,
    title,
    author,
    publishedAt,
    fetchedAt,
    body,
    bodyCompleteness,
    bodyHash,
    summary,
    readingState,
    favorite,
    createdAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Article &&
          other.id == this.id &&
          other.feedId == this.feedId &&
          other.guid == this.guid &&
          other.guidPresent == this.guidPresent &&
          other.normalizedLink == this.normalizedLink &&
          other.sourceUrl == this.sourceUrl &&
          other.fallbackFingerprint == this.fallbackFingerprint &&
          other.fingerprintReliability == this.fingerprintReliability &&
          other.identityBasis == this.identityBasis &&
          other.title == this.title &&
          other.author == this.author &&
          other.publishedAt == this.publishedAt &&
          other.fetchedAt == this.fetchedAt &&
          other.body == this.body &&
          other.bodyCompleteness == this.bodyCompleteness &&
          other.bodyHash == this.bodyHash &&
          other.summary == this.summary &&
          other.readingState == this.readingState &&
          other.favorite == this.favorite &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ArticlesCompanion extends UpdateCompanion<Article> {
  final Value<int> id;
  final Value<int> feedId;
  final Value<String?> guid;
  final Value<bool> guidPresent;
  final Value<String?> normalizedLink;
  final Value<String?> sourceUrl;
  final Value<String?> fallbackFingerprint;
  final Value<FingerprintReliability?> fingerprintReliability;
  final Value<IdentityBasis> identityBasis;
  final Value<String> title;
  final Value<String?> author;
  final Value<DateTime?> publishedAt;
  final Value<DateTime> fetchedAt;
  final Value<String?> body;
  final Value<BodyCompleteness> bodyCompleteness;
  final Value<String?> bodyHash;
  final Value<String?> summary;
  final Value<ReadingState> readingState;
  final Value<bool> favorite;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ArticlesCompanion({
    this.id = const Value.absent(),
    this.feedId = const Value.absent(),
    this.guid = const Value.absent(),
    this.guidPresent = const Value.absent(),
    this.normalizedLink = const Value.absent(),
    this.sourceUrl = const Value.absent(),
    this.fallbackFingerprint = const Value.absent(),
    this.fingerprintReliability = const Value.absent(),
    this.identityBasis = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.publishedAt = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.body = const Value.absent(),
    this.bodyCompleteness = const Value.absent(),
    this.bodyHash = const Value.absent(),
    this.summary = const Value.absent(),
    this.readingState = const Value.absent(),
    this.favorite = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ArticlesCompanion.insert({
    this.id = const Value.absent(),
    required int feedId,
    this.guid = const Value.absent(),
    this.guidPresent = const Value.absent(),
    this.normalizedLink = const Value.absent(),
    this.sourceUrl = const Value.absent(),
    this.fallbackFingerprint = const Value.absent(),
    this.fingerprintReliability = const Value.absent(),
    required IdentityBasis identityBasis,
    required String title,
    this.author = const Value.absent(),
    this.publishedAt = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.body = const Value.absent(),
    this.bodyCompleteness = const Value.absent(),
    this.bodyHash = const Value.absent(),
    this.summary = const Value.absent(),
    this.readingState = const Value.absent(),
    this.favorite = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : feedId = Value(feedId),
       identityBasis = Value(identityBasis),
       title = Value(title);
  static Insertable<Article> custom({
    Expression<int>? id,
    Expression<int>? feedId,
    Expression<String>? guid,
    Expression<bool>? guidPresent,
    Expression<String>? normalizedLink,
    Expression<String>? sourceUrl,
    Expression<String>? fallbackFingerprint,
    Expression<String>? fingerprintReliability,
    Expression<String>? identityBasis,
    Expression<String>? title,
    Expression<String>? author,
    Expression<DateTime>? publishedAt,
    Expression<DateTime>? fetchedAt,
    Expression<String>? body,
    Expression<String>? bodyCompleteness,
    Expression<String>? bodyHash,
    Expression<String>? summary,
    Expression<String>? readingState,
    Expression<bool>? favorite,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (feedId != null) 'feed_id': feedId,
      if (guid != null) 'guid': guid,
      if (guidPresent != null) 'guid_present': guidPresent,
      if (normalizedLink != null) 'normalized_link': normalizedLink,
      if (sourceUrl != null) 'source_url': sourceUrl,
      if (fallbackFingerprint != null)
        'fallback_fingerprint': fallbackFingerprint,
      if (fingerprintReliability != null)
        'fingerprint_reliability': fingerprintReliability,
      if (identityBasis != null) 'identity_basis': identityBasis,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (publishedAt != null) 'published_at': publishedAt,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (body != null) 'body': body,
      if (bodyCompleteness != null) 'body_completeness': bodyCompleteness,
      if (bodyHash != null) 'body_hash': bodyHash,
      if (summary != null) 'summary': summary,
      if (readingState != null) 'reading_state': readingState,
      if (favorite != null) 'favorite': favorite,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ArticlesCompanion copyWith({
    Value<int>? id,
    Value<int>? feedId,
    Value<String?>? guid,
    Value<bool>? guidPresent,
    Value<String?>? normalizedLink,
    Value<String?>? sourceUrl,
    Value<String?>? fallbackFingerprint,
    Value<FingerprintReliability?>? fingerprintReliability,
    Value<IdentityBasis>? identityBasis,
    Value<String>? title,
    Value<String?>? author,
    Value<DateTime?>? publishedAt,
    Value<DateTime>? fetchedAt,
    Value<String?>? body,
    Value<BodyCompleteness>? bodyCompleteness,
    Value<String?>? bodyHash,
    Value<String?>? summary,
    Value<ReadingState>? readingState,
    Value<bool>? favorite,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return ArticlesCompanion(
      id: id ?? this.id,
      feedId: feedId ?? this.feedId,
      guid: guid ?? this.guid,
      guidPresent: guidPresent ?? this.guidPresent,
      normalizedLink: normalizedLink ?? this.normalizedLink,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      fallbackFingerprint: fallbackFingerprint ?? this.fallbackFingerprint,
      fingerprintReliability:
          fingerprintReliability ?? this.fingerprintReliability,
      identityBasis: identityBasis ?? this.identityBasis,
      title: title ?? this.title,
      author: author ?? this.author,
      publishedAt: publishedAt ?? this.publishedAt,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      body: body ?? this.body,
      bodyCompleteness: bodyCompleteness ?? this.bodyCompleteness,
      bodyHash: bodyHash ?? this.bodyHash,
      summary: summary ?? this.summary,
      readingState: readingState ?? this.readingState,
      favorite: favorite ?? this.favorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (feedId.present) {
      map['feed_id'] = Variable<int>(feedId.value);
    }
    if (guid.present) {
      map['guid'] = Variable<String>(guid.value);
    }
    if (guidPresent.present) {
      map['guid_present'] = Variable<bool>(guidPresent.value);
    }
    if (normalizedLink.present) {
      map['normalized_link'] = Variable<String>(normalizedLink.value);
    }
    if (sourceUrl.present) {
      map['source_url'] = Variable<String>(sourceUrl.value);
    }
    if (fallbackFingerprint.present) {
      map['fallback_fingerprint'] = Variable<String>(fallbackFingerprint.value);
    }
    if (fingerprintReliability.present) {
      map['fingerprint_reliability'] = Variable<String>(
        $ArticlesTable.$converterfingerprintReliabilityn.toSql(
          fingerprintReliability.value,
        ),
      );
    }
    if (identityBasis.present) {
      map['identity_basis'] = Variable<String>(
        $ArticlesTable.$converteridentityBasis.toSql(identityBasis.value),
      );
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (publishedAt.present) {
      map['published_at'] = Variable<DateTime>(publishedAt.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (bodyCompleteness.present) {
      map['body_completeness'] = Variable<String>(
        $ArticlesTable.$converterbodyCompleteness.toSql(bodyCompleteness.value),
      );
    }
    if (bodyHash.present) {
      map['body_hash'] = Variable<String>(bodyHash.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (readingState.present) {
      map['reading_state'] = Variable<String>(
        $ArticlesTable.$converterreadingState.toSql(readingState.value),
      );
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArticlesCompanion(')
          ..write('id: $id, ')
          ..write('feedId: $feedId, ')
          ..write('guid: $guid, ')
          ..write('guidPresent: $guidPresent, ')
          ..write('normalizedLink: $normalizedLink, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('fallbackFingerprint: $fallbackFingerprint, ')
          ..write('fingerprintReliability: $fingerprintReliability, ')
          ..write('identityBasis: $identityBasis, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('publishedAt: $publishedAt, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('body: $body, ')
          ..write('bodyCompleteness: $bodyCompleteness, ')
          ..write('bodyHash: $bodyHash, ')
          ..write('summary: $summary, ')
          ..write('readingState: $readingState, ')
          ..write('favorite: $favorite, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ReadingSessionsTable extends ReadingSessions
    with TableInfo<$ReadingSessionsTable, ReadingSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _articleIdMeta = const VerificationMeta(
    'articleId',
  );
  @override
  late final GeneratedColumn<int> articleId = GeneratedColumn<int>(
    'article_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES articles (id)',
    ),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _effectiveSecondsMeta = const VerificationMeta(
    'effectiveSeconds',
  );
  @override
  late final GeneratedColumn<int> effectiveSeconds = GeneratedColumn<int>(
    'effective_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _timeZoneMeta = const VerificationMeta(
    'timeZone',
  );
  @override
  late final GeneratedColumn<String> timeZone = GeneratedColumn<String>(
    'time_zone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    articleId,
    startedAt,
    endedAt,
    effectiveSeconds,
    timeZone,
    localDate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('article_id')) {
      context.handle(
        _articleIdMeta,
        articleId.isAcceptableOrUnknown(data['article_id']!, _articleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_articleIdMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('effective_seconds')) {
      context.handle(
        _effectiveSecondsMeta,
        effectiveSeconds.isAcceptableOrUnknown(
          data['effective_seconds']!,
          _effectiveSecondsMeta,
        ),
      );
    }
    if (data.containsKey('time_zone')) {
      context.handle(
        _timeZoneMeta,
        timeZone.isAcceptableOrUnknown(data['time_zone']!, _timeZoneMeta),
      );
    } else if (isInserting) {
      context.missing(_timeZoneMeta);
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReadingSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      articleId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}article_id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      ),
      effectiveSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}effective_seconds'],
      )!,
      timeZone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_zone'],
      )!,
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
    );
  }

  @override
  $ReadingSessionsTable createAlias(String alias) {
    return $ReadingSessionsTable(attachedDatabase, alias);
  }
}

class ReadingSession extends DataClass implements Insertable<ReadingSession> {
  final int id;
  final int articleId;

  /// 会话开始（UTC 存储）。
  final DateTime startedAt;

  /// 会话结束（UTC）；进行中的会话为 null。
  final DateTime? endedAt;

  /// 有效秒数：只统计前台可见且活跃的时间，暂停区间不计入。
  final int effectiveSeconds;

  /// 统计时区（IANA 名称，如 `Asia/Shanghai`）。跨午夜按此时区拆分会话，
  /// 历史统计在用户旅行后仍按当时时区归属。
  final String timeZone;

  /// 设备本地日期键（`YYYY-MM-DD`，按 [timeZone] 计算）。
  ///
  /// 冗余存储而非每次由 UTC 现算：热力图与七日柱状图按本地日期分组，
  /// 若只存 UTC 就要在查询里重复时区换算，且历史会话的归属会随查询时区变化。
  final String localDate;
  const ReadingSession({
    required this.id,
    required this.articleId,
    required this.startedAt,
    this.endedAt,
    required this.effectiveSeconds,
    required this.timeZone,
    required this.localDate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['article_id'] = Variable<int>(articleId);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    map['effective_seconds'] = Variable<int>(effectiveSeconds);
    map['time_zone'] = Variable<String>(timeZone);
    map['local_date'] = Variable<String>(localDate);
    return map;
  }

  ReadingSessionsCompanion toCompanion(bool nullToAbsent) {
    return ReadingSessionsCompanion(
      id: Value(id),
      articleId: Value(articleId),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      effectiveSeconds: Value(effectiveSeconds),
      timeZone: Value(timeZone),
      localDate: Value(localDate),
    );
  }

  factory ReadingSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingSession(
      id: serializer.fromJson<int>(json['id']),
      articleId: serializer.fromJson<int>(json['articleId']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      effectiveSeconds: serializer.fromJson<int>(json['effectiveSeconds']),
      timeZone: serializer.fromJson<String>(json['timeZone']),
      localDate: serializer.fromJson<String>(json['localDate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'articleId': serializer.toJson<int>(articleId),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'effectiveSeconds': serializer.toJson<int>(effectiveSeconds),
      'timeZone': serializer.toJson<String>(timeZone),
      'localDate': serializer.toJson<String>(localDate),
    };
  }

  ReadingSession copyWith({
    int? id,
    int? articleId,
    DateTime? startedAt,
    Value<DateTime?> endedAt = const Value.absent(),
    int? effectiveSeconds,
    String? timeZone,
    String? localDate,
  }) => ReadingSession(
    id: id ?? this.id,
    articleId: articleId ?? this.articleId,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    effectiveSeconds: effectiveSeconds ?? this.effectiveSeconds,
    timeZone: timeZone ?? this.timeZone,
    localDate: localDate ?? this.localDate,
  );
  ReadingSession copyWithCompanion(ReadingSessionsCompanion data) {
    return ReadingSession(
      id: data.id.present ? data.id.value : this.id,
      articleId: data.articleId.present ? data.articleId.value : this.articleId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      effectiveSeconds: data.effectiveSeconds.present
          ? data.effectiveSeconds.value
          : this.effectiveSeconds,
      timeZone: data.timeZone.present ? data.timeZone.value : this.timeZone,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingSession(')
          ..write('id: $id, ')
          ..write('articleId: $articleId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('effectiveSeconds: $effectiveSeconds, ')
          ..write('timeZone: $timeZone, ')
          ..write('localDate: $localDate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    articleId,
    startedAt,
    endedAt,
    effectiveSeconds,
    timeZone,
    localDate,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingSession &&
          other.id == this.id &&
          other.articleId == this.articleId &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.effectiveSeconds == this.effectiveSeconds &&
          other.timeZone == this.timeZone &&
          other.localDate == this.localDate);
}

class ReadingSessionsCompanion extends UpdateCompanion<ReadingSession> {
  final Value<int> id;
  final Value<int> articleId;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<int> effectiveSeconds;
  final Value<String> timeZone;
  final Value<String> localDate;
  const ReadingSessionsCompanion({
    this.id = const Value.absent(),
    this.articleId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.effectiveSeconds = const Value.absent(),
    this.timeZone = const Value.absent(),
    this.localDate = const Value.absent(),
  });
  ReadingSessionsCompanion.insert({
    this.id = const Value.absent(),
    required int articleId,
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    this.effectiveSeconds = const Value.absent(),
    required String timeZone,
    required String localDate,
  }) : articleId = Value(articleId),
       startedAt = Value(startedAt),
       timeZone = Value(timeZone),
       localDate = Value(localDate);
  static Insertable<ReadingSession> custom({
    Expression<int>? id,
    Expression<int>? articleId,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<int>? effectiveSeconds,
    Expression<String>? timeZone,
    Expression<String>? localDate,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (articleId != null) 'article_id': articleId,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (effectiveSeconds != null) 'effective_seconds': effectiveSeconds,
      if (timeZone != null) 'time_zone': timeZone,
      if (localDate != null) 'local_date': localDate,
    });
  }

  ReadingSessionsCompanion copyWith({
    Value<int>? id,
    Value<int>? articleId,
    Value<DateTime>? startedAt,
    Value<DateTime?>? endedAt,
    Value<int>? effectiveSeconds,
    Value<String>? timeZone,
    Value<String>? localDate,
  }) {
    return ReadingSessionsCompanion(
      id: id ?? this.id,
      articleId: articleId ?? this.articleId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      effectiveSeconds: effectiveSeconds ?? this.effectiveSeconds,
      timeZone: timeZone ?? this.timeZone,
      localDate: localDate ?? this.localDate,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (articleId.present) {
      map['article_id'] = Variable<int>(articleId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (effectiveSeconds.present) {
      map['effective_seconds'] = Variable<int>(effectiveSeconds.value);
    }
    if (timeZone.present) {
      map['time_zone'] = Variable<String>(timeZone.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingSessionsCompanion(')
          ..write('id: $id, ')
          ..write('articleId: $articleId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('effectiveSeconds: $effectiveSeconds, ')
          ..write('timeZone: $timeZone, ')
          ..write('localDate: $localDate')
          ..write(')'))
        .toString();
  }
}

class $SummaryVersionsTable extends SummaryVersions
    with TableInfo<$SummaryVersionsTable, SummaryVersion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SummaryVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeZoneMeta = const VerificationMeta(
    'timeZone',
  );
  @override
  late final GeneratedColumn<String> timeZone = GeneratedColumn<String>(
    'time_zone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inputSnapshotRefMeta = const VerificationMeta(
    'inputSnapshotRef',
  );
  @override
  late final GeneratedColumn<String> inputSnapshotRef = GeneratedColumn<String>(
    'input_snapshot_ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _inputSnapshotHashMeta = const VerificationMeta(
    'inputSnapshotHash',
  );
  @override
  late final GeneratedColumn<String> inputSnapshotHash =
      GeneratedColumn<String>(
        'input_snapshot_hash',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _providerAliasMeta = const VerificationMeta(
    'providerAlias',
  );
  @override
  late final GeneratedColumn<String> providerAlias = GeneratedColumn<String>(
    'provider_alias',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TaskStatus, String> taskStatus =
      GeneratedColumn<String>(
        'task_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<TaskStatus>($SummaryVersionsTable.$convertertaskStatus);
  static const VerificationMeta _isCurrentMeta = const VerificationMeta(
    'isCurrent',
  );
  @override
  late final GeneratedColumn<bool> isCurrent = GeneratedColumn<bool>(
    'is_current',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_current" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    localDate,
    timeZone,
    inputSnapshotRef,
    inputSnapshotHash,
    providerAlias,
    modelId,
    taskStatus,
    isCurrent,
    content,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'summary_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SummaryVersion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    if (data.containsKey('time_zone')) {
      context.handle(
        _timeZoneMeta,
        timeZone.isAcceptableOrUnknown(data['time_zone']!, _timeZoneMeta),
      );
    } else if (isInserting) {
      context.missing(_timeZoneMeta);
    }
    if (data.containsKey('input_snapshot_ref')) {
      context.handle(
        _inputSnapshotRefMeta,
        inputSnapshotRef.isAcceptableOrUnknown(
          data['input_snapshot_ref']!,
          _inputSnapshotRefMeta,
        ),
      );
    }
    if (data.containsKey('input_snapshot_hash')) {
      context.handle(
        _inputSnapshotHashMeta,
        inputSnapshotHash.isAcceptableOrUnknown(
          data['input_snapshot_hash']!,
          _inputSnapshotHashMeta,
        ),
      );
    }
    if (data.containsKey('provider_alias')) {
      context.handle(
        _providerAliasMeta,
        providerAlias.isAcceptableOrUnknown(
          data['provider_alias']!,
          _providerAliasMeta,
        ),
      );
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    }
    if (data.containsKey('is_current')) {
      context.handle(
        _isCurrentMeta,
        isCurrent.isAcceptableOrUnknown(data['is_current']!, _isCurrentMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SummaryVersion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SummaryVersion(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
      timeZone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_zone'],
      )!,
      inputSnapshotRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}input_snapshot_ref'],
      ),
      inputSnapshotHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}input_snapshot_hash'],
      ),
      providerAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_alias'],
      ),
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      ),
      taskStatus: $SummaryVersionsTable.$convertertaskStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}task_status'],
        )!,
      ),
      isCurrent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_current'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SummaryVersionsTable createAlias(String alias) {
    return $SummaryVersionsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TaskStatus, String, String> $convertertaskStatus =
      const EnumNameConverter<TaskStatus>(TaskStatus.values);
}

class SummaryVersion extends DataClass implements Insertable<SummaryVersion> {
  final int id;

  /// 设备本地日期键（`YYYY-MM-DD`）。日期与 [timeZone] 在任务开始时固化，
  /// 之后即使设备时区变化也不重写历史归属（D-07、架构 4.4）。
  final String localDate;

  /// 任务开始时的统计时区（IANA 名称）。
  final String timeZone;

  /// 输入快照引用：指向当次固定下来的文章集合（T037 落地具体快照表）。
  /// 这里只保存不透明引用与内容哈希，避免 T009 提前实现 AI 输入模型。
  final String? inputSnapshotRef;

  /// 输入快照内容哈希：同一输入重复生成时可据此判定缓存是否失效。
  final String? inputSnapshotHash;

  /// 模型元数据：提供商别名与模型 ID 分开，避免把端点/凭据写进这一层。
  final String? providerAlias;
  final String? modelId;

  /// 任务状态引用，复用 core 的任务状态机枚举（9 态，架构 4.5）。
  final TaskStatus taskStatus;

  /// 是否为当前对外展示的版本。
  final bool isCurrent;

  /// 总结正文（校验通过后的最终文本）。
  final String? content;

  /// 生成/保存时间（UTC）。
  final DateTime createdAt;
  const SummaryVersion({
    required this.id,
    required this.localDate,
    required this.timeZone,
    this.inputSnapshotRef,
    this.inputSnapshotHash,
    this.providerAlias,
    this.modelId,
    required this.taskStatus,
    required this.isCurrent,
    this.content,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['local_date'] = Variable<String>(localDate);
    map['time_zone'] = Variable<String>(timeZone);
    if (!nullToAbsent || inputSnapshotRef != null) {
      map['input_snapshot_ref'] = Variable<String>(inputSnapshotRef);
    }
    if (!nullToAbsent || inputSnapshotHash != null) {
      map['input_snapshot_hash'] = Variable<String>(inputSnapshotHash);
    }
    if (!nullToAbsent || providerAlias != null) {
      map['provider_alias'] = Variable<String>(providerAlias);
    }
    if (!nullToAbsent || modelId != null) {
      map['model_id'] = Variable<String>(modelId);
    }
    {
      map['task_status'] = Variable<String>(
        $SummaryVersionsTable.$convertertaskStatus.toSql(taskStatus),
      );
    }
    map['is_current'] = Variable<bool>(isCurrent);
    if (!nullToAbsent || content != null) {
      map['content'] = Variable<String>(content);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SummaryVersionsCompanion toCompanion(bool nullToAbsent) {
    return SummaryVersionsCompanion(
      id: Value(id),
      localDate: Value(localDate),
      timeZone: Value(timeZone),
      inputSnapshotRef: inputSnapshotRef == null && nullToAbsent
          ? const Value.absent()
          : Value(inputSnapshotRef),
      inputSnapshotHash: inputSnapshotHash == null && nullToAbsent
          ? const Value.absent()
          : Value(inputSnapshotHash),
      providerAlias: providerAlias == null && nullToAbsent
          ? const Value.absent()
          : Value(providerAlias),
      modelId: modelId == null && nullToAbsent
          ? const Value.absent()
          : Value(modelId),
      taskStatus: Value(taskStatus),
      isCurrent: Value(isCurrent),
      content: content == null && nullToAbsent
          ? const Value.absent()
          : Value(content),
      createdAt: Value(createdAt),
    );
  }

  factory SummaryVersion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SummaryVersion(
      id: serializer.fromJson<int>(json['id']),
      localDate: serializer.fromJson<String>(json['localDate']),
      timeZone: serializer.fromJson<String>(json['timeZone']),
      inputSnapshotRef: serializer.fromJson<String?>(json['inputSnapshotRef']),
      inputSnapshotHash: serializer.fromJson<String?>(
        json['inputSnapshotHash'],
      ),
      providerAlias: serializer.fromJson<String?>(json['providerAlias']),
      modelId: serializer.fromJson<String?>(json['modelId']),
      taskStatus: $SummaryVersionsTable.$convertertaskStatus.fromJson(
        serializer.fromJson<String>(json['taskStatus']),
      ),
      isCurrent: serializer.fromJson<bool>(json['isCurrent']),
      content: serializer.fromJson<String?>(json['content']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'localDate': serializer.toJson<String>(localDate),
      'timeZone': serializer.toJson<String>(timeZone),
      'inputSnapshotRef': serializer.toJson<String?>(inputSnapshotRef),
      'inputSnapshotHash': serializer.toJson<String?>(inputSnapshotHash),
      'providerAlias': serializer.toJson<String?>(providerAlias),
      'modelId': serializer.toJson<String?>(modelId),
      'taskStatus': serializer.toJson<String>(
        $SummaryVersionsTable.$convertertaskStatus.toJson(taskStatus),
      ),
      'isCurrent': serializer.toJson<bool>(isCurrent),
      'content': serializer.toJson<String?>(content),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SummaryVersion copyWith({
    int? id,
    String? localDate,
    String? timeZone,
    Value<String?> inputSnapshotRef = const Value.absent(),
    Value<String?> inputSnapshotHash = const Value.absent(),
    Value<String?> providerAlias = const Value.absent(),
    Value<String?> modelId = const Value.absent(),
    TaskStatus? taskStatus,
    bool? isCurrent,
    Value<String?> content = const Value.absent(),
    DateTime? createdAt,
  }) => SummaryVersion(
    id: id ?? this.id,
    localDate: localDate ?? this.localDate,
    timeZone: timeZone ?? this.timeZone,
    inputSnapshotRef: inputSnapshotRef.present
        ? inputSnapshotRef.value
        : this.inputSnapshotRef,
    inputSnapshotHash: inputSnapshotHash.present
        ? inputSnapshotHash.value
        : this.inputSnapshotHash,
    providerAlias: providerAlias.present
        ? providerAlias.value
        : this.providerAlias,
    modelId: modelId.present ? modelId.value : this.modelId,
    taskStatus: taskStatus ?? this.taskStatus,
    isCurrent: isCurrent ?? this.isCurrent,
    content: content.present ? content.value : this.content,
    createdAt: createdAt ?? this.createdAt,
  );
  SummaryVersion copyWithCompanion(SummaryVersionsCompanion data) {
    return SummaryVersion(
      id: data.id.present ? data.id.value : this.id,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      timeZone: data.timeZone.present ? data.timeZone.value : this.timeZone,
      inputSnapshotRef: data.inputSnapshotRef.present
          ? data.inputSnapshotRef.value
          : this.inputSnapshotRef,
      inputSnapshotHash: data.inputSnapshotHash.present
          ? data.inputSnapshotHash.value
          : this.inputSnapshotHash,
      providerAlias: data.providerAlias.present
          ? data.providerAlias.value
          : this.providerAlias,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      taskStatus: data.taskStatus.present
          ? data.taskStatus.value
          : this.taskStatus,
      isCurrent: data.isCurrent.present ? data.isCurrent.value : this.isCurrent,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SummaryVersion(')
          ..write('id: $id, ')
          ..write('localDate: $localDate, ')
          ..write('timeZone: $timeZone, ')
          ..write('inputSnapshotRef: $inputSnapshotRef, ')
          ..write('inputSnapshotHash: $inputSnapshotHash, ')
          ..write('providerAlias: $providerAlias, ')
          ..write('modelId: $modelId, ')
          ..write('taskStatus: $taskStatus, ')
          ..write('isCurrent: $isCurrent, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    localDate,
    timeZone,
    inputSnapshotRef,
    inputSnapshotHash,
    providerAlias,
    modelId,
    taskStatus,
    isCurrent,
    content,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SummaryVersion &&
          other.id == this.id &&
          other.localDate == this.localDate &&
          other.timeZone == this.timeZone &&
          other.inputSnapshotRef == this.inputSnapshotRef &&
          other.inputSnapshotHash == this.inputSnapshotHash &&
          other.providerAlias == this.providerAlias &&
          other.modelId == this.modelId &&
          other.taskStatus == this.taskStatus &&
          other.isCurrent == this.isCurrent &&
          other.content == this.content &&
          other.createdAt == this.createdAt);
}

class SummaryVersionsCompanion extends UpdateCompanion<SummaryVersion> {
  final Value<int> id;
  final Value<String> localDate;
  final Value<String> timeZone;
  final Value<String?> inputSnapshotRef;
  final Value<String?> inputSnapshotHash;
  final Value<String?> providerAlias;
  final Value<String?> modelId;
  final Value<TaskStatus> taskStatus;
  final Value<bool> isCurrent;
  final Value<String?> content;
  final Value<DateTime> createdAt;
  const SummaryVersionsCompanion({
    this.id = const Value.absent(),
    this.localDate = const Value.absent(),
    this.timeZone = const Value.absent(),
    this.inputSnapshotRef = const Value.absent(),
    this.inputSnapshotHash = const Value.absent(),
    this.providerAlias = const Value.absent(),
    this.modelId = const Value.absent(),
    this.taskStatus = const Value.absent(),
    this.isCurrent = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SummaryVersionsCompanion.insert({
    this.id = const Value.absent(),
    required String localDate,
    required String timeZone,
    this.inputSnapshotRef = const Value.absent(),
    this.inputSnapshotHash = const Value.absent(),
    this.providerAlias = const Value.absent(),
    this.modelId = const Value.absent(),
    required TaskStatus taskStatus,
    this.isCurrent = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : localDate = Value(localDate),
       timeZone = Value(timeZone),
       taskStatus = Value(taskStatus);
  static Insertable<SummaryVersion> custom({
    Expression<int>? id,
    Expression<String>? localDate,
    Expression<String>? timeZone,
    Expression<String>? inputSnapshotRef,
    Expression<String>? inputSnapshotHash,
    Expression<String>? providerAlias,
    Expression<String>? modelId,
    Expression<String>? taskStatus,
    Expression<bool>? isCurrent,
    Expression<String>? content,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (localDate != null) 'local_date': localDate,
      if (timeZone != null) 'time_zone': timeZone,
      if (inputSnapshotRef != null) 'input_snapshot_ref': inputSnapshotRef,
      if (inputSnapshotHash != null) 'input_snapshot_hash': inputSnapshotHash,
      if (providerAlias != null) 'provider_alias': providerAlias,
      if (modelId != null) 'model_id': modelId,
      if (taskStatus != null) 'task_status': taskStatus,
      if (isCurrent != null) 'is_current': isCurrent,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SummaryVersionsCompanion copyWith({
    Value<int>? id,
    Value<String>? localDate,
    Value<String>? timeZone,
    Value<String?>? inputSnapshotRef,
    Value<String?>? inputSnapshotHash,
    Value<String?>? providerAlias,
    Value<String?>? modelId,
    Value<TaskStatus>? taskStatus,
    Value<bool>? isCurrent,
    Value<String?>? content,
    Value<DateTime>? createdAt,
  }) {
    return SummaryVersionsCompanion(
      id: id ?? this.id,
      localDate: localDate ?? this.localDate,
      timeZone: timeZone ?? this.timeZone,
      inputSnapshotRef: inputSnapshotRef ?? this.inputSnapshotRef,
      inputSnapshotHash: inputSnapshotHash ?? this.inputSnapshotHash,
      providerAlias: providerAlias ?? this.providerAlias,
      modelId: modelId ?? this.modelId,
      taskStatus: taskStatus ?? this.taskStatus,
      isCurrent: isCurrent ?? this.isCurrent,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (timeZone.present) {
      map['time_zone'] = Variable<String>(timeZone.value);
    }
    if (inputSnapshotRef.present) {
      map['input_snapshot_ref'] = Variable<String>(inputSnapshotRef.value);
    }
    if (inputSnapshotHash.present) {
      map['input_snapshot_hash'] = Variable<String>(inputSnapshotHash.value);
    }
    if (providerAlias.present) {
      map['provider_alias'] = Variable<String>(providerAlias.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (taskStatus.present) {
      map['task_status'] = Variable<String>(
        $SummaryVersionsTable.$convertertaskStatus.toSql(taskStatus.value),
      );
    }
    if (isCurrent.present) {
      map['is_current'] = Variable<bool>(isCurrent.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SummaryVersionsCompanion(')
          ..write('id: $id, ')
          ..write('localDate: $localDate, ')
          ..write('timeZone: $timeZone, ')
          ..write('inputSnapshotRef: $inputSnapshotRef, ')
          ..write('inputSnapshotHash: $inputSnapshotHash, ')
          ..write('providerAlias: $providerAlias, ')
          ..write('modelId: $modelId, ')
          ..write('taskStatus: $taskStatus, ')
          ..write('isCurrent: $isCurrent, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $CitationsTable extends Citations
    with TableInfo<$CitationsTable, Citation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CitationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _summaryVersionIdMeta = const VerificationMeta(
    'summaryVersionId',
  );
  @override
  late final GeneratedColumn<int> summaryVersionId = GeneratedColumn<int>(
    'summary_version_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES summary_versions (id)',
    ),
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publishedAtMeta = const VerificationMeta(
    'publishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> publishedAt = GeneratedColumn<DateTime>(
    'published_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accessedAtMeta = const VerificationMeta(
    'accessedAt',
  );
  @override
  late final GeneratedColumn<DateTime> accessedAt = GeneratedColumn<DateTime>(
    'accessed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _excerptMeta = const VerificationMeta(
    'excerpt',
  );
  @override
  late final GeneratedColumn<String> excerpt = GeneratedColumn<String>(
    'excerpt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _materialHashMeta = const VerificationMeta(
    'materialHash',
  );
  @override
  late final GeneratedColumn<String> materialHash = GeneratedColumn<String>(
    'material_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<CitationAccessMethod, String>
  accessMethod = GeneratedColumn<String>(
    'access_method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<CitationAccessMethod>($CitationsTable.$converteraccessMethod);
  static const VerificationMeta _articleIdMeta = const VerificationMeta(
    'articleId',
  );
  @override
  late final GeneratedColumn<int> articleId = GeneratedColumn<int>(
    'article_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES articles (id) ON DELETE SET NULL',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    summaryVersionId,
    sourceId,
    title,
    url,
    publishedAt,
    accessedAt,
    excerpt,
    materialHash,
    accessMethod,
    articleId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'citations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Citation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('summary_version_id')) {
      context.handle(
        _summaryVersionIdMeta,
        summaryVersionId.isAcceptableOrUnknown(
          data['summary_version_id']!,
          _summaryVersionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_summaryVersionIdMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    }
    if (data.containsKey('published_at')) {
      context.handle(
        _publishedAtMeta,
        publishedAt.isAcceptableOrUnknown(
          data['published_at']!,
          _publishedAtMeta,
        ),
      );
    }
    if (data.containsKey('accessed_at')) {
      context.handle(
        _accessedAtMeta,
        accessedAt.isAcceptableOrUnknown(data['accessed_at']!, _accessedAtMeta),
      );
    }
    if (data.containsKey('excerpt')) {
      context.handle(
        _excerptMeta,
        excerpt.isAcceptableOrUnknown(data['excerpt']!, _excerptMeta),
      );
    } else if (isInserting) {
      context.missing(_excerptMeta);
    }
    if (data.containsKey('material_hash')) {
      context.handle(
        _materialHashMeta,
        materialHash.isAcceptableOrUnknown(
          data['material_hash']!,
          _materialHashMeta,
        ),
      );
    }
    if (data.containsKey('article_id')) {
      context.handle(
        _articleIdMeta,
        articleId.isAcceptableOrUnknown(data['article_id']!, _articleIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Citation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Citation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      summaryVersionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}summary_version_id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
      publishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}published_at'],
      ),
      accessedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}accessed_at'],
      ),
      excerpt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}excerpt'],
      )!,
      materialHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}material_hash'],
      ),
      accessMethod: $CitationsTable.$converteraccessMethod.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}access_method'],
        )!,
      ),
      articleId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}article_id'],
      ),
    );
  }

  @override
  $CitationsTable createAlias(String alias) {
    return $CitationsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<CitationAccessMethod, String, String>
  $converteraccessMethod = const EnumNameConverter<CitationAccessMethod>(
    CitationAccessMethod.values,
  );
}

class Citation extends DataClass implements Insertable<Citation> {
  final int id;
  final int summaryVersionId;

  /// 材料来源标识；必须是真实获取过的材料，不允许模型编造的地址。
  final String sourceId;
  final String? title;
  final String? url;

  /// 材料发布时间（源声明，UTC）；未知为 null。
  final DateTime? publishedAt;

  /// 本机实际获取该材料的时刻（UTC）；用于区分“材料时间”与“访问时间”。
  final DateTime? accessedAt;

  /// 最小摘录（只保留支撑结论所需的片段，不为引用长期保留整篇正文）。
  final String excerpt;

  /// 材料哈希：引用校验用，避免只凭标题/URL 判断同一材料。
  final String? materialHash;

  /// 获取方式（rss / fetch / search）。
  final CitationAccessMethod accessMethod;

  /// 本地文章引用：引用指向本机文章时为该文章 ID（可空），外部来源则为 null。
  /// 用 SET NULL：文章被彻底删除时不留下指向不存在行的悬空引用，但引用记录
  /// 本身仍保留（材料哈希与摘录可继续支撑历史总结的说明性）。
  final int? articleId;
  const Citation({
    required this.id,
    required this.summaryVersionId,
    required this.sourceId,
    this.title,
    this.url,
    this.publishedAt,
    this.accessedAt,
    required this.excerpt,
    this.materialHash,
    required this.accessMethod,
    this.articleId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['summary_version_id'] = Variable<int>(summaryVersionId);
    map['source_id'] = Variable<String>(sourceId);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    if (!nullToAbsent || publishedAt != null) {
      map['published_at'] = Variable<DateTime>(publishedAt);
    }
    if (!nullToAbsent || accessedAt != null) {
      map['accessed_at'] = Variable<DateTime>(accessedAt);
    }
    map['excerpt'] = Variable<String>(excerpt);
    if (!nullToAbsent || materialHash != null) {
      map['material_hash'] = Variable<String>(materialHash);
    }
    {
      map['access_method'] = Variable<String>(
        $CitationsTable.$converteraccessMethod.toSql(accessMethod),
      );
    }
    if (!nullToAbsent || articleId != null) {
      map['article_id'] = Variable<int>(articleId);
    }
    return map;
  }

  CitationsCompanion toCompanion(bool nullToAbsent) {
    return CitationsCompanion(
      id: Value(id),
      summaryVersionId: Value(summaryVersionId),
      sourceId: Value(sourceId),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      publishedAt: publishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(publishedAt),
      accessedAt: accessedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(accessedAt),
      excerpt: Value(excerpt),
      materialHash: materialHash == null && nullToAbsent
          ? const Value.absent()
          : Value(materialHash),
      accessMethod: Value(accessMethod),
      articleId: articleId == null && nullToAbsent
          ? const Value.absent()
          : Value(articleId),
    );
  }

  factory Citation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Citation(
      id: serializer.fromJson<int>(json['id']),
      summaryVersionId: serializer.fromJson<int>(json['summaryVersionId']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      title: serializer.fromJson<String?>(json['title']),
      url: serializer.fromJson<String?>(json['url']),
      publishedAt: serializer.fromJson<DateTime?>(json['publishedAt']),
      accessedAt: serializer.fromJson<DateTime?>(json['accessedAt']),
      excerpt: serializer.fromJson<String>(json['excerpt']),
      materialHash: serializer.fromJson<String?>(json['materialHash']),
      accessMethod: $CitationsTable.$converteraccessMethod.fromJson(
        serializer.fromJson<String>(json['accessMethod']),
      ),
      articleId: serializer.fromJson<int?>(json['articleId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'summaryVersionId': serializer.toJson<int>(summaryVersionId),
      'sourceId': serializer.toJson<String>(sourceId),
      'title': serializer.toJson<String?>(title),
      'url': serializer.toJson<String?>(url),
      'publishedAt': serializer.toJson<DateTime?>(publishedAt),
      'accessedAt': serializer.toJson<DateTime?>(accessedAt),
      'excerpt': serializer.toJson<String>(excerpt),
      'materialHash': serializer.toJson<String?>(materialHash),
      'accessMethod': serializer.toJson<String>(
        $CitationsTable.$converteraccessMethod.toJson(accessMethod),
      ),
      'articleId': serializer.toJson<int?>(articleId),
    };
  }

  Citation copyWith({
    int? id,
    int? summaryVersionId,
    String? sourceId,
    Value<String?> title = const Value.absent(),
    Value<String?> url = const Value.absent(),
    Value<DateTime?> publishedAt = const Value.absent(),
    Value<DateTime?> accessedAt = const Value.absent(),
    String? excerpt,
    Value<String?> materialHash = const Value.absent(),
    CitationAccessMethod? accessMethod,
    Value<int?> articleId = const Value.absent(),
  }) => Citation(
    id: id ?? this.id,
    summaryVersionId: summaryVersionId ?? this.summaryVersionId,
    sourceId: sourceId ?? this.sourceId,
    title: title.present ? title.value : this.title,
    url: url.present ? url.value : this.url,
    publishedAt: publishedAt.present ? publishedAt.value : this.publishedAt,
    accessedAt: accessedAt.present ? accessedAt.value : this.accessedAt,
    excerpt: excerpt ?? this.excerpt,
    materialHash: materialHash.present ? materialHash.value : this.materialHash,
    accessMethod: accessMethod ?? this.accessMethod,
    articleId: articleId.present ? articleId.value : this.articleId,
  );
  Citation copyWithCompanion(CitationsCompanion data) {
    return Citation(
      id: data.id.present ? data.id.value : this.id,
      summaryVersionId: data.summaryVersionId.present
          ? data.summaryVersionId.value
          : this.summaryVersionId,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      title: data.title.present ? data.title.value : this.title,
      url: data.url.present ? data.url.value : this.url,
      publishedAt: data.publishedAt.present
          ? data.publishedAt.value
          : this.publishedAt,
      accessedAt: data.accessedAt.present
          ? data.accessedAt.value
          : this.accessedAt,
      excerpt: data.excerpt.present ? data.excerpt.value : this.excerpt,
      materialHash: data.materialHash.present
          ? data.materialHash.value
          : this.materialHash,
      accessMethod: data.accessMethod.present
          ? data.accessMethod.value
          : this.accessMethod,
      articleId: data.articleId.present ? data.articleId.value : this.articleId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Citation(')
          ..write('id: $id, ')
          ..write('summaryVersionId: $summaryVersionId, ')
          ..write('sourceId: $sourceId, ')
          ..write('title: $title, ')
          ..write('url: $url, ')
          ..write('publishedAt: $publishedAt, ')
          ..write('accessedAt: $accessedAt, ')
          ..write('excerpt: $excerpt, ')
          ..write('materialHash: $materialHash, ')
          ..write('accessMethod: $accessMethod, ')
          ..write('articleId: $articleId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    summaryVersionId,
    sourceId,
    title,
    url,
    publishedAt,
    accessedAt,
    excerpt,
    materialHash,
    accessMethod,
    articleId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Citation &&
          other.id == this.id &&
          other.summaryVersionId == this.summaryVersionId &&
          other.sourceId == this.sourceId &&
          other.title == this.title &&
          other.url == this.url &&
          other.publishedAt == this.publishedAt &&
          other.accessedAt == this.accessedAt &&
          other.excerpt == this.excerpt &&
          other.materialHash == this.materialHash &&
          other.accessMethod == this.accessMethod &&
          other.articleId == this.articleId);
}

class CitationsCompanion extends UpdateCompanion<Citation> {
  final Value<int> id;
  final Value<int> summaryVersionId;
  final Value<String> sourceId;
  final Value<String?> title;
  final Value<String?> url;
  final Value<DateTime?> publishedAt;
  final Value<DateTime?> accessedAt;
  final Value<String> excerpt;
  final Value<String?> materialHash;
  final Value<CitationAccessMethod> accessMethod;
  final Value<int?> articleId;
  const CitationsCompanion({
    this.id = const Value.absent(),
    this.summaryVersionId = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.title = const Value.absent(),
    this.url = const Value.absent(),
    this.publishedAt = const Value.absent(),
    this.accessedAt = const Value.absent(),
    this.excerpt = const Value.absent(),
    this.materialHash = const Value.absent(),
    this.accessMethod = const Value.absent(),
    this.articleId = const Value.absent(),
  });
  CitationsCompanion.insert({
    this.id = const Value.absent(),
    required int summaryVersionId,
    required String sourceId,
    this.title = const Value.absent(),
    this.url = const Value.absent(),
    this.publishedAt = const Value.absent(),
    this.accessedAt = const Value.absent(),
    required String excerpt,
    this.materialHash = const Value.absent(),
    required CitationAccessMethod accessMethod,
    this.articleId = const Value.absent(),
  }) : summaryVersionId = Value(summaryVersionId),
       sourceId = Value(sourceId),
       excerpt = Value(excerpt),
       accessMethod = Value(accessMethod);
  static Insertable<Citation> custom({
    Expression<int>? id,
    Expression<int>? summaryVersionId,
    Expression<String>? sourceId,
    Expression<String>? title,
    Expression<String>? url,
    Expression<DateTime>? publishedAt,
    Expression<DateTime>? accessedAt,
    Expression<String>? excerpt,
    Expression<String>? materialHash,
    Expression<String>? accessMethod,
    Expression<int>? articleId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (summaryVersionId != null) 'summary_version_id': summaryVersionId,
      if (sourceId != null) 'source_id': sourceId,
      if (title != null) 'title': title,
      if (url != null) 'url': url,
      if (publishedAt != null) 'published_at': publishedAt,
      if (accessedAt != null) 'accessed_at': accessedAt,
      if (excerpt != null) 'excerpt': excerpt,
      if (materialHash != null) 'material_hash': materialHash,
      if (accessMethod != null) 'access_method': accessMethod,
      if (articleId != null) 'article_id': articleId,
    });
  }

  CitationsCompanion copyWith({
    Value<int>? id,
    Value<int>? summaryVersionId,
    Value<String>? sourceId,
    Value<String?>? title,
    Value<String?>? url,
    Value<DateTime?>? publishedAt,
    Value<DateTime?>? accessedAt,
    Value<String>? excerpt,
    Value<String?>? materialHash,
    Value<CitationAccessMethod>? accessMethod,
    Value<int?>? articleId,
  }) {
    return CitationsCompanion(
      id: id ?? this.id,
      summaryVersionId: summaryVersionId ?? this.summaryVersionId,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      url: url ?? this.url,
      publishedAt: publishedAt ?? this.publishedAt,
      accessedAt: accessedAt ?? this.accessedAt,
      excerpt: excerpt ?? this.excerpt,
      materialHash: materialHash ?? this.materialHash,
      accessMethod: accessMethod ?? this.accessMethod,
      articleId: articleId ?? this.articleId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (summaryVersionId.present) {
      map['summary_version_id'] = Variable<int>(summaryVersionId.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (publishedAt.present) {
      map['published_at'] = Variable<DateTime>(publishedAt.value);
    }
    if (accessedAt.present) {
      map['accessed_at'] = Variable<DateTime>(accessedAt.value);
    }
    if (excerpt.present) {
      map['excerpt'] = Variable<String>(excerpt.value);
    }
    if (materialHash.present) {
      map['material_hash'] = Variable<String>(materialHash.value);
    }
    if (accessMethod.present) {
      map['access_method'] = Variable<String>(
        $CitationsTable.$converteraccessMethod.toSql(accessMethod.value),
      );
    }
    if (articleId.present) {
      map['article_id'] = Variable<int>(articleId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CitationsCompanion(')
          ..write('id: $id, ')
          ..write('summaryVersionId: $summaryVersionId, ')
          ..write('sourceId: $sourceId, ')
          ..write('title: $title, ')
          ..write('url: $url, ')
          ..write('publishedAt: $publishedAt, ')
          ..write('accessedAt: $accessedAt, ')
          ..write('excerpt: $excerpt, ')
          ..write('materialHash: $materialHash, ')
          ..write('accessMethod: $accessMethod, ')
          ..write('articleId: $articleId')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  /// 设置编号文本，主键。
  final String key;

  /// 值的 JSON 编码文本（类型由注册表定义，这里不解释语义）。
  final String value;

  /// 最后更新时间（UTC）。同步（T041）用它与远端比较先后。
  final DateTime updatedAt;
  const Setting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Setting copyWith({String? key, String? value, DateTime? updatedAt}) =>
      Setting(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $GroupsTable groups = $GroupsTable(this);
  late final $FeedsTable feeds = $FeedsTable(this);
  late final $ArticlesTable articles = $ArticlesTable(this);
  late final $ReadingSessionsTable readingSessions = $ReadingSessionsTable(
    this,
  );
  late final $SummaryVersionsTable summaryVersions = $SummaryVersionsTable(
    this,
  );
  late final $CitationsTable citations = $CitationsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final Index uxGroupsSyncId = Index(
    'ux_groups_sync_id',
    'CREATE UNIQUE INDEX ux_groups_sync_id ON "groups" (sync_id)',
  );
  late final Index uxFeedsSyncId = Index(
    'ux_feeds_sync_id',
    'CREATE UNIQUE INDEX ux_feeds_sync_id ON feeds (sync_id)',
  );
  late final Index uxFeedsNormalizedUrl = Index(
    'ux_feeds_normalized_url',
    'CREATE UNIQUE INDEX ux_feeds_normalized_url ON feeds (normalized_url)',
  );
  late final Index ixFeedsGroupSort = Index(
    'ix_feeds_group_sort',
    'CREATE INDEX ix_feeds_group_sort ON feeds (group_id, sort_order)',
  );
  late final Index uxArticlesFeedGuid = Index(
    'ux_articles_feed_guid',
    'CREATE UNIQUE INDEX ux_articles_feed_guid ON articles (feed_id, guid) WHERE guid IS NOT NULL',
  );
  late final Index uxArticlesFeedNormalizedLink = Index(
    'ux_articles_feed_normalized_link',
    'CREATE UNIQUE INDEX ux_articles_feed_normalized_link ON articles (feed_id, normalized_link) WHERE normalized_link IS NOT NULL',
  );
  late final Index uxArticlesFeedFingerprint = Index(
    'ux_articles_feed_fingerprint',
    'CREATE UNIQUE INDEX ux_articles_feed_fingerprint ON articles (feed_id, fallback_fingerprint) WHERE fallback_fingerprint IS NOT NULL',
  );
  late final Index ixArticlesFeedPublished = Index(
    'ix_articles_feed_published',
    'CREATE INDEX ix_articles_feed_published ON articles (feed_id, published_at)',
  );
  late final Index ixArticlesReadingState = Index(
    'ix_articles_reading_state',
    'CREATE INDEX ix_articles_reading_state ON articles (reading_state)',
  );
  late final Index ixArticlesFavorite = Index(
    'ix_articles_favorite',
    'CREATE INDEX ix_articles_favorite ON articles (favorite)',
  );
  late final Index ixArticlesBodyHash = Index(
    'ix_articles_body_hash',
    'CREATE INDEX ix_articles_body_hash ON articles (body_hash)',
  );
  late final Index ixReadingSessionsArticleStart = Index(
    'ix_reading_sessions_article_start',
    'CREATE INDEX ix_reading_sessions_article_start ON reading_sessions (article_id, started_at)',
  );
  late final Index ixReadingSessionsStarted = Index(
    'ix_reading_sessions_started',
    'CREATE INDEX ix_reading_sessions_started ON reading_sessions (started_at)',
  );
  late final Index ixSummaryVersionsLocalDate = Index(
    'ix_summary_versions_local_date',
    'CREATE INDEX ix_summary_versions_local_date ON summary_versions (local_date, time_zone)',
  );
  late final Index ixCitationsSummary = Index(
    'ix_citations_summary',
    'CREATE INDEX ix_citations_summary ON citations (summary_version_id)',
  );
  late final Index ixCitationsSource = Index(
    'ix_citations_source',
    'CREATE INDEX ix_citations_source ON citations (source_id)',
  );
  late final Index ixSettingsUpdatedAt = Index(
    'ix_settings_updated_at',
    'CREATE INDEX ix_settings_updated_at ON settings (updated_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    groups,
    feeds,
    articles,
    readingSessions,
    summaryVersions,
    citations,
    settings,
    uxGroupsSyncId,
    uxFeedsSyncId,
    uxFeedsNormalizedUrl,
    ixFeedsGroupSort,
    uxArticlesFeedGuid,
    uxArticlesFeedNormalizedLink,
    uxArticlesFeedFingerprint,
    ixArticlesFeedPublished,
    ixArticlesReadingState,
    ixArticlesFavorite,
    ixArticlesBodyHash,
    ixReadingSessionsArticleStart,
    ixReadingSessionsStarted,
    ixSummaryVersionsLocalDate,
    ixCitationsSummary,
    ixCitationsSource,
    ixSettingsUpdatedAt,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'articles',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('citations', kind: UpdateKind.update)],
    ),
  ]);
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$GroupsTableCreateCompanionBuilder = GroupsCompanion Function({
  Value<int> id,
  required String syncId,
  required String name,
  Value<int> sortOrder,
  Value<bool> pinned,
  Value<bool> isReserved,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$GroupsTableUpdateCompanionBuilder = GroupsCompanion Function({
  Value<int> id,
  Value<String> syncId,
  Value<String> name,
  Value<int> sortOrder,
  Value<bool> pinned,
  Value<bool> isReserved,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

final class $$GroupsTableReferences
    extends BaseReferences<_$AppDatabase, $GroupsTable, Group> {
  $$GroupsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$FeedsTable, List<Feed>> _feedsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.feeds,
    aliasName: 'groups__id__feeds__group_id',
  );

  $$FeedsTableProcessedTableManager get feedsRefs {
    final manager = $$FeedsTableTableManager(
      $_db,
      $_db.feeds,
    ).filter((f) => f.groupId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_feedsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$GroupsTableFilterComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isReserved => $composableBuilder(
    column: $table.isReserved,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> feedsRefs(
    Expression<bool> Function($$FeedsTableFilterComposer f) f,
  ) {
    final $$FeedsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.feeds,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedsTableFilterComposer(
            $db: $db,
            $table: $db.feeds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isReserved => $composableBuilder(
    column: $table.isReserved,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<bool> get isReserved => $composableBuilder(
    column: $table.isReserved,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> feedsRefs<T extends Object>(
    Expression<T> Function($$FeedsTableAnnotationComposer a) f,
  ) {
    final $$FeedsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.feeds,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedsTableAnnotationComposer(
            $db: $db,
            $table: $db.feeds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupsTable,
          Group,
          $$GroupsTableFilterComposer,
          $$GroupsTableOrderingComposer,
          $$GroupsTableAnnotationComposer,
          $$GroupsTableCreateCompanionBuilder,
          $$GroupsTableUpdateCompanionBuilder,
          (Group, $$GroupsTableReferences),
          Group,
          PrefetchHooks Function({bool feedsRefs})
        > {
  $$GroupsTableTableManager(_$AppDatabase db, $GroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> syncId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> isReserved = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => GroupsCompanion(
                id: id,
                syncId: syncId,
                name: name,
                sortOrder: sortOrder,
                pinned: pinned,
                isReserved: isReserved,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String syncId,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> isReserved = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => GroupsCompanion.insert(
                id: id,
                syncId: syncId,
                name: name,
                sortOrder: sortOrder,
                pinned: pinned,
                isReserved: isReserved,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GroupsTable, Group>(table),
                  $$GroupsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({feedsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (feedsRefs) db.feeds],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (feedsRefs)
                    await $_getPrefetchedData<Group, $GroupsTable, Feed>(
                      currentTable: table,
                      referencedTable: $$GroupsTableReferences._feedsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$GroupsTableReferences(db, table, p0).feedsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.groupId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$GroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupsTable,
      Group,
      $$GroupsTableFilterComposer,
      $$GroupsTableOrderingComposer,
      $$GroupsTableAnnotationComposer,
      $$GroupsTableCreateCompanionBuilder,
      $$GroupsTableUpdateCompanionBuilder,
      (Group, $$GroupsTableReferences),
      Group,
      PrefetchHooks Function({bool feedsRefs})
    >;
typedef $$FeedsTableCreateCompanionBuilder = FeedsCompanion Function({
  Value<int> id,
  required String syncId,
  required String normalizedUrl,
  required String name,
  Value<String?> sourceName,
  Value<int?> groupId,
  Value<bool> favorite,
  Value<int?> refreshIntervalMinutes,
  Value<int> sortOrder,
  Value<String?> httpEtag,
  Value<String?> httpLastModified,
  Value<String?> credentialRef,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$FeedsTableUpdateCompanionBuilder = FeedsCompanion Function({
  Value<int> id,
  Value<String> syncId,
  Value<String> normalizedUrl,
  Value<String> name,
  Value<String?> sourceName,
  Value<int?> groupId,
  Value<bool> favorite,
  Value<int?> refreshIntervalMinutes,
  Value<int> sortOrder,
  Value<String?> httpEtag,
  Value<String?> httpLastModified,
  Value<String?> credentialRef,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

final class $$FeedsTableReferences
    extends BaseReferences<_$AppDatabase, $FeedsTable, Feed> {
  $$FeedsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $GroupsTable _groupIdTable(_$AppDatabase db) =>
      db.groups.createAlias('feeds__group_id__groups__id');

  $$GroupsTableProcessedTableManager? get groupId {
    final $_column = $_itemColumn<int>('group_id');
    if ($_column == null) return null;
    final manager = $$GroupsTableTableManager(
      $_db,
      $_db.groups,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ArticlesTable, List<Article>> _articlesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.articles,
    aliasName: 'feeds__id__articles__feed_id',
  );

  $$ArticlesTableProcessedTableManager get articlesRefs {
    final manager = $$ArticlesTableTableManager(
      $_db,
      $_db.articles,
    ).filter((f) => f.feedId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_articlesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FeedsTableFilterComposer extends Composer<_$AppDatabase, $FeedsTable> {
  $$FeedsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedUrl => $composableBuilder(
    column: $table.normalizedUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get refreshIntervalMinutes => $composableBuilder(
    column: $table.refreshIntervalMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get httpEtag => $composableBuilder(
    column: $table.httpEtag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get httpLastModified => $composableBuilder(
    column: $table.httpLastModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get credentialRef => $composableBuilder(
    column: $table.credentialRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$GroupsTableFilterComposer get groupId {
    final $$GroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupsTableFilterComposer(
            $db: $db,
            $table: $db.groups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> articlesRefs(
    Expression<bool> Function($$ArticlesTableFilterComposer f) f,
  ) {
    final $$ArticlesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.articles,
      getReferencedColumn: (t) => t.feedId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticlesTableFilterComposer(
            $db: $db,
            $table: $db.articles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FeedsTableOrderingComposer
    extends Composer<_$AppDatabase, $FeedsTable> {
  $$FeedsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedUrl => $composableBuilder(
    column: $table.normalizedUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get refreshIntervalMinutes => $composableBuilder(
    column: $table.refreshIntervalMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get httpEtag => $composableBuilder(
    column: $table.httpEtag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get httpLastModified => $composableBuilder(
    column: $table.httpLastModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get credentialRef => $composableBuilder(
    column: $table.credentialRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$GroupsTableOrderingComposer get groupId {
    final $$GroupsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupsTableOrderingComposer(
            $db: $db,
            $table: $db.groups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FeedsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FeedsTable> {
  $$FeedsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<String> get normalizedUrl => $composableBuilder(
    column: $table.normalizedUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<int> get refreshIntervalMinutes => $composableBuilder(
    column: $table.refreshIntervalMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get httpEtag =>
      $composableBuilder(column: $table.httpEtag, builder: (column) => column);

  GeneratedColumn<String> get httpLastModified => $composableBuilder(
    column: $table.httpLastModified,
    builder: (column) => column,
  );

  GeneratedColumn<String> get credentialRef => $composableBuilder(
    column: $table.credentialRef,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$GroupsTableAnnotationComposer get groupId {
    final $$GroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.groups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> articlesRefs<T extends Object>(
    Expression<T> Function($$ArticlesTableAnnotationComposer a) f,
  ) {
    final $$ArticlesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.articles,
      getReferencedColumn: (t) => t.feedId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticlesTableAnnotationComposer(
            $db: $db,
            $table: $db.articles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FeedsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FeedsTable,
          Feed,
          $$FeedsTableFilterComposer,
          $$FeedsTableOrderingComposer,
          $$FeedsTableAnnotationComposer,
          $$FeedsTableCreateCompanionBuilder,
          $$FeedsTableUpdateCompanionBuilder,
          (Feed, $$FeedsTableReferences),
          Feed,
          PrefetchHooks Function({bool groupId, bool articlesRefs})
        > {
  $$FeedsTableTableManager(_$AppDatabase db, $FeedsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FeedsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FeedsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FeedsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> syncId = const Value.absent(),
                Value<String> normalizedUrl = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> sourceName = const Value.absent(),
                Value<int?> groupId = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int?> refreshIntervalMinutes = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String?> httpEtag = const Value.absent(),
                Value<String?> httpLastModified = const Value.absent(),
                Value<String?> credentialRef = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => FeedsCompanion(
                id: id,
                syncId: syncId,
                normalizedUrl: normalizedUrl,
                name: name,
                sourceName: sourceName,
                groupId: groupId,
                favorite: favorite,
                refreshIntervalMinutes: refreshIntervalMinutes,
                sortOrder: sortOrder,
                httpEtag: httpEtag,
                httpLastModified: httpLastModified,
                credentialRef: credentialRef,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String syncId,
                required String normalizedUrl,
                required String name,
                Value<String?> sourceName = const Value.absent(),
                Value<int?> groupId = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int?> refreshIntervalMinutes = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String?> httpEtag = const Value.absent(),
                Value<String?> httpLastModified = const Value.absent(),
                Value<String?> credentialRef = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => FeedsCompanion.insert(
                id: id,
                syncId: syncId,
                normalizedUrl: normalizedUrl,
                name: name,
                sourceName: sourceName,
                groupId: groupId,
                favorite: favorite,
                refreshIntervalMinutes: refreshIntervalMinutes,
                sortOrder: sortOrder,
                httpEtag: httpEtag,
                httpLastModified: httpLastModified,
                credentialRef: credentialRef,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FeedsTable, Feed>(table),
                  $$FeedsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({groupId = false, articlesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (articlesRefs) db.articles],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (groupId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.groupId,
                        referencedTable: $$FeedsTableReferences._groupIdTable(
                          db,
                        ),
                        referencedColumn: $$FeedsTableReferences
                            ._groupIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (articlesRefs)
                    await $_getPrefetchedData<Feed, $FeedsTable, Article>(
                      currentTable: table,
                      referencedTable: $$FeedsTableReferences
                          ._articlesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$FeedsTableReferences(db, table, p0).articlesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.feedId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$FeedsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FeedsTable,
      Feed,
      $$FeedsTableFilterComposer,
      $$FeedsTableOrderingComposer,
      $$FeedsTableAnnotationComposer,
      $$FeedsTableCreateCompanionBuilder,
      $$FeedsTableUpdateCompanionBuilder,
      (Feed, $$FeedsTableReferences),
      Feed,
      PrefetchHooks Function({bool groupId, bool articlesRefs})
    >;
typedef $$ArticlesTableCreateCompanionBuilder = ArticlesCompanion Function({
  Value<int> id,
  required int feedId,
  Value<String?> guid,
  Value<bool> guidPresent,
  Value<String?> normalizedLink,
  Value<String?> sourceUrl,
  Value<String?> fallbackFingerprint,
  Value<FingerprintReliability?> fingerprintReliability,
  required IdentityBasis identityBasis,
  required String title,
  Value<String?> author,
  Value<DateTime?> publishedAt,
  Value<DateTime> fetchedAt,
  Value<String?> body,
  Value<BodyCompleteness> bodyCompleteness,
  Value<String?> bodyHash,
  Value<String?> summary,
  Value<ReadingState> readingState,
  Value<bool> favorite,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$ArticlesTableUpdateCompanionBuilder = ArticlesCompanion Function({
  Value<int> id,
  Value<int> feedId,
  Value<String?> guid,
  Value<bool> guidPresent,
  Value<String?> normalizedLink,
  Value<String?> sourceUrl,
  Value<String?> fallbackFingerprint,
  Value<FingerprintReliability?> fingerprintReliability,
  Value<IdentityBasis> identityBasis,
  Value<String> title,
  Value<String?> author,
  Value<DateTime?> publishedAt,
  Value<DateTime> fetchedAt,
  Value<String?> body,
  Value<BodyCompleteness> bodyCompleteness,
  Value<String?> bodyHash,
  Value<String?> summary,
  Value<ReadingState> readingState,
  Value<bool> favorite,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

final class $$ArticlesTableReferences
    extends BaseReferences<_$AppDatabase, $ArticlesTable, Article> {
  $$ArticlesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FeedsTable _feedIdTable(_$AppDatabase db) =>
      db.feeds.createAlias('articles__feed_id__feeds__id');

  $$FeedsTableProcessedTableManager get feedId {
    final $_column = $_itemColumn<int>('feed_id')!;

    final manager = $$FeedsTableTableManager(
      $_db,
      $_db.feeds,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_feedIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ReadingSessionsTable, List<ReadingSession>>
  _readingSessionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.readingSessions,
    aliasName: 'articles__id__reading_sessions__article_id',
  );

  $$ReadingSessionsTableProcessedTableManager get readingSessionsRefs {
    final manager = $$ReadingSessionsTableTableManager(
      $_db,
      $_db.readingSessions,
    ).filter((f) => f.articleId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _readingSessionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CitationsTable, List<Citation>>
  _citationsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.citations,
    aliasName: 'articles__id__citations__article_id',
  );

  $$CitationsTableProcessedTableManager get citationsRefs {
    final manager = $$CitationsTableTableManager(
      $_db,
      $_db.citations,
    ).filter((f) => f.articleId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_citationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ArticlesTableFilterComposer
    extends Composer<_$AppDatabase, $ArticlesTable> {
  $$ArticlesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get guid => $composableBuilder(
    column: $table.guid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get guidPresent => $composableBuilder(
    column: $table.guidPresent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedLink => $composableBuilder(
    column: $table.normalizedLink,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceUrl => $composableBuilder(
    column: $table.sourceUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fallbackFingerprint => $composableBuilder(
    column: $table.fallbackFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    FingerprintReliability?,
    FingerprintReliability,
    String
  >
  get fingerprintReliability => $composableBuilder(
    column: $table.fingerprintReliability,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<IdentityBasis, IdentityBasis, String>
  get identityBasis => $composableBuilder(
    column: $table.identityBasis,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<BodyCompleteness, BodyCompleteness, String>
  get bodyCompleteness => $composableBuilder(
    column: $table.bodyCompleteness,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get bodyHash => $composableBuilder(
    column: $table.bodyHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ReadingState, ReadingState, String>
  get readingState => $composableBuilder(
    column: $table.readingState,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$FeedsTableFilterComposer get feedId {
    final $$FeedsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.feedId,
      referencedTable: $db.feeds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedsTableFilterComposer(
            $db: $db,
            $table: $db.feeds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> readingSessionsRefs(
    Expression<bool> Function($$ReadingSessionsTableFilterComposer f) f,
  ) {
    final $$ReadingSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.readingSessions,
      getReferencedColumn: (t) => t.articleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReadingSessionsTableFilterComposer(
            $db: $db,
            $table: $db.readingSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> citationsRefs(
    Expression<bool> Function($$CitationsTableFilterComposer f) f,
  ) {
    final $$CitationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.citations,
      getReferencedColumn: (t) => t.articleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CitationsTableFilterComposer(
            $db: $db,
            $table: $db.citations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ArticlesTableOrderingComposer
    extends Composer<_$AppDatabase, $ArticlesTable> {
  $$ArticlesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get guid => $composableBuilder(
    column: $table.guid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get guidPresent => $composableBuilder(
    column: $table.guidPresent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedLink => $composableBuilder(
    column: $table.normalizedLink,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceUrl => $composableBuilder(
    column: $table.sourceUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fallbackFingerprint => $composableBuilder(
    column: $table.fallbackFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprintReliability => $composableBuilder(
    column: $table.fingerprintReliability,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identityBasis => $composableBuilder(
    column: $table.identityBasis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyCompleteness => $composableBuilder(
    column: $table.bodyCompleteness,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyHash => $composableBuilder(
    column: $table.bodyHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get readingState => $composableBuilder(
    column: $table.readingState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$FeedsTableOrderingComposer get feedId {
    final $$FeedsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.feedId,
      referencedTable: $db.feeds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedsTableOrderingComposer(
            $db: $db,
            $table: $db.feeds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ArticlesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArticlesTable> {
  $$ArticlesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get guid =>
      $composableBuilder(column: $table.guid, builder: (column) => column);

  GeneratedColumn<bool> get guidPresent => $composableBuilder(
    column: $table.guidPresent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get normalizedLink => $composableBuilder(
    column: $table.normalizedLink,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceUrl =>
      $composableBuilder(column: $table.sourceUrl, builder: (column) => column);

  GeneratedColumn<String> get fallbackFingerprint => $composableBuilder(
    column: $table.fallbackFingerprint,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<FingerprintReliability?, String>
  get fingerprintReliability => $composableBuilder(
    column: $table.fingerprintReliability,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<IdentityBasis, String> get identityBasis =>
      $composableBuilder(
        column: $table.identityBasis,
        builder: (column) => column,
      );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumnWithTypeConverter<BodyCompleteness, String>
  get bodyCompleteness => $composableBuilder(
    column: $table.bodyCompleteness,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bodyHash =>
      $composableBuilder(column: $table.bodyHash, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ReadingState, String> get readingState =>
      $composableBuilder(
        column: $table.readingState,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$FeedsTableAnnotationComposer get feedId {
    final $$FeedsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.feedId,
      referencedTable: $db.feeds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedsTableAnnotationComposer(
            $db: $db,
            $table: $db.feeds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> readingSessionsRefs<T extends Object>(
    Expression<T> Function($$ReadingSessionsTableAnnotationComposer a) f,
  ) {
    final $$ReadingSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.readingSessions,
      getReferencedColumn: (t) => t.articleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReadingSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.readingSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> citationsRefs<T extends Object>(
    Expression<T> Function($$CitationsTableAnnotationComposer a) f,
  ) {
    final $$CitationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.citations,
      getReferencedColumn: (t) => t.articleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CitationsTableAnnotationComposer(
            $db: $db,
            $table: $db.citations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ArticlesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ArticlesTable,
          Article,
          $$ArticlesTableFilterComposer,
          $$ArticlesTableOrderingComposer,
          $$ArticlesTableAnnotationComposer,
          $$ArticlesTableCreateCompanionBuilder,
          $$ArticlesTableUpdateCompanionBuilder,
          (Article, $$ArticlesTableReferences),
          Article,
          PrefetchHooks Function({
            bool feedId,
            bool readingSessionsRefs,
            bool citationsRefs,
          })
        > {
  $$ArticlesTableTableManager(_$AppDatabase db, $ArticlesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArticlesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArticlesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArticlesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> feedId = const Value.absent(),
                Value<String?> guid = const Value.absent(),
                Value<bool> guidPresent = const Value.absent(),
                Value<String?> normalizedLink = const Value.absent(),
                Value<String?> sourceUrl = const Value.absent(),
                Value<String?> fallbackFingerprint = const Value.absent(),
                Value<FingerprintReliability?> fingerprintReliability =
                    const Value.absent(),
                Value<IdentityBasis> identityBasis = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<DateTime?> publishedAt = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<String?> body = const Value.absent(),
                Value<BodyCompleteness> bodyCompleteness = const Value.absent(),
                Value<String?> bodyHash = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<ReadingState> readingState = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ArticlesCompanion(
                id: id,
                feedId: feedId,
                guid: guid,
                guidPresent: guidPresent,
                normalizedLink: normalizedLink,
                sourceUrl: sourceUrl,
                fallbackFingerprint: fallbackFingerprint,
                fingerprintReliability: fingerprintReliability,
                identityBasis: identityBasis,
                title: title,
                author: author,
                publishedAt: publishedAt,
                fetchedAt: fetchedAt,
                body: body,
                bodyCompleteness: bodyCompleteness,
                bodyHash: bodyHash,
                summary: summary,
                readingState: readingState,
                favorite: favorite,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int feedId,
                Value<String?> guid = const Value.absent(),
                Value<bool> guidPresent = const Value.absent(),
                Value<String?> normalizedLink = const Value.absent(),
                Value<String?> sourceUrl = const Value.absent(),
                Value<String?> fallbackFingerprint = const Value.absent(),
                Value<FingerprintReliability?> fingerprintReliability =
                    const Value.absent(),
                required IdentityBasis identityBasis,
                required String title,
                Value<String?> author = const Value.absent(),
                Value<DateTime?> publishedAt = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<String?> body = const Value.absent(),
                Value<BodyCompleteness> bodyCompleteness = const Value.absent(),
                Value<String?> bodyHash = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<ReadingState> readingState = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ArticlesCompanion.insert(
                id: id,
                feedId: feedId,
                guid: guid,
                guidPresent: guidPresent,
                normalizedLink: normalizedLink,
                sourceUrl: sourceUrl,
                fallbackFingerprint: fallbackFingerprint,
                fingerprintReliability: fingerprintReliability,
                identityBasis: identityBasis,
                title: title,
                author: author,
                publishedAt: publishedAt,
                fetchedAt: fetchedAt,
                body: body,
                bodyCompleteness: bodyCompleteness,
                bodyHash: bodyHash,
                summary: summary,
                readingState: readingState,
                favorite: favorite,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ArticlesTable, Article>(table),
                  $$ArticlesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                feedId = false,
                readingSessionsRefs = false,
                citationsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (readingSessionsRefs) db.readingSessions,
                    if (citationsRefs) db.citations,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (feedId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.feedId,
                            referencedTable: $$ArticlesTableReferences
                                ._feedIdTable(db),
                            referencedColumn: $$ArticlesTableReferences
                                ._feedIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (readingSessionsRefs)
                        await $_getPrefetchedData<
                          Article,
                          $ArticlesTable,
                          ReadingSession
                        >(
                          currentTable: table,
                          referencedTable: $$ArticlesTableReferences
                              ._readingSessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ArticlesTableReferences(
                                db,
                                table,
                                p0,
                              ).readingSessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.articleId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (citationsRefs)
                        await $_getPrefetchedData<
                          Article,
                          $ArticlesTable,
                          Citation
                        >(
                          currentTable: table,
                          referencedTable: $$ArticlesTableReferences
                              ._citationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ArticlesTableReferences(
                                db,
                                table,
                                p0,
                              ).citationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.articleId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ArticlesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ArticlesTable,
      Article,
      $$ArticlesTableFilterComposer,
      $$ArticlesTableOrderingComposer,
      $$ArticlesTableAnnotationComposer,
      $$ArticlesTableCreateCompanionBuilder,
      $$ArticlesTableUpdateCompanionBuilder,
      (Article, $$ArticlesTableReferences),
      Article,
      PrefetchHooks Function({
        bool feedId,
        bool readingSessionsRefs,
        bool citationsRefs,
      })
    >;
typedef $$ReadingSessionsTableCreateCompanionBuilder =
    ReadingSessionsCompanion Function({
      Value<int> id,
      required int articleId,
      required DateTime startedAt,
      Value<DateTime?> endedAt,
      Value<int> effectiveSeconds,
      required String timeZone,
      required String localDate,
    });
typedef $$ReadingSessionsTableUpdateCompanionBuilder =
    ReadingSessionsCompanion Function({
      Value<int> id,
      Value<int> articleId,
      Value<DateTime> startedAt,
      Value<DateTime?> endedAt,
      Value<int> effectiveSeconds,
      Value<String> timeZone,
      Value<String> localDate,
    });

final class $$ReadingSessionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $ReadingSessionsTable, ReadingSession> {
  $$ReadingSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ArticlesTable _articleIdTable(_$AppDatabase db) =>
      db.articles.createAlias('reading_sessions__article_id__articles__id');

  $$ArticlesTableProcessedTableManager get articleId {
    final $_column = $_itemColumn<int>('article_id')!;

    final manager = $$ArticlesTableTableManager(
      $_db,
      $_db.articles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_articleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReadingSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingSessionsTable> {
  $$ReadingSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get effectiveSeconds => $composableBuilder(
    column: $table.effectiveSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeZone => $composableBuilder(
    column: $table.timeZone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  $$ArticlesTableFilterComposer get articleId {
    final $$ArticlesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.articleId,
      referencedTable: $db.articles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticlesTableFilterComposer(
            $db: $db,
            $table: $db.articles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingSessionsTable> {
  $$ReadingSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get effectiveSeconds => $composableBuilder(
    column: $table.effectiveSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeZone => $composableBuilder(
    column: $table.timeZone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  $$ArticlesTableOrderingComposer get articleId {
    final $$ArticlesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.articleId,
      referencedTable: $db.articles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticlesTableOrderingComposer(
            $db: $db,
            $table: $db.articles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingSessionsTable> {
  $$ReadingSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get effectiveSeconds => $composableBuilder(
    column: $table.effectiveSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get timeZone =>
      $composableBuilder(column: $table.timeZone, builder: (column) => column);

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  $$ArticlesTableAnnotationComposer get articleId {
    final $$ArticlesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.articleId,
      referencedTable: $db.articles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticlesTableAnnotationComposer(
            $db: $db,
            $table: $db.articles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingSessionsTable,
          ReadingSession,
          $$ReadingSessionsTableFilterComposer,
          $$ReadingSessionsTableOrderingComposer,
          $$ReadingSessionsTableAnnotationComposer,
          $$ReadingSessionsTableCreateCompanionBuilder,
          $$ReadingSessionsTableUpdateCompanionBuilder,
          (ReadingSession, $$ReadingSessionsTableReferences),
          ReadingSession,
          PrefetchHooks Function({bool articleId})
        > {
  $$ReadingSessionsTableTableManager(
    _$AppDatabase db,
    $ReadingSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReadingSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> articleId = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> effectiveSeconds = const Value.absent(),
                Value<String> timeZone = const Value.absent(),
                Value<String> localDate = const Value.absent(),
              }) => ReadingSessionsCompanion(
                id: id,
                articleId: articleId,
                startedAt: startedAt,
                endedAt: endedAt,
                effectiveSeconds: effectiveSeconds,
                timeZone: timeZone,
                localDate: localDate,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int articleId,
                required DateTime startedAt,
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> effectiveSeconds = const Value.absent(),
                required String timeZone,
                required String localDate,
              }) => ReadingSessionsCompanion.insert(
                id: id,
                articleId: articleId,
                startedAt: startedAt,
                endedAt: endedAt,
                effectiveSeconds: effectiveSeconds,
                timeZone: timeZone,
                localDate: localDate,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReadingSessionsTable, ReadingSession>(table),
                  $$ReadingSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({articleId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (articleId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.articleId,
                        referencedTable: $$ReadingSessionsTableReferences
                            ._articleIdTable(db),
                        referencedColumn: $$ReadingSessionsTableReferences
                            ._articleIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReadingSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingSessionsTable,
      ReadingSession,
      $$ReadingSessionsTableFilterComposer,
      $$ReadingSessionsTableOrderingComposer,
      $$ReadingSessionsTableAnnotationComposer,
      $$ReadingSessionsTableCreateCompanionBuilder,
      $$ReadingSessionsTableUpdateCompanionBuilder,
      (ReadingSession, $$ReadingSessionsTableReferences),
      ReadingSession,
      PrefetchHooks Function({bool articleId})
    >;
typedef $$SummaryVersionsTableCreateCompanionBuilder =
    SummaryVersionsCompanion Function({
      Value<int> id,
      required String localDate,
      required String timeZone,
      Value<String?> inputSnapshotRef,
      Value<String?> inputSnapshotHash,
      Value<String?> providerAlias,
      Value<String?> modelId,
      required TaskStatus taskStatus,
      Value<bool> isCurrent,
      Value<String?> content,
      Value<DateTime> createdAt,
    });
typedef $$SummaryVersionsTableUpdateCompanionBuilder =
    SummaryVersionsCompanion Function({
      Value<int> id,
      Value<String> localDate,
      Value<String> timeZone,
      Value<String?> inputSnapshotRef,
      Value<String?> inputSnapshotHash,
      Value<String?> providerAlias,
      Value<String?> modelId,
      Value<TaskStatus> taskStatus,
      Value<bool> isCurrent,
      Value<String?> content,
      Value<DateTime> createdAt,
    });

final class $$SummaryVersionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $SummaryVersionsTable, SummaryVersion> {
  $$SummaryVersionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$CitationsTable, List<Citation>>
  _citationsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.citations,
    aliasName: 'summary_versions__id__citations__summary_version_id',
  );

  $$CitationsTableProcessedTableManager get citationsRefs {
    final manager = $$CitationsTableTableManager(
      $_db,
      $_db.citations,
    ).filter((f) => f.summaryVersionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_citationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SummaryVersionsTableFilterComposer
    extends Composer<_$AppDatabase, $SummaryVersionsTable> {
  $$SummaryVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeZone => $composableBuilder(
    column: $table.timeZone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputSnapshotRef => $composableBuilder(
    column: $table.inputSnapshotRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputSnapshotHash => $composableBuilder(
    column: $table.inputSnapshotHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerAlias => $composableBuilder(
    column: $table.providerAlias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TaskStatus, TaskStatus, String>
  get taskStatus => $composableBuilder(
    column: $table.taskStatus,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get isCurrent => $composableBuilder(
    column: $table.isCurrent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> citationsRefs(
    Expression<bool> Function($$CitationsTableFilterComposer f) f,
  ) {
    final $$CitationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.citations,
      getReferencedColumn: (t) => t.summaryVersionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CitationsTableFilterComposer(
            $db: $db,
            $table: $db.citations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SummaryVersionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SummaryVersionsTable> {
  $$SummaryVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeZone => $composableBuilder(
    column: $table.timeZone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputSnapshotRef => $composableBuilder(
    column: $table.inputSnapshotRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputSnapshotHash => $composableBuilder(
    column: $table.inputSnapshotHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerAlias => $composableBuilder(
    column: $table.providerAlias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskStatus => $composableBuilder(
    column: $table.taskStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCurrent => $composableBuilder(
    column: $table.isCurrent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SummaryVersionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SummaryVersionsTable> {
  $$SummaryVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumn<String> get timeZone =>
      $composableBuilder(column: $table.timeZone, builder: (column) => column);

  GeneratedColumn<String> get inputSnapshotRef => $composableBuilder(
    column: $table.inputSnapshotRef,
    builder: (column) => column,
  );

  GeneratedColumn<String> get inputSnapshotHash => $composableBuilder(
    column: $table.inputSnapshotHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get providerAlias => $composableBuilder(
    column: $table.providerAlias,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TaskStatus, String> get taskStatus =>
      $composableBuilder(
        column: $table.taskStatus,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get isCurrent =>
      $composableBuilder(column: $table.isCurrent, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> citationsRefs<T extends Object>(
    Expression<T> Function($$CitationsTableAnnotationComposer a) f,
  ) {
    final $$CitationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.citations,
      getReferencedColumn: (t) => t.summaryVersionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CitationsTableAnnotationComposer(
            $db: $db,
            $table: $db.citations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SummaryVersionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SummaryVersionsTable,
          SummaryVersion,
          $$SummaryVersionsTableFilterComposer,
          $$SummaryVersionsTableOrderingComposer,
          $$SummaryVersionsTableAnnotationComposer,
          $$SummaryVersionsTableCreateCompanionBuilder,
          $$SummaryVersionsTableUpdateCompanionBuilder,
          (SummaryVersion, $$SummaryVersionsTableReferences),
          SummaryVersion,
          PrefetchHooks Function({bool citationsRefs})
        > {
  $$SummaryVersionsTableTableManager(
    _$AppDatabase db,
    $SummaryVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SummaryVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SummaryVersionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SummaryVersionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> localDate = const Value.absent(),
                Value<String> timeZone = const Value.absent(),
                Value<String?> inputSnapshotRef = const Value.absent(),
                Value<String?> inputSnapshotHash = const Value.absent(),
                Value<String?> providerAlias = const Value.absent(),
                Value<String?> modelId = const Value.absent(),
                Value<TaskStatus> taskStatus = const Value.absent(),
                Value<bool> isCurrent = const Value.absent(),
                Value<String?> content = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SummaryVersionsCompanion(
                id: id,
                localDate: localDate,
                timeZone: timeZone,
                inputSnapshotRef: inputSnapshotRef,
                inputSnapshotHash: inputSnapshotHash,
                providerAlias: providerAlias,
                modelId: modelId,
                taskStatus: taskStatus,
                isCurrent: isCurrent,
                content: content,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String localDate,
                required String timeZone,
                Value<String?> inputSnapshotRef = const Value.absent(),
                Value<String?> inputSnapshotHash = const Value.absent(),
                Value<String?> providerAlias = const Value.absent(),
                Value<String?> modelId = const Value.absent(),
                required TaskStatus taskStatus,
                Value<bool> isCurrent = const Value.absent(),
                Value<String?> content = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SummaryVersionsCompanion.insert(
                id: id,
                localDate: localDate,
                timeZone: timeZone,
                inputSnapshotRef: inputSnapshotRef,
                inputSnapshotHash: inputSnapshotHash,
                providerAlias: providerAlias,
                modelId: modelId,
                taskStatus: taskStatus,
                isCurrent: isCurrent,
                content: content,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SummaryVersionsTable, SummaryVersion>(table),
                  $$SummaryVersionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({citationsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (citationsRefs) db.citations],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (citationsRefs)
                    await $_getPrefetchedData<
                      SummaryVersion,
                      $SummaryVersionsTable,
                      Citation
                    >(
                      currentTable: table,
                      referencedTable: $$SummaryVersionsTableReferences
                          ._citationsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$SummaryVersionsTableReferences(
                            db,
                            table,
                            p0,
                          ).citationsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.summaryVersionId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SummaryVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SummaryVersionsTable,
      SummaryVersion,
      $$SummaryVersionsTableFilterComposer,
      $$SummaryVersionsTableOrderingComposer,
      $$SummaryVersionsTableAnnotationComposer,
      $$SummaryVersionsTableCreateCompanionBuilder,
      $$SummaryVersionsTableUpdateCompanionBuilder,
      (SummaryVersion, $$SummaryVersionsTableReferences),
      SummaryVersion,
      PrefetchHooks Function({bool citationsRefs})
    >;
typedef $$CitationsTableCreateCompanionBuilder = CitationsCompanion Function({
  Value<int> id,
  required int summaryVersionId,
  required String sourceId,
  Value<String?> title,
  Value<String?> url,
  Value<DateTime?> publishedAt,
  Value<DateTime?> accessedAt,
  required String excerpt,
  Value<String?> materialHash,
  required CitationAccessMethod accessMethod,
  Value<int?> articleId,
});
typedef $$CitationsTableUpdateCompanionBuilder = CitationsCompanion Function({
  Value<int> id,
  Value<int> summaryVersionId,
  Value<String> sourceId,
  Value<String?> title,
  Value<String?> url,
  Value<DateTime?> publishedAt,
  Value<DateTime?> accessedAt,
  Value<String> excerpt,
  Value<String?> materialHash,
  Value<CitationAccessMethod> accessMethod,
  Value<int?> articleId,
});

final class $$CitationsTableReferences
    extends BaseReferences<_$AppDatabase, $CitationsTable, Citation> {
  $$CitationsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SummaryVersionsTable _summaryVersionIdTable(_$AppDatabase db) => db
      .summaryVersions
      .createAlias('citations__summary_version_id__summary_versions__id');

  $$SummaryVersionsTableProcessedTableManager get summaryVersionId {
    final $_column = $_itemColumn<int>('summary_version_id')!;

    final manager = $$SummaryVersionsTableTableManager(
      $_db,
      $_db.summaryVersions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_summaryVersionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ArticlesTable _articleIdTable(_$AppDatabase db) =>
      db.articles.createAlias('citations__article_id__articles__id');

  $$ArticlesTableProcessedTableManager? get articleId {
    final $_column = $_itemColumn<int>('article_id');
    if ($_column == null) return null;
    final manager = $$ArticlesTableTableManager(
      $_db,
      $_db.articles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_articleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CitationsTableFilterComposer
    extends Composer<_$AppDatabase, $CitationsTable> {
  $$CitationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get accessedAt => $composableBuilder(
    column: $table.accessedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get excerpt => $composableBuilder(
    column: $table.excerpt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get materialHash => $composableBuilder(
    column: $table.materialHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    CitationAccessMethod,
    CitationAccessMethod,
    String
  >
  get accessMethod => $composableBuilder(
    column: $table.accessMethod,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  $$SummaryVersionsTableFilterComposer get summaryVersionId {
    final $$SummaryVersionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.summaryVersionId,
      referencedTable: $db.summaryVersions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SummaryVersionsTableFilterComposer(
            $db: $db,
            $table: $db.summaryVersions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ArticlesTableFilterComposer get articleId {
    final $$ArticlesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.articleId,
      referencedTable: $db.articles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticlesTableFilterComposer(
            $db: $db,
            $table: $db.articles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CitationsTableOrderingComposer
    extends Composer<_$AppDatabase, $CitationsTable> {
  $$CitationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get accessedAt => $composableBuilder(
    column: $table.accessedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get excerpt => $composableBuilder(
    column: $table.excerpt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get materialHash => $composableBuilder(
    column: $table.materialHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accessMethod => $composableBuilder(
    column: $table.accessMethod,
    builder: (column) => ColumnOrderings(column),
  );

  $$SummaryVersionsTableOrderingComposer get summaryVersionId {
    final $$SummaryVersionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.summaryVersionId,
      referencedTable: $db.summaryVersions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SummaryVersionsTableOrderingComposer(
            $db: $db,
            $table: $db.summaryVersions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ArticlesTableOrderingComposer get articleId {
    final $$ArticlesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.articleId,
      referencedTable: $db.articles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticlesTableOrderingComposer(
            $db: $db,
            $table: $db.articles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CitationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CitationsTable> {
  $$CitationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get accessedAt => $composableBuilder(
    column: $table.accessedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get excerpt =>
      $composableBuilder(column: $table.excerpt, builder: (column) => column);

  GeneratedColumn<String> get materialHash => $composableBuilder(
    column: $table.materialHash,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<CitationAccessMethod, String>
  get accessMethod => $composableBuilder(
    column: $table.accessMethod,
    builder: (column) => column,
  );

  $$SummaryVersionsTableAnnotationComposer get summaryVersionId {
    final $$SummaryVersionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.summaryVersionId,
      referencedTable: $db.summaryVersions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SummaryVersionsTableAnnotationComposer(
            $db: $db,
            $table: $db.summaryVersions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ArticlesTableAnnotationComposer get articleId {
    final $$ArticlesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.articleId,
      referencedTable: $db.articles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticlesTableAnnotationComposer(
            $db: $db,
            $table: $db.articles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CitationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CitationsTable,
          Citation,
          $$CitationsTableFilterComposer,
          $$CitationsTableOrderingComposer,
          $$CitationsTableAnnotationComposer,
          $$CitationsTableCreateCompanionBuilder,
          $$CitationsTableUpdateCompanionBuilder,
          (Citation, $$CitationsTableReferences),
          Citation,
          PrefetchHooks Function({bool summaryVersionId, bool articleId})
        > {
  $$CitationsTableTableManager(_$AppDatabase db, $CitationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CitationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CitationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CitationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> summaryVersionId = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<DateTime?> publishedAt = const Value.absent(),
                Value<DateTime?> accessedAt = const Value.absent(),
                Value<String> excerpt = const Value.absent(),
                Value<String?> materialHash = const Value.absent(),
                Value<CitationAccessMethod> accessMethod = const Value.absent(),
                Value<int?> articleId = const Value.absent(),
              }) => CitationsCompanion(
                id: id,
                summaryVersionId: summaryVersionId,
                sourceId: sourceId,
                title: title,
                url: url,
                publishedAt: publishedAt,
                accessedAt: accessedAt,
                excerpt: excerpt,
                materialHash: materialHash,
                accessMethod: accessMethod,
                articleId: articleId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int summaryVersionId,
                required String sourceId,
                Value<String?> title = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<DateTime?> publishedAt = const Value.absent(),
                Value<DateTime?> accessedAt = const Value.absent(),
                required String excerpt,
                Value<String?> materialHash = const Value.absent(),
                required CitationAccessMethod accessMethod,
                Value<int?> articleId = const Value.absent(),
              }) => CitationsCompanion.insert(
                id: id,
                summaryVersionId: summaryVersionId,
                sourceId: sourceId,
                title: title,
                url: url,
                publishedAt: publishedAt,
                accessedAt: accessedAt,
                excerpt: excerpt,
                materialHash: materialHash,
                accessMethod: accessMethod,
                articleId: articleId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CitationsTable, Citation>(table),
                  $$CitationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({summaryVersionId = false, articleId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (summaryVersionId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.summaryVersionId,
                            referencedTable: $$CitationsTableReferences
                                ._summaryVersionIdTable(db),
                            referencedColumn: $$CitationsTableReferences
                                ._summaryVersionIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (articleId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.articleId,
                            referencedTable: $$CitationsTableReferences
                                ._articleIdTable(db),
                            referencedColumn: $$CitationsTableReferences
                                ._articleIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$CitationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CitationsTable,
      Citation,
      $$CitationsTableFilterComposer,
      $$CitationsTableOrderingComposer,
      $$CitationsTableAnnotationComposer,
      $$CitationsTableCreateCompanionBuilder,
      $$CitationsTableUpdateCompanionBuilder,
      (Citation, $$CitationsTableReferences),
      Citation,
      PrefetchHooks Function({bool summaryVersionId, bool articleId})
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, Setting>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, Setting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$GroupsTableTableManager get groups =>
      $$GroupsTableTableManager(_db, _db.groups);
  $$FeedsTableTableManager get feeds =>
      $$FeedsTableTableManager(_db, _db.feeds);
  $$ArticlesTableTableManager get articles =>
      $$ArticlesTableTableManager(_db, _db.articles);
  $$ReadingSessionsTableTableManager get readingSessions =>
      $$ReadingSessionsTableTableManager(_db, _db.readingSessions);
  $$SummaryVersionsTableTableManager get summaryVersions =>
      $$SummaryVersionsTableTableManager(_db, _db.summaryVersions);
  $$CitationsTableTableManager get citations =>
      $$CitationsTableTableManager(_db, _db.citations);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
