// AI 任务的公共 Provider（T029/T030 的装配点）。
//
// 为什么从 presentation/ai_task_list_page.dart 挪到 application：
//   - 视觉链路（T033 的 VisualRouter）与选词解释/单文摘要（T034）都要构造一个
//     [AiTaskRunner]，而它们住在 features/ai/application（或 articles 的用例），不该
//     import 一个**页面**文件来拿装配；
//   - Provider 是装配概念，放在与实现同层或更低是既有做法（见 ai_ports 的说明）。
//     放在页面里会让「页面被替换/裁剪」意外地牵动后台任务的装配。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

import '../domain/ai_model.dart';
import 'ai_ports.dart';
import 'ai_task_budget.dart';
import 'ai_task_runner.dart';
import 'model_manager_controller.dart';
import 'persistent_ai_task_service.dart';

/// 任务预算 Provider（T029 的 SET-035/036/059/062/063）。
///
/// 从设置读值是异步的，而 Provider 的构造是同步的；因此这里用注册表默认值，由组合根或
/// 后续任务覆盖成「读用户值」的实现（读设置并生效属 T041 的同步投影范围，本任务不引入
/// 第二套设置读取路径）。
final Provider<AiTaskBudget> aiTaskBudgetProvider = Provider<AiTaskBudget>(
  (Ref ref) => const AiTaskBudget(),
);

/// 任务使用的时钟（测试覆盖成假时钟；生产用系统时钟）。
final Provider<Clock> aiTaskClockProvider = Provider<Clock>(
  (Ref ref) => const SystemClock(),
);

/// 持久任务用例 Provider（由组合根装配端口）。
final Provider<PersistentAiTaskService> persistentAiTaskServiceProvider =
    Provider<PersistentAiTaskService>((Ref ref) {
      final AiTaskBudget budget = ref.watch(aiTaskBudgetProvider);
      return PersistentAiTaskService(
        tasks: ref.watch(aiTaskStoreProvider),
        cache: ref.watch(aiResultCacheProvider),
        clock: ref.watch(aiTaskClockProvider),
        diagnostics: ref.watch(aiDiagnosticSinkProvider),
        budget: budget,
        runnerFactory: (void Function(TaskSnapshot snapshot) onSnapshot) =>
            AiTaskRunner(
              credentials: ref.watch(aiCredentialStoreProvider),
              factory: ref.watch(aiProviderFactoryProvider)!,
              diagnostics: ref.watch(aiDiagnosticSinkProvider),
              budget: budget,
              clock: ref.watch(aiTaskClockProvider),
              onSnapshot: onSnapshot,
            ),
      );
    });

/// 按当前配置构造一个 AI 任务队列（不落库、不查缓存）。
///
/// 与 [persistentAiTaskServiceProvider] 分开：那个回答「持久化地跑一次任务」（写任务行、
/// 查/写缓存、状态落库），这个回答「跑一次模型调用」。工具的受控循环、视觉分析这类
/// **中间步骤**需要的是后者——给它们一个会写任务记录与缓存的服务，会让一次中间调用在
/// 任务列表里留下一行看起来像用户任务的历史。
final Provider<AiTaskRunner> aiTaskRunnerProvider = Provider<AiTaskRunner>(
  (Ref ref) => AiTaskRunner(
    credentials: ref.watch(aiCredentialStoreProvider),
    factory: ref.watch(aiProviderFactoryProvider)!,
    diagnostics: ref.watch(aiDiagnosticSinkProvider),
    budget: ref.watch(aiTaskBudgetProvider),
    clock: ref.watch(aiTaskClockProvider),
  ),
);

/// 读启用模型（按故障转移顺序）。
final Provider<Future<Result<List<AiModel>>> Function()>
enabledModelsLoaderProvider =
    Provider<Future<Result<List<AiModel>>> Function()>(
      (Ref ref) => ref.read(modelManagerProvider).loadEnabledModels,
    );
