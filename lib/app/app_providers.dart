// 组合根（T011，架构第 2.2 节「组合入口负责注入具体实现」）。
//
// 本文件是**唯一**知道「哪个接口用哪个基础设施实现」的地方之一（另一处是
// lib/app/app_bootstrap.dart 的启动流程）。它完成 T010 遗留的第 3 条：
// 把数据库、设置仓储、凭据存储与诊断日志接到应用启动流程上。
//
// 为什么 Provider 定义在 app 层而不是 infrastructure：
//   - Riverpod 的 Provider 是**装配**概念，不是实现的一部分。放进 infrastructure
//     会让 infra 依赖状态容器，也会让「哪个实现被选中」散落到多个文件；
//   - 各 Provider 的默认实现故意抛错，这样漏接线会在启动时立刻失败，而不是退化
//     成某个静默的空实现，把「已持久化/已可用」演得像真的一样。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override 类型在 riverpod 3 的 misc 入口（flutter_riverpod.dart 不再导出它）。
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:flux/features/onboarding/application/onboarding_state.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/platform/credential_store.dart';

import 'app_bootstrap.dart';

/// 打开（或已确认无法打开）的本地数据库句柄。
///
/// 故意没有默认实现：「数据库还没准备好就有人读它」是必须尽早暴露的装配错误。
/// 数据库不可用是**可诊断的正常状态**，由 [appBootstrapStatusProvider] 表达，
/// 而不是靠这里返回 null 让每个调用点各写一套空值处理。
final Provider<AppDatabase> databaseProvider = Provider<AppDatabase>(
  (Ref ref) =>
      throw StateError('databaseProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart'),
);

/// 凭据存储（T010 交付的能力）。
final Provider<CredentialStore> credentialStoreProvider =
    Provider<CredentialStore>(
      (Ref ref) => throw StateError(
        'credentialStoreProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
      ),
    );

/// 诊断日志（T010 交付的能力）。
final Provider<DiagnosticLog> diagnosticLogProvider = Provider<DiagnosticLog>(
  (Ref ref) => throw StateError(
    'diagnosticLogProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
  ),
);

/// 启动状态：数据库是否可用，以及失败类别。
final class AppBootstrapStatus {
  /// 构造启动状态。
  const AppBootstrapStatus({required this.degraded, this.failureKind});

  /// 数据库不可用（本次运行不持久化任何改动）。
  final bool degraded;

  /// 失败类别（例如 storage），不含路径与用户内容。
  final String? failureKind;
}

/// 启动状态 Provider（由组合根注入）。
final Provider<AppBootstrapStatus> appBootstrapStatusProvider =
    Provider<AppBootstrapStatus>(
      (Ref ref) => throw StateError(
        'appBootstrapStatusProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
      ),
    );

/// 把一次启动装配结果翻译成 ProviderScope 的 overrides。
///
/// 这是唯一的装配点：main.dart 调用它，测试也用同一函数（换成内存数据库或替身），
/// 因此测试走的就是生产注入路径，不会出现「测试里能过、真实启动漏接线」。
List<Override> bootstrapOverrides(AppBootstrapResult result) {
  return <Override>[
    appBootstrapStatusProvider.overrideWithValue(
      AppBootstrapStatus(
        degraded: result.isDegraded,
        failureKind: result.databaseFailure?.kind,
      ),
    ),
    settingsStoreProvider.overrideWithValue(result.settingsStore),
    onboardingStoreProvider.overrideWithValue(result.onboardingStore),
    credentialStoreProvider.overrideWithValue(result.credentialStore),
    diagnosticLogProvider.overrideWithValue(result.diagnosticLog),
    if (result.database case final AppDatabase database)
      databaseProvider.overrideWithValue(database),
  ];
}
