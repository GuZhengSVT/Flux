// lib/core 统一出口（barrel）。
//
// core 只放跨模块的稳定基础件：错误、结果、时钟、任务状态机。
// 这里**不**放任何业务模块的专有类型（文章、订阅、AI 协议），那些属于 lib/features。
library;

export 'clock.dart';
export 'domain/domain.dart';
export 'error/app_error.dart';
export 'error/secret_redaction.dart';
export 'result.dart';
export 'settings/settings.dart';
export 'task/task_snapshot.dart';
export 'task/task_status.dart';
export 'task/task_transition.dart';
