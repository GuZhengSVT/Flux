// 提取结果的端口（T024）。
//
// 与 article_ports.dart 同一条理由（架构 2.2：页面不直接碰数据库，由组合根注入实现）：
// 默认实现一律抛错，漏接线必须在使用时立刻暴露。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/application/feed_ports.dart';

import '../domain/static_article_extractor.dart';
import 'fetch_original_article.dart';

/// 提取结果读写端口。
final Provider<ArticleExtractionStore> articleExtractionProvider =
    Provider<ArticleExtractionStore>(
      (Ref ref) => throw StateError(
        'articleExtractionProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 静态网页抓取端口（实现住在 infrastructure/network）。
final Provider<StaticPageFetcherPort> staticPageFetcherProvider =
    Provider<StaticPageFetcherPort>(
      (Ref ref) => throw StateError(
        'staticPageFetcherProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 主动获取原站全文的用例。
final Provider<FetchOriginalArticleUseCase> fetchOriginalArticleProvider =
    Provider<FetchOriginalArticleUseCase>(
      (Ref ref) => FetchOriginalArticleUseCase(
        fetcher: ref.watch(staticPageFetcherProvider),
        extractions: ref.watch(articleExtractionProvider),
        diagnostics: ref.watch(diagnosticSinkProvider),
      ),
    );

/// 抽取上限（单独暴露，便于界面与测试读取同一份口径）。
final Provider<StaticExtractionLimits> staticExtractionLimitsProvider =
    Provider<StaticExtractionLimits>(
      (Ref ref) => const StaticExtractionLimits(),
    );
