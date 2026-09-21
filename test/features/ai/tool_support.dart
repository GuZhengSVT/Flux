// T032 工具执行器测试的替身（端口级，全部不联网）。
//
// 为什么替身放在**端口**这一层而不是 MockClient：执行器的安全断言（地址守卫）必须
// 发生在「发出请求之前」，而端口的调用计数正是「有没有出网」的判据。用 MockClient 会
// 把断言推到 HTTP 层，那时「拒绝发生在参数校验」与「拒绝发生在连接前」就分不开了。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/tool_ports.dart';
import 'package:flux/features/ai/domain/search_credential_store.dart';
import 'package:flux/features/ai/domain/search_protocol.dart';
import 'package:flux/features/ai/domain/search_provider.dart';
import 'package:flux/features/ai/domain/search_result.dart';
import 'package:flux/features/ai/domain/search_service.dart';
import 'package:flux/features/ai/domain/search_service_store.dart';

/// 内存搜索服务存储。
final class FakeSearchServiceStore implements SearchServiceStore {
  final List<SearchService> _rows = <SearchService>[];
  int _nextId = 1;

  @override
  Future<Result<List<SearchService>>> loadAll() async =>
      Ok<List<SearchService>>(List<SearchService>.unmodifiable(_rows));

  @override
  Future<Result<SearchService>> insert(SearchService service) async {
    final SearchService saved = service.copyWith(id: _nextId++);
    _rows.add(saved);
    return Ok<SearchService>(saved);
  }

  @override
  Future<Result<SearchService>> update(SearchService service) async {
    final int index = _rows.indexWhere((SearchService s) => s.id == service.id);
    if (index < 0) {
      return Err<SearchService>(
        StorageError(operation: 'update', isMissing: true),
      );
    }
    _rows[index] = service;
    return Ok<SearchService>(service);
  }

  @override
  Future<Result<void>> delete(int id) async {
    _rows.removeWhere((SearchService s) => s.id == id);
    return okUnit();
  }

  @override
  Future<Result<void>> saveOrder(List<int> idsInOrder) async => okUnit();

  @override
  Future<Result<void>> setDefaultForTasks(
    int id, {
    required bool isDefault,
  }) async => okUnit();
}

/// 内存搜索凭据。
final class FakeSearchCredentials implements SearchCredentialStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<Result<String>> read(String identifier) async {
    final String? value = values[identifier];
    if (value == null) {
      return Err<String>(
        StorageError(operation: 'read', detail: 'missing', isMissing: true),
      );
    }
    return Ok<String>(value);
  }

  @override
  Future<Result<void>> write(String identifier, String apiKey) async {
    values[identifier] = apiKey;
    return okUnit();
  }

  @override
  Future<Result<void>> delete(String identifier) async {
    values.remove(identifier);
    return okUnit();
  }

  @override
  Future<Result<bool>> exists(String identifier) async =>
      Ok<bool>(values.containsKey(identifier));

  @override
  Future<bool> isAvailable() async => true;
}

/// 记录检索次数与参数的假搜索工厂。
final class RecordingSearchFactory implements SearchProviderFactory {
  int searches = 0;
  String? lastQuery;
  int? lastCount;
  AppError? failWith;

  @override
  Result<SearchProvider> create({
    required SearchProtocol protocol,
    required String baseUrl,
    required String apiKey,
    Duration timeout = const Duration(seconds: 20),
    int maxResults = 10,
    bool allowPrivateEndpoint = false,
  }) => Ok<SearchProvider>(_RecordingSearchProvider(this, protocol));

  /// 记录一次检索（供替身调用）。
  void record(SearchRequest request) {
    searches++;
    lastQuery = request.text;
    lastCount = request.count;
  }
}

final class _RecordingSearchProvider implements SearchProvider {
  _RecordingSearchProvider(this._factory, this._protocol);

  final RecordingSearchFactory _factory;
  final SearchProtocol _protocol;

  @override
  String get providerId => _protocol.id;

  @override
  Future<Result<SearchResponse>> search(SearchRequest query) async {
    _factory.record(query);
    final AppError? failure = _factory.failWith;
    if (failure != null) {
      return Err<SearchResponse>(failure);
    }
    return Ok<SearchResponse>(
      SearchResponse(
        provider: _protocol.id,
        query: query.text,
        results: <SearchResult>[
          SearchResult(
            sourceId: searchResultSourceId(provider: _protocol.id, rank: 0),
            title: 'fixture result',
            url: 'https://example.com/a',
            snippet: 'fixture snippet',
            provider: _protocol.id,
            accessCategory: SearchAccessCategory.general,
          ),
        ],
      ),
    );
  }
}

/// 记录调用次数的假网页抓取端口。
final class FakePageFetcher implements ControlledPageFetcher {
  int calls = 0;
  FetchedPage result = const FetchedPage(
    finalUri: 'https://example.com/page',
    title: 'Fixture',
    text: '正文内容',
    imageUrls: <String>[],
    outcome: 'ok',
  );
  AppError? failWith;

  @override
  Future<Result<FetchedPage>> fetch(Uri uri) async {
    calls++;
    final AppError? failure = failWith;
    if (failure != null) {
      return Err<FetchedPage>(failure);
    }
    return Ok<FetchedPage>(result);
  }
}

/// 记录调用次数的假图片查看端口。
final class FakeImageInspector implements ToolImageInspector {
  int calls = 0;
  AppError? failWith;

  @override
  Future<Result<InspectedImage>> inspect(String url) async {
    calls++;
    final AppError? failure = failWith;
    if (failure != null) {
      return Err<InspectedImage>(failure);
    }
    return const Ok<InspectedImage>(
      InspectedImage(
        mimeType: 'image/png',
        width: 640,
        height: 480,
        byteLength: 1234,
      ),
    );
  }
}
