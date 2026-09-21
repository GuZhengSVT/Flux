// T031：搜索服务管理用例（CRUD / 引用检查 / 排序 / 凭据隔离 / 测试按钮的发送边界）。
//
// 这一组用例盯的是「管理器会不会替用户花钱或泄漏」这一类问题：
//   - **没有凭据绝不发请求**（协议要求凭据时直接拒绝，请求计数为 0）；
//   - **没有费用确认绝不发请求**（SearchSendConfirmation 是前置参数）；
//   - 凭据按**服务名**存储，且与 AI 凭据分属不同 Keychain 类别（SET-039）；
//   - 诊断日志里不含 Key、不含查询词；
//   - 删除前先算引用；读不到引用时**不放行**删除；
//   - 端点在保存时校验，非法地址不落库。
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/search_manager.dart';
import 'package:flux/features/ai/domain/search_credential_store.dart';
import 'package:flux/features/ai/domain/search_protocol.dart';
import 'package:flux/features/ai/domain/search_provider.dart';
import 'package:flux/features/ai/domain/search_result.dart';
import 'package:flux/features/ai/domain/search_service.dart';
import 'package:flux/features/ai/domain/search_service_store.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart'
    show DiagnosticLogSink;
import 'package:flux/infrastructure/local/search_service_store.dart';
import 'package:flux/infrastructure/platform/ai_credential_adapter.dart';
import 'package:flux/infrastructure/platform/credential_store.dart';

/// 一个记录「被创建过几次适配器、发过几次检索」的假工厂。
final class _CountingFactory implements SearchProviderFactory {
  /// 适配器被创建过几次。
  int created = 0;

  /// 检索被调用过几次。
  int searches = 0;

  /// 收到的 Key（用于断言「凭据确实从安全存储读出来并交给了适配器」）。
  final List<String> receivedKeys = <String>[];

  /// 收到的 SET-041 批准标记（每创建一次追加一项）。
  ///
  /// 单独记录它是因为这个开关必须从**服务记录**一路传到适配器：中途丢掉会让
  /// 「用户已批准内网端点」变成一次无效勾选（界面上是打开的，请求却仍被守卫拒绝）。
  final List<bool> receivedPrivateApprovals = <bool>[];

  /// 是否让检索失败；非空时返回该错误。
  AppError? failWith;

  @override
  Result<SearchProvider> create({
    required SearchProtocol protocol,
    required String baseUrl,
    required String apiKey,
    Duration timeout = const Duration(seconds: 20),
    int maxResults = 10,
    bool allowPrivateEndpoint = false,
  }) {
    created++;
    receivedKeys.add(apiKey);
    receivedPrivateApprovals.add(allowPrivateEndpoint);
    return Ok<SearchProvider>(_FakeProvider(this, protocol));
  }
}

/// 一个不联网的假适配器。
final class _FakeProvider implements SearchProvider {
  _FakeProvider(this._factory, this._protocol);

  final _CountingFactory _factory;
  final SearchProtocol _protocol;

  @override
  String get providerId => _protocol.id;

