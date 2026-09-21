// T010：设置仓储——类型化读写、默认值回落、秘密项拒绝。
//
// 重点验证三条不变量（对应 settings_repository.dart 顶部注释）：
//   1. 未注册编号不写；
//   2. 值必须属于取值域；
//   3. 秘密项/操作类一律拒绝——这条最关键：settings 表是明文、会被备份与同步
//      带走，凭据一旦写进去就等于违反架构第 8 节。
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/settings_repository.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    repo = SettingsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('读取与默认值', () {
    test('未写入时读到注册表默认值（调用方不必自己填默认）', () async {
      expect((await repo.read(SettingId.set059)).valueOrNull, 10);
      expect((await repo.read(SettingId.set010)).valueOrNull, isTrue);
      expect((await repo.read(SettingId.set013)).valueOrNull, isFalse);
      expect((await repo.read(SettingId.set057)).valueOrNull, '20:00');
      expect((await repo.read(SettingId.set001)).valueOrNull, 'system');
    });

    test('复合设置未写入时读到完整的默认分量', () async {
      final Object? value = (await repo.read(SettingId.set004)).valueOrNull;
      expect(value, isA<Map<Object?, Object?>>());
      final Map<Object?, Object?> map = value! as Map<Object?, Object?>;
      expect(map['opacityPercent'], 20);
      expect(map['blur'], 8);
      expect(map['brightnessPercent'], 100);
    });

    test('isOverridden 区分「读到的默认值」与「显式写入过」', () async {
      expect((await repo.isOverridden(SettingId.set059)).valueOrNull, isFalse);
      await repo.write(SettingId.set059, 30);
      expect((await repo.isOverridden(SettingId.set059)).valueOrNull, isTrue);
    });
  });

  group('写入与读回', () {
    test('写入后读回同一个值，并按 JSON 落库', () async {
      final Result<Object?> written = await repo.write(SettingId.set059, 30);
      expect(written.isOk, isTrue);
      expect((await repo.read(SettingId.set059)).valueOrNull, 30);

      // 落库形态是 JSON 文本：明文备份可直接阅读（架构 5.3）。
      final Setting row = await db.select(db.settings).getSingle();
      expect(row.key, 'SET-059');
      expect(row.value, '30');
    });

    test('重复写入是覆盖而不是追加（主键为编号）', () async {
      await repo.write(SettingId.set059, 20);
      await repo.write(SettingId.set059, 40);
      final List<Setting> rows = await db.select(db.settings).get();
      expect(rows, hasLength(1));
      expect(rows.single.value, '40');
    });

    test('复合设置可写入并原样读回', () async {
      const Map<String, Object?> value = <String, Object?>{
        'opacityPercent': 30,
        'blur': 10,
        'brightnessPercent': 120,
      };
      expect((await repo.write(SettingId.set004, value)).isOk, isTrue);
      final Map<Object?, Object?> read =
          (await repo.read(SettingId.set004)).valueOrNull!
              as Map<Object?, Object?>;
      expect(read['opacityPercent'], 30);
      expect(read['blur'], 10);
      expect(read['brightnessPercent'], 120);
    });

    test('删除后回落到默认值', () async {
      await repo.write(SettingId.set059, 30);
      expect((await repo.remove(SettingId.set059)).isOk, isTrue);
      expect((await repo.read(SettingId.set059)).valueOrNull, 10);
      // 删除不存在的项也成功（幂等）。
      expect((await repo.remove(SettingId.set059)).isOk, isTrue);
    });
  });

  group('拒绝非法写入', () {
    test('未注册编号写入失败，且表内不产生任何行', () async {
      final Result<Object?> result = await repo.write(
        const SettingId('SET-017'),
        true,
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
      expect(await db.select(db.settings).get(), isEmpty);
    });

    test('越界的值被拒绝且不落库', () async {
      final Result<Object?> result = await repo.write(SettingId.set059, 61);
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
      expect(await db.select(db.settings).get(), isEmpty);
    });

    test('类型错误的值被拒绝', () async {
      expect((await repo.write(SettingId.set059, '30')).isErr, isTrue);
      expect((await repo.write(SettingId.set010, 'true')).isErr, isTrue);
      expect((await repo.write(SettingId.set051, 'not-a-list')).isErr, isTrue);
    });

    test('**秘密项写入普通存储必须失败**（SET-031 AI API Key）', () async {
      final Result<Object?> result = await repo.write(
        SettingId.set031,
        'sk-test-not-a-real-key',
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
      expect((result.errorOrNull! as ValidationError).reason, contains('安全存储'));
      // 最关键的一条：明文表里绝不能出现这个值。
      expect(await db.select(db.settings).get(), isEmpty);
    });

    test('四个秘密项都被普通存储拒绝', () async {
      for (final SettingId id in <SettingId>[
        SettingId.set027,
        SettingId.set031,
        SettingId.set039,
        SettingId.set071,
      ]) {
        final Result<Object?> result = await repo.write(id, 'secret-value');
        expect(result.isErr, isTrue, reason: '${id.code} 必须被拒绝');
      }
      expect(await db.select(db.settings).get(), isEmpty);
    });

    test('操作类设置写入失败（不是持久设置）', () async {
      expect((await repo.write(SettingId.set042, true)).isErr, isTrue);
      expect((await repo.write(SettingId.set079, true)).isErr, isTrue);
      expect(await db.select(db.settings).get(), isEmpty);
    });

    test('读到损坏的存储值时报解析错误（不静默返回默认值）', () async {
      // 直接写一行坏 JSON，模拟旧版本/手工改动留下的脏数据。
      await db
          .into(db.settings)
          .insert(SettingsCompanion.insert(key: 'SET-059', value: '{broken'));
      final Result<Object?> read = await repo.read(SettingId.set059);
      expect(read.isErr, isTrue);
      expect(read.errorOrNull, isA<ParseError>());
    });
  });

  group('批量读取与同步投影', () {
    test('readEffective 为每个注册编号都给出有效值', () async {
      final Map<String, Object?> effective =
          (await repo.readEffective()).valueOrNull!;
      expect(effective, hasLength(70));
      expect(effective['SET-059'], 10);
      expect(effective['SET-001'], 'system');
    });

    test('readEffective 用已存值覆盖默认值', () async {
      await repo.write(SettingId.set059, 20);
      final Map<String, Object?> effective =
          (await repo.readEffective()).valueOrNull!;
      expect(effective['SET-059'], 20);
    });

    test('readSyncableCommon 只返回 C 类 31 项，且不含秘密', () async {
      final Map<String, Object?> common =
          (await repo.readSyncableCommon()).valueOrNull!;
      expect(common, hasLength(31));
      for (final String secret in <String>[
        'SET-027',
        'SET-031',
        'SET-039',
        'SET-071',
      ]) {
        expect(common.containsKey(secret), isFalse, reason: '$secret 不得进同步投影');
      }
      // 设备项（D）同样排除。
      expect(common.containsKey('SET-004'), isFalse);
      expect(common.containsKey('SET-080'), isFalse);
      // C 类代表性项存在。
      expect(common['SET-001'], 'system');
      expect(common['SET-057'], '20:00');
    });

    test('readAllStored 只返回已写入的项', () async {
      await repo.write(SettingId.set059, 20);
      await repo.write(SettingId.set001, 'en');
      final Map<String, Object?> stored =
          (await repo.readAllStored()).valueOrNull!;
      expect(stored, hasLength(2));
      expect(stored['SET-059'], 20);
      expect(stored['SET-001'], 'en');
    });
  });

  group('存储层的秘密防线（不是只靠 UI）', () {
    test('通过仓储无法把任何 S 类值写进 settings 表', () async {
      // 逐个尝试四个秘密项，并确认表始终为空。
      for (final SettingDefinition definition in SettingRegistry.secrets) {
        final Result<Object?> result = await repo.write(
          definition.id,
          'any-secret',
        );
        expect(result.isErr, isTrue);
      }
      expect(await db.select(db.settings).get(), isEmpty);
    });

    test('可存储集合与注册表的 C+D 项（68）一致', () {
      expect(SettingRegistry.storable, hasLength(64));
      // 68 可持久化项 - 4 秘密项 = 64 可进普通存储。
    });
  });
}
