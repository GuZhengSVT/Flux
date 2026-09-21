// infrastructure/local：SQLite/Drift、资源缓存、诊断（架构第 2.2 节）。
//
// 只有本目录（以及 infrastructure/network、infrastructure/platform）可以
// 接触平台与存储细节；presentation/application/domain 通过接口获取能力。
//
// T009 已落地：database.dart（AppDatabase v1、迁移策略、openAppDatabase）、
// tables/（按域拆分的表定义与枚举）、article_store.dart（幂等批量导入事务）。
// T010 已落地：database.dart 升到 v2（新增 settings 表与增量迁移）、
// settings_repository.dart（类型化设置读写，拒绝秘密项）、
// diagnostics.dart（脱敏诊断日志与保留策略）。
// 本目录不导出给 features 层直接使用：上层通过接口获取能力（架构 2.2）。
// TODO(T021): 媒体缓存与 LRU。
// TODO(T047): 存储分类与清理策略。
library;
