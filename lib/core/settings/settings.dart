// lib/core/settings 统一出口（barrel）。
//
// T010 交付：SET 注册表（编号、类型、默认值、范围、C/D/S 分类）与校验 API。
// 设置页（T011）、同步投影（T041）与备份（T046）都从这里取定义，不各自复制一份。
library;

export 'setting_definition.dart';
export 'setting_id.dart';
export 'settings_registry.dart';
export 'settings_validator.dart';
