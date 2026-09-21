// 设置仓储（T010）：类型化读写 + 拒绝秘密项进普通存储。
//
// 职责边界：本文件只做「按注册表定义存取 JSON 值」，不含设置页交互，也不含同步
// 决策（T041）。所有写入都必须先过注册表校验与服务端不可绕过的可存储性判定。
//
// 三条不变量（测试逐一断言）：
//   1. 未注册编号不写——避免拼错键名产生永远读不到的幽灵配置；
//   2. 值必须属于该编号的取值域——避免设置页与存储各有一套口径；
//   3. 秘密项（S 类）与操作类（文档写明不是持久设置）一律拒绝——前者必须走
//      Keychain，后者是一次按钮点击、不是偏好。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';
import 'tables/settings_tables.dart';

/// 设置仓储：包一层类型化 API，让上层不必直接拼 companion 或处理 JSON。
final class SettingsRepository {
  /// 绑定到一个已打开的 [AppDatabase]。
  const SettingsRepository(this._db);

  final AppDatabase _db;

  /// 读取一个设置项。
  ///
  /// 没有存过（或存了 null）时返回该编号的**默认值**，因此调用方总是拿到一个
  /// 可用的值，不需要自己在每个使用点重复写默认值。未注册编号返回 [Err]。
  Future<Result<Object?>> read(SettingId id) async {
    final SettingDefinition? definition = SettingRegistry.findById(id);
    if (definition == null) {
      return Err<Object?>(unknownSettingId(id));
    }

    final Setting? row;
    try {
      row = await (_db.select(
        _db.settings,
      )..where((Settings t) => t.key.equals(id.code))).getSingleOrNull();
    } on Exception catch (error, stackTrace) {
      return Err<Object?>(
        StorageError(
          operation: 'settings.read(${id.code})',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }

    if (row == null) {
      return Ok<Object?>(definition.defaultValue);
    }

    // 读回的值也要校验：数据库里的行可能来自旧版本或手工改动，
    // 校验失败时明确报错，而不是把一个非法值当成配置使用。
    final Result<Object?> decoded = SettingsValidator.decode(id, row.value);
    if (decoded.isErr) {
      return decoded;
    }
    return Ok<Object?>(decoded.valueOrNull ?? definition.defaultValue);
  }

  /// 写入一个设置项；成功时返回被持久化的值（便于调用方确认归一化结果）。
  ///
  /// 拒绝顺序刻意如此：先判编号是否存在，再判可存储性（秘密/操作类），
  /// 最后判取值域。这样错误信息总是最具体的那一条。
  Future<Result<Object?>> write(SettingId id, Object? value) async {
    final Result<void> storable = SettingsValidator.validateStorable(id);
    if (storable.isErr) {
      return Err<Object?>(storable.errorOrNull!);
    }
    final Result<void> valid = SettingsValidator.validate(id, value);
    if (valid.isErr) {
      return Err<Object?>(valid.errorOrNull!);
    }

    try {
      await _db
          .into(_db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: id.code,
              value: SettingValueCodec.encode(value),
              updatedAt: Value<DateTime>(DateTime.now().toUtc()),
            ),
          );
    } on Exception catch (error, stackTrace) {
      return Err<Object?>(
        StorageError(
          operation: 'settings.write(${id.code})',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    return Ok<Object?>(value);
  }

  /// 删除一个已存设置项，使其回落到默认值。
  ///
  /// 未存过也视为成功（幂等），避免调用方必须区分“删了不存在的键”。
  Future<Result<void>> remove(SettingId id) async {
    final SettingDefinition? definition = SettingRegistry.findById(id);
    if (definition == null) {
      return Err<void>(unknownSettingId(id));
    }
    try {
      await (_db.delete(
        _db.settings,
      )..where((Settings t) => t.key.equals(id.code))).go();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'settings.remove(${id.code})',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    return okUnit();
  }

  /// 该编号是否已被显式写入过（区别于“读到了默认值”）。
  Future<Result<bool>> isOverridden(SettingId id) async {
    final SettingDefinition? definition = SettingRegistry.findById(id);
    if (definition == null) {
      return Err<bool>(unknownSettingId(id));
    }
    try {
      final Setting? row = await (_db.select(
        _db.settings,
      )..where((Settings t) => t.key.equals(id.code))).getSingleOrNull();
      return Ok<bool>(row != null);
    } on Exception catch (error, stackTrace) {
      return Err<bool>(
        StorageError(
          operation: 'settings.isOverridden(${id.code})',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 载入全部已存设置项（键 → 解码后的值），供设置页一次性读取。
  Future<Result<Map<String, Object?>>> readAllStored() async {
    final List<Setting> rows;
    try {
      rows = await _db.select(_db.settings).get();
    } on Exception catch (error, stackTrace) {
      return Err<Map<String, Object?>>(
        StorageError(
          operation: 'settings.readAllStored',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final Setting row in rows) {
      result[row.key] = SettingValueCodec.decodeOrNull(row.value);
    }
    return Ok<Map<String, Object?>>(result);
  }

  /// 载入全部设置项的**有效值**（已存值覆盖默认值），键为 SET 编号。
  ///
  /// 这是设置页与同步投影的读取入口：它保证每个注册编号都有值。
  Future<Result<Map<String, Object?>>> readEffective() async {
    final Result<Map<String, Object?>> stored = await readAllStored();
    if (stored.isErr) {
      return stored;
    }
    final Map<String, Object?> overrides = stored.valueOrNull!;
    final Map<String, Object?> effective = <String, Object?>{};
    for (final SettingDefinition definition in SettingRegistry.all) {
      effective[definition.id.code] = overrides.containsKey(definition.id.code)
          ? overrides[definition.id.code]
          : definition.defaultValue;
    }
    return Ok<Map<String, Object?>>(effective);
  }

  /// 只读取**可同步**（C 类）设置的有效值；T041 的投影依据。
  ///
  /// 秘密项（S）与设备项（D）在此明确排除，避免日后有人用“全部设置”直接同步。
  Future<Result<Map<String, Object?>>> readSyncableCommon() async {
    final Result<Map<String, Object?>> effective = await readEffective();
    if (effective.isErr) {
      return effective;
    }
    final Map<String, Object?> all = effective.valueOrNull!;
    final Map<String, Object?> common = <String, Object?>{};
    for (final SettingDefinition definition
        in SettingRegistry.withClassification(SettingClassification.common)) {
      common[definition.id.code] = all[definition.id.code];
    }
    return Ok<Map<String, Object?>>(common);
  }
}
