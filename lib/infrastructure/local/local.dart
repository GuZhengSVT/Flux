// infrastructure/local：SQLite/Drift、资源缓存、诊断（架构第 2.2 节）。
//
// 只有本目录（以及 infrastructure/network、infrastructure/platform）可以
// 接触平台与存储细节；presentation/application/domain 通过接口获取能力。
//
// TODO(T009): Drift 实体、索引、事务与迁移。
// TODO(T021): 媒体缓存与 LRU。
// TODO(T047): 存储分类与清理策略。
library;
