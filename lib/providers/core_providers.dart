import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../services/feed_fetcher.dart';
import '../services/full_text_extractor.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden in main()');
});

final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    ),
  );
});

final feedFetcherProvider = Provider<FeedFetcher>((ref) {
  return FeedFetcher(ref.watch(dioProvider));
});

final fullTextExtractorProvider = Provider<FullTextExtractor>((ref) {
  return FullTextExtractor(ref.watch(dioProvider));
});
