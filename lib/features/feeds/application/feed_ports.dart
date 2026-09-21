// 订阅功能的外部端口 Provider（T014）。
//
// 为什么端口 Provider 住在 features 而不是 lib/app：
//   test/core/architecture_layering_test.dart 明确禁止 features 反向 import lib/app
//   （T011 的设置页曾因「顺手拿个颜色」与 app 形成目录级循环，这条守则就是那次留下
//   的）。而控制器需要读这些端口，因此端口必须与控制器同层或更低。
//   T010/T011 的设置与本机引导端口正是同一做法：定义在 features，由组合根覆盖。
//
// 默认实现一律**抛错**（与 settingsStoreProvider 一致）：漏接线必须立刻暴露，
// 而不是退化成一个静默的空实现，把「已持久化」演得像真的一样。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

/// 订阅与分组的读写端口。
final Provider<FeedCatalogStore> feedCatalogProvider =
    Provider<FeedCatalogStore>(
      (Ref ref) => throw StateError(
        'feedCatalogProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
      ),
    );

/// 文章写入端口（「添加订阅」要写入首次抓取到的文章）。
final Provider<FeedArticleStore> feedArticleStoreProvider =
    Provider<FeedArticleStore>(
      (Ref ref) => throw StateError(
        'feedArticleStoreProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
      ),
    );

/// 订阅抓取端口（T013 的能力）。
final Provider<FeedFetcher> feedFetcherProvider = Provider<FeedFetcher>(
  (Ref ref) => throw StateError(
    'feedFetcherProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
  ),
);

/// 分组折叠状态的本机存储（SET-025）。
final Provider<GroupCollapseStore> groupCollapseStoreProvider =
    Provider<GroupCollapseStore>(
      (Ref ref) => throw StateError(
        'groupCollapseStoreProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
      ),
    );

/// 诊断记录端口（T013 的写入能力，由 T010 的脱敏日志实现）。
///
/// 与上面几个不同的是：它的实现（把 DiagnosticLog 适配成 DiagnosticSink）住在
/// infrastructure，因此由组合根注入；这里同样只声明默认抛错的空位。
final Provider<DiagnosticSink> diagnosticSinkProvider =
    Provider<DiagnosticSink>(
      (Ref ref) => throw StateError(
        'diagnosticSinkProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
      ),
    );
