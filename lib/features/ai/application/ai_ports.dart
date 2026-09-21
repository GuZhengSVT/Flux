// AI 功能的外部端口 Provider（T025）。
//
// 为什么端口 Provider 住在 features/ai 而不是 lib/app：架构 2.2 与
// test/core/architecture_layering_test.dart 明确禁止 features 反向 import lib/app
// （T011 的设置页曾因「顺手拿个颜色」与 app 形成目录级循环，那条守则就是那次留下的）。
// 控制器需要读这些端口，因此端口必须与控制器同层或更低，由组合根覆盖。
//
// 默认实现一律**抛错**（与 settingsStoreProvider/feedCatalogProvider 一致）：
// 漏接线必须立刻暴露，而不是退化成一个静默的空实现，把「已保存/已可用」演得像真的。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

import '../domain/ai_credential_store.dart';
import '../domain/ai_model_store.dart';
import '../domain/ai_provider.dart';
import '../domain/ai_task_store.dart';

/// AI 任务的持久记录端口（T030）。
///
/// 与 [aiModelStoreProvider] 同一个理由（默认抛错、由组合根覆盖）；降级启动时由
/// 组合根接上一份「读返回空、写明确失败」的实现，而不是让这里退化成一个静默的空实现。
final Provider<AiTaskStore> aiTaskStoreProvider = Provider<AiTaskStore>(
  (Ref ref) => throw StateError(
    'aiTaskStoreProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
  ),
);

/// AI 结果缓存端口（T030）。
final Provider<AiResultCache> aiResultCacheProvider = Provider<AiResultCache>(
  (Ref ref) => throw StateError(
    'aiResultCacheProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
  ),
);

/// 模型记录读写端口。
final Provider<AiModelStore> aiModelStoreProvider = Provider<AiModelStore>(
  (Ref ref) => throw StateError(
    'aiModelStoreProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
  ),
);

/// AI 凭据端口（SET-031，真实实现是 macOS Keychain）。
final Provider<AiCredentialStore> aiCredentialStoreProvider =
    Provider<AiCredentialStore>(
      (Ref ref) => throw StateError(
        'aiCredentialStoreProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
      ),
    );

/// 适配器工厂（T026 提供真实实现；T025 期间可为空）。
///
/// 允许为空：T025 交付的是契约与模型管理，测试按钮在**没有适配器**时必须给出
/// 明确说明（「协议适配器尚未实现」），而不是让一次点击静默什么都不做。
final Provider<AiProviderFactory?> aiProviderFactoryProvider =
    Provider<AiProviderFactory?>((Ref ref) => null);

/// 诊断记录端口。
///
/// 与 features/feeds 的同名端口分开声明而不是互相 import：两个 feature 各自拥有
/// 自己的端口是既有做法（articles/feeds 都各自声明端口），跨 feature 依赖会让
/// 「删除一个 feature」变成一件需要跨目录排查的事。
final Provider<DiagnosticSink> aiDiagnosticSinkProvider =
    Provider<DiagnosticSink>(
      (Ref ref) => throw StateError(
        'aiDiagnosticSinkProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
      ),
    );