  @override
  Future<Result<SearchResponse>> search(SearchRequest query) async {
    _factory.searches++;
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
            title: 'fixture title',
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

/// 一个内存凭据存储，记录写入过的值（用于断言存的是哪一份）。
final class _RecordingCredentialStore implements SearchCredentialStore {
  final Map<String, String> values = <String, String>{};
  bool available = true;

  @override
  Future<Result<String>> read(String identifier) async {
    final String? value = values[identifier];
    if (value == null) {
      return Err<String>(
        StorageError(
          operation: 'searchCredential.read',
          detail: 'missing',
          isMissing: true,
        ),
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
  Future<bool> isAvailable() async => available;
}

/// 一个读取必然失败的存储（验证「读不到引用 ≠ 没有引用」）。
final class _FailingStore implements SearchServiceStore {
  _FailingStore(this._inner);

  final SearchServiceStore _inner;

  @override
  Future<Result<List<SearchService>>> loadAll() async =>
      Err<List<SearchService>>(
        StorageError(operation: 'searchService.loadAll', detail: 'boom'),
      );

  @override
  Future<Result<SearchService>> insert(SearchService service) =>
      _inner.insert(service);

  @override
  Future<Result<SearchService>> update(SearchService service) =>
      _inner.update(service);

  @override
  Future<Result<void>> delete(int id) => _inner.delete(id);

  @override
  Future<Result<void>> saveOrder(List<int> idsInOrder) =>
      _inner.saveOrder(idsInOrder);

  @override
  Future<Result<void>> setDefaultForTasks(int id, {required bool isDefault}) =>
      _inner.setDefaultForTasks(id, isDefault: isDefault);
}

void main() {
  late AppDatabase db;
  late DriftSearchServiceStore store;
  late _RecordingCredentialStore credentials;
  late DiagnosticLog diagnostics;
  late _CountingFactory factory;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    store = DriftSearchServiceStore(db);
    credentials = _RecordingCredentialStore();
    // 默认级别是 error（SET-082 的生产默认值），而这里要同时检查 info/warning
    // 路径，因此显式放开到 info（与 model_manager_test 同一做法）。
    diagnostics = DiagnosticLog(level: DiagnosticLevel.info);
    factory = _CountingFactory();
  });

  tearDown(() async {
    await db.close();
  });

  SearchManager manager({
    SearchServiceStore? withStore,
    bool withFactory = true,
  }) => SearchManager(
    store: withStore ?? store,
    credentials: credentials,
    diagnostics: DiagnosticLogSink(diagnostics),
    factory: withFactory ? factory : null,
  );

  SearchService service({
    String label = 'tavily-main',
    SearchProtocol protocol = SearchProtocol.tavily,
    String baseUrl = 'https://api.example.com',
    bool enabled = true,
    bool allowPrivate = false,
  }) => SearchService(
    label: label,
    protocol: protocol,
    baseUrl: baseUrl,
    enabled: enabled,
    allowPrivateEndpoint: allowPrivate,
  );

  group('CRUD 与取值域', () {
    test('保存后可读回；改为更新而不是插入第二条', () async {
      final SearchManager sut = manager();
      final SearchService saved = (await sut.saveService(service())).unwrap();
      expect(saved.id, isNotNull);

      final SearchService updated = (await sut.saveService(
        saved.copyWith(baseUrl: 'https://api2.example.com'),
      )).unwrap();
      expect(updated.id, saved.id);

      final List<SearchService> all = (await sut.loadServices()).unwrap();
      expect(all, hasLength(1));
      expect(all.single.baseUrl, 'https://api2.example.com');
    });

    test('服务名重复返回 ValidationError（不覆盖已有记录）', () async {
      final SearchManager sut = manager();
      await sut.saveService(service());
      final Result<SearchService> conflict = await sut.saveService(
        service(baseUrl: 'https://other.example.com'),
      );
      expect(conflict.isErr, isTrue);
      expect(conflict.errorOrNull, isA<ValidationError>());
      expect((await sut.loadServices()).unwrap(), hasLength(1));
    });

    test('非法端点与越界结果数都不落库', () async {
      final SearchManager sut = manager();
      for (final SearchService bad in <SearchService>[
        service(baseUrl: 'file:///etc/passwd'),
        service(baseUrl: ''),
        service().copyWith(maxResults: 99),
        service().copyWith(timeoutSeconds: 1),
      ]) {
        final Result<SearchService> result = await sut.saveService(bad);
        expect(result.isErr, isTrue, reason: '非法配置不得落库：$bad');
        expect(result.errorOrNull, isA<ValidationError>());
      }
      expect((await sut.loadServices()).unwrap(), isEmpty);
    });

    test('loadEnabledServices 只返回启用的服务，且保持排序', () async {
      final SearchManager sut = manager();
      final SearchService first = (await sut.saveService(
        service(label: 'a', baseUrl: 'https://a.example.com'),
      )).unwrap();
      final SearchService second = (await sut.saveService(
        service(label: 'b', baseUrl: 'https://b.example.com'),
      )).unwrap();
      await sut.saveService(second.copyWith(enabled: false));
      // 顺序反转为 b, a 后再取启用列表。
      await sut.reorder(<int>[second.id!, first.id!]);
      await sut.saveService(second.copyWith(enabled: true));

      final List<SearchService> enabled = (await sut.loadEnabledServices())
          .unwrap();
      expect(enabled.map((SearchService s) => s.label), <String>['b', 'a']);
    });

    test('reorder 拒绝重复 id', () async {
      final SearchManager sut = manager();
      final SearchService saved = (await sut.saveService(service())).unwrap();
      final Result<void> result = await sut.reorder(<int>[
        saved.id!,
        saved.id!,
      ]);
      expect(result.errorOrNull, isA<ValidationError>());
    });
  });

  group('引用检查与删除', () {
    test('未设默认时删除不需要确认', () async {
      final SearchManager sut = manager();
      final SearchService saved = (await sut.saveService(service())).unwrap();
      expect((await sut.describeReferencesTo(saved)).unwrap(), isEmpty);
      expect((await sut.deleteService(saved)).isOk, isTrue);
      expect((await sut.loadServices()).unwrap(), isEmpty);
    });

    test('设为默认后删除需要确认（返回 ModelInUseError）', () async {
      final SearchManager sut = manager();
      final SearchService saved = (await sut.saveService(service())).unwrap();
      await sut.setDefaultForTasks(saved.id!, isDefault: true);

      final Result<void> blocked = await sut.deleteService(saved);
      expect(blocked.errorOrNull, isA<ModelInUseError>());
      expect(
        (blocked.errorOrNull! as ModelInUseError).referenceDescriptions,
        contains('任务默认搜索服务'),
      );
      // 记录仍在（没有静默删除）。
      expect((await sut.loadServices()).unwrap(), hasLength(1));

      // 带 force 后删除成功。
      expect((await sut.deleteService(saved, force: true)).isOk, isTrue);
      expect((await sut.loadServices()).unwrap(), isEmpty);
    });

    test('引用读不出来时不放行删除（读不到 ≠ 没有引用）', () async {
      final SearchManager sut = manager(withStore: _FailingStore(store));
      final Result<void> result = await sut.deleteService(
        const SearchService(
          id: 1,
          label: 'x',
          protocol: SearchProtocol.tavily,
          baseUrl: 'https://api.example.com',
        ),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<StorageError>());
    });

    test('删除记录不删除凭据（两件事分开）', () async {
      final SearchManager sut = manager();
      final SearchService saved = (await sut.saveService(service())).unwrap();
      await sut.saveCredential(saved.credentialIdentifier, 'secret-key');
      await sut.deleteService(saved);
      expect(
        credentials.values,
        containsPair(saved.credentialIdentifier, 'secret-key'),
        reason: '删配置不等于删凭据（凭据删除是独立动作）',
      );
    });
  });

  group('凭据（SET-039 与 AI 凭据分开）', () {
    test('凭据读写按服务名进行，且 isAvailable 透传', () async {
      final SearchManager sut = manager();
      expect((await sut.saveCredential('tavily-main', 'k-1')).isOk, isTrue);
      expect((await sut.hasCredential('tavily-main')).unwrap(), isTrue);
      expect((await sut.hasCredential('other')).unwrap(), isFalse);
      expect(await sut.isCredentialStoreAvailable(), isTrue);

      credentials.available = false;
      expect(await sut.isCredentialStoreAvailable(), isFalse);
    });

    test('空 Key 被拒绝（不写入一个空凭据）', () async {
      final SearchManager sut = manager();
      final Result<void> result = await sut.saveCredential('x', '   ');
      expect(result.errorOrNull, isA<ValidationError>());
      expect(credentials.values, isEmpty);
    });

    test('搜索凭据与 AI 凭据在 Keychain 里是不同类别', () async {
      // 同一份底层 CredentialStore，两个适配器；同名标识必须落到不同条目。
      final InMemoryCredentialStore inner = InMemoryCredentialStore();
      final AiCredentialStoreAdapter ai = AiCredentialStoreAdapter(inner);
      final SearchCredentialStoreAdapter search = SearchCredentialStoreAdapter(
        inner,
      );

      await ai.write('openai', 'ai-key');
      await search.write('openai', 'search-key');
      expect((await ai.read('openai')).unwrap(), 'ai-key');
      expect(
        (await search.read('openai')).unwrap(),
        'search-key',
        reason: '同名不得互相覆盖：SET-039 要求两类凭据分开管理',
      );
    });
  });

  group('最小检索测试（SET-042）', () {
    SearchSendConfirmation confirmation() =>
        SearchSendConfirmation(acknowledgedAtUtc: DateTime.utc(2026, 9, 22));

    test('协议要求凭据但未配置 → AuthError，且**一次请求都不发**', () async {
      final SearchManager sut = manager();
      final SearchService saved = (await sut.saveService(service())).unwrap();
      final Result<SearchTestReport> report = await sut.runMinimalSearch(
        saved,
        confirmation: confirmation(),
      );
      expect(report.errorOrNull, isA<AuthError>());
      expect(factory.created, 0, reason: '没有凭据时连适配器都不该创建');
      expect(factory.searches, 0, reason: '不发任何请求');
    });

    test('有凭据时发一次请求并给出结构化报告（不含片段内容）', () async {
      final SearchManager sut = manager();
      final SearchService saved = (await sut.saveService(service())).unwrap();
      await sut.saveCredential(saved.credentialIdentifier, 'secret-key');

      final Result<SearchTestReport> report = await sut.runMinimalSearch(
        saved,
        confirmation: confirmation(),
      );
      expect(report.isOk, isTrue);
      expect(factory.created, 1);
      expect(factory.searches, 1);
      expect(factory.receivedKeys.single, 'secret-key');
      final SearchTestReport value = report.unwrap();
      expect(value.resultCount, 1);
      expect(value.firstTitle, 'fixture title');
      expect(value.hasAnswer, isFalse);
    });

    test('未启用的服务被拒绝，且不发请求', () async {
      final SearchManager sut = manager();
      final SearchService saved = (await sut.saveService(
        service(enabled: false),
      )).unwrap();
      await sut.saveCredential(saved.credentialIdentifier, 'secret-key');
      final Result<SearchTestReport> report = await sut.runMinimalSearch(
        saved,
        confirmation: confirmation(),
      );
      expect(report.errorOrNull, isA<ValidationError>());
      expect(factory.searches, 0);
    });

    test('工厂未接线 → 明确说明，不静默什么都不做', () async {
      final SearchManager sut = manager(withFactory: false);
      final SearchService saved = (await sut.saveService(service())).unwrap();
      await sut.saveCredential(saved.credentialIdentifier, 'secret-key');
      final Result<SearchTestReport> report = await sut.runMinimalSearch(
        saved,
        confirmation: confirmation(),
      );
      expect(report.errorOrNull, isA<ValidationError>());
      expect(factory.searches, 0);
    });

    test('SearXNG 不要求凭据：无凭据也可测试（可选认证）', () async {
      final SearchManager sut = manager();
      final SearchService saved = (await sut.saveService(
        service(
          label: 'self-hosted',
          protocol: SearchProtocol.searxng,
          baseUrl: 'https://search.example.com',
        ),
      )).unwrap();
      final Result<SearchTestReport> report = await sut.runMinimalSearch(
        saved,
        confirmation: confirmation(),
      );
      expect(report.isOk, isTrue, reason: 'SearXNG 的凭据是可选的');
      expect(factory.searches, 1);
    });

    test('SET-041 的批准从记录一路传到适配器（否则勾选无效）', () async {
      final SearchManager sut = manager();
      final SearchService saved = (await sut.saveService(
        service(
          label: 'self-hosted',
          protocol: SearchProtocol.searxng,
          baseUrl: 'http://192.168.1.10:8080',
          allowPrivate: true,
        ),
      )).unwrap();
      await sut.runMinimalSearch(saved, confirmation: confirmation());
      expect(factory.receivedPrivateApprovals, <bool>[true]);
    });

    test('适配器失败时不把错误吞掉，并记一条诊断', () async {
      final SearchManager sut = manager();
      final SearchService saved = (await sut.saveService(service())).unwrap();
      await sut.saveCredential(saved.credentialIdentifier, 'secret-key');
      factory.failWith = RateLimitError(provider: 'tavily');

      final Result<SearchTestReport> report = await sut.runMinimalSearch(
        saved,
        confirmation: confirmation(),
      );
      expect(report.errorOrNull, isA<RateLimitError>());
      expect(
        diagnostics.entries.any(
          (DiagnosticEntry entry) => entry.message.contains('搜索测试失败'),
        ),
        isTrue,
      );
    });
  });

  group('诊断日志不含秘密与查询词', () {
    test('成功与失败路径的日志里都不含 Key、不含查询词', () async {
      final SearchManager sut = manager();
      final SearchService saved = (await sut.saveService(service())).unwrap();
      const String key = 'super-secret-search-key';
      const String query = 'this-is-the-user-query';
      await sut.saveCredential(saved.credentialIdentifier, key);
      await sut.runMinimalSearch(
        saved,
        confirmation: SearchSendConfirmation(
          acknowledgedAtUtc: DateTime.utc(2026, 9, 22),
        ),
        query: query,
      );
      factory.failWith = AuthError(provider: 'tavily');
      await sut.runMinimalSearch(
        saved,
        confirmation: SearchSendConfirmation(
          acknowledgedAtUtc: DateTime.utc(2026, 9, 22),
        ),
        query: query,
      );

      final String all = diagnostics.entries
          .map((DiagnosticEntry entry) => entry.message)
          .join('\n');
      expect(all, isNotEmpty);
      expect(all, isNot(contains(key)), reason: '诊断里绝不能出现凭据');
      expect(all, isNot(contains(query)), reason: '诊断里不记用户查询词');
      expect(all, contains('搜索测试成功'));
      expect(all, contains('搜索测试失败'));
    });
  });
}
