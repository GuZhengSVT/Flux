// 数据目录的布局常量（T046 提升到 core）。
//
// 为什么从 lib/app/app_bootstrap.dart 提到 core：备份与恢复必须知道「数据库文件叫什么、
// 媒体目录叫什么」——而这两件事同时被组合根（lib/app，创建它们）与基础设施（读取/写入它们）
// 需要。基础设施 import lib/app 会形成目录级循环（app → features → infrastructure，而
// infrastructure → app 就把环闭上了），因此常量的归属必须是两边都能依赖的 core。
//
// lib/app/app_bootstrap.dart 保留同名常量（re-export 本文件），历史调用点不需要改动。
library;

/// 应用数据目录名（与包标识一致的稳定名字，便于用户定位）。
const String fluxDataDirectoryName = 'Flux';

/// 数据库文件名。
const String fluxDatabaseFileName = 'flux.sqlite';

/// 诊断日志文件名。
const String fluxDiagnosticLogFileName = 'diagnostics.log';

/// 媒体缓存目录名（T021；与数据库同放在应用数据目录下）。
///
/// 与数据库并列而不是放进系统临时目录：缓存要跨启动保留（「离线可读」依赖它），
/// 而临时目录会被系统清理。放在同一个数据目录下也让「一键清缓存」与「彻底卸载」
/// 有一个明确的边界（T047 处理清理策略）。
const String fluxMediaCacheDirectoryName = 'media';
