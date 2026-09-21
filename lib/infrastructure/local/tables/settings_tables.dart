// 设置存储表（T010，schema v2）。
//
// 为什么是「一张窄表」而不是每个设置一列：
//   - SET 编号有 70 个且会随文档演进增减；一个编号一列意味着每次文档调整都要
//     改 schema、写迁移。窄表把「新增设置」降级为纯数据操作；
//   - 值的类型由 lib/core/settings 的注册表决定，这里只存 JSON 文本，因此不需要
//     为 bool/int/列表/复合对象各建一套列；
//   - C 类设置要参与同步（T041），窄表天然便于按编号做增量投影。
//
// 约束：**秘密项（S 类）绝不进入本表**。凭据走 CredentialStore（Keychain），
// 这里是明文存储、会被明文备份和同步带走，因此写入前必须经过
// SettingsValidator.validateStorable 的判定。
library;

import 'package:drift/drift.dart';

/// 一个持久化的设置项。
///
/// [key] 是 SET 编号文本（例如 `SET-004`）——直接用作主键，不引入中间代理键，
/// 这样导出/导入与同步包里的键就是文档编号，排查时不需要换算。
@TableIndex(name: 'ix_settings_updated_at', columns: {#updatedAt})
class Settings extends Table {
  /// 设置编号文本，主键。
  TextColumn get key => text()();

  /// 值的 JSON 编码文本（类型由注册表定义，这里不解释语义）。
  TextColumn get value => text()();

  /// 最后更新时间（UTC）。同步（T041）用它与远端比较先后。
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}
