// 文章阅读相关的端口 Provider（T017）。
//
// 与 features/feeds 的 feed_ports.dart 同一条理由（架构 2.2：页面不直接碰数据库，
// 由组合根注入实现）：默认实现一律抛错，漏接线必须在使用时立刻暴露，而不是退化成一个
// 空实现把「没有数据」演得像真的一样。
//
// 端口定义在 application 而不是 presentation：presentation 只画界面，用例层需要这些
// 接口，因此它们必须与用例同层或更低。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

import 'article_search_use_case.dart';

/// 文章阅读端口（列表、状态写入）。
final Provider<ArticleCatalogStore> articleCatalogProvider =
    Provider<ArticleCatalogStore>(
      (Ref ref) => throw StateError(
        'articleCatalogProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 全文检索端口（T022）。
final Provider<ArticleSearchPort> articleSearchProvider =
    Provider<ArticleSearchPort>(
      (Ref ref) => throw StateError(
        'articleSearchProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 检索用例（由检索端口 + 整行读取端口组成）。
final Provider<SearchArticlesUseCase> searchArticlesUseCaseProvider =
    Provider<SearchArticlesUseCase>(
      (Ref ref) => SearchArticlesUseCase(
        search: ref.watch(articleSearchProvider),
        articles: ref.watch(articleCatalogProvider),
      ),
    );
