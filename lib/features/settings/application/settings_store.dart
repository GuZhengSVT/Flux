// 设置读写端口（T011）。
//
// 为什么需要这一层：架构第 2.2 节规定「展示层调用用例层，用例层依赖领域规则和
// 接口；基础设施实现这些接口」，并且 features 层不得 import infrastructure
// （test/core/architecture_layering_test.dart 会实际拦截）。
// T010 的 SettingsRepository 是**基础设施实现**，它住 lib/infrastructure/local；
// 设置页需要的是「按 SET 编号读写的抽象」，因此这里定义端口，组合根
// （lib/app）把仓储适配上来。
//
// 保留的语义（与 T010 仓储一致，不在适配层丢失）：
//   - 读未存过的编号返回该编号的**默认值**，调用方不必自己补默认值；
//   - 写秘密项（S 类）与操作类必须失败，上层不得把秘密写进明文表；
//   - 失败是 [Result.err]，不是异常，也不是静默成功。
library;

import 'package:flux/core/core.dart';

/// 设置读写端口。
abstract interface class SettingsStore {
  /// 读取一个设置项（未存过时返回注册表默认值）。
  Future<Result<Object?>> readSetting(SettingId id);

  /// 写入一个设置项。
  Future<Result<Object?>> writeSetting(SettingId id, Object? value);

  /// 载入全部设置项的**有效值**（已存值覆盖默认值），键为 SET 编号。
  Future<Result<Map<String, Object?>>> readEffectiveSettings();
}
