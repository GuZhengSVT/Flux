// sync（WebDAV 快照、合并、冲突）目录占位 —— T041–T045 落地。
//
// 条件发布与三方合并规则见架构第 5.2 节；网络调用不得放在长数据库事务内。
//
// TODO(T043): 三方合并/条件发布/墓碑/冲突。
// TODO(T044): 同步设置页、触发排队与首次合并。
// TODO(T045): 删除与收藏保留的跨设备集成。
//
// T041 已落地（契约住在 core，实现住在 infrastructure，两者都由本目录的用例消费）：
//   core/domain/sync_projection.dart   纳入/排除的权威清单（C 类设置、订阅/分组、
//                                      三态与收藏、T036 的新闻规则；S/D 类与正文/统计排除）
//   core/domain/sync_article_key.dart  跨设备文章同步键、占位行、订阅对齐与别名
//   core/domain/sync_store.dart        同步状态端口（基线/待同步变更/墓碑/别名/占位行）
//   infrastructure/local/sync_store.dart  drift 实现
//   infrastructure/local/tables/sync_tables.dart  schema v16 的四张表
// T042 已落地：
//   core/domain/webdav.dart            能力探测判定、快照命名、manifest 与孤儿快照判据
//   infrastructure/network/webdav_client.dart  PROPFIND/GET/PUT/If-Match/DELETE/MKCOL
//   infrastructure/network/webdav_snapshot_publisher.dart  快照发布协议（含 412 重试）
library;
