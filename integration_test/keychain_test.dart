// T010：macOS Keychain 真实往返（integration_test）。
//
// 为什么必须是 integration_test 而不是 flutter test：
//   flutter test 跑在 host VM 上，没有 macOS 主进程，MethodChannel 找不到实现，
//   只能验证「错误翻译」；要证明真的写进并读回了系统钥匙串，必须在真实设备上跑。
//
// 执行：flutter test integration_test -d macos
//
// 安全：只写入**明显的假值**（`flux-test-` 前缀 + 时间戳），不涉及任何真实凭据；
// 用例结束（含失败路径）都会删除自己创建的条目，不在用户钥匙串里留残留。
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/platform/credential_store.dart';
import 'package:flux/infrastructure/platform/keychain_store.dart';

/// 测试专用类别：所有条目都带这个前缀，便于识别与清理。
const String _testCategory = 'flux-test-t010';

/// 生成一个带时间戳的假凭据值（明确不是真 key）。
String _fakeValue(String marker) =>
    'flux-test-fake-$marker-${DateTime.now().microsecondsSinceEpoch}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final KeychainCredentialStore store = KeychainCredentialStore();
  final List<CredentialKey> created = <CredentialKey>[];

  /// 登记并返回一个测试键。
  CredentialKey key(String identifier) {
    final CredentialKey created_ = CredentialKey(
      category: _testCategory,
      identifier: identifier,
    );
    created.add(created_);
    return created_;
  }

  tearDown(() async {
    // 清理本次测试写入的所有条目。
    for (final CredentialKey k in created) {
      await store.delete(k);
    }
    created.clear();
  });

  testWidgets('安全存储通道在 macOS 上可用', (WidgetTester tester) async {
    expect(
      await store.isAvailable(),
      isTrue,
      reason: 'macOS 必须有可用的 Keychain 通道，否则凭据只能会话使用或失败',
    );
  });

  testWidgets('write → read 回读一致 → update → read → delete → read 报 notFound', (
    WidgetTester tester,
  ) async {
    final CredentialKey k = key('roundtrip');
    final String first = _fakeValue('first');
    final String second = _fakeValue('second');

    // 起始状态：不存在。
    expect((await store.exists(k)).valueOrNull, isFalse);
    final Result<String> missing = await store.read(k);
    expect(missing.isErr, isTrue);
    expect(isCredentialMissing(missing.errorOrNull!), isTrue);

    // write → read 回读一致。
    expect((await store.write(k, first)).isOk, isTrue);
    expect((await store.exists(k)).valueOrNull, isTrue);
    expect((await store.read(k)).valueOrNull, first);

    // update（同键覆盖）→ read 得到新值。
    expect((await store.write(k, second)).isOk, isTrue);
    expect((await store.read(k)).valueOrNull, second);
    expect(
      (await store.exists(k)).valueOrNull,
      isTrue,
      reason: '覆盖不得产生重复条目或删除条目',
    );

    // delete → read 报 notFound。
    expect((await store.delete(k)).isOk, isTrue);
    expect((await store.exists(k)).valueOrNull, isFalse);
    final Result<String> afterDelete = await store.read(k);
    expect(afterDelete.isErr, isTrue);
    expect(isCredentialMissing(afterDelete.errorOrNull!), isTrue);
  });

  testWidgets('多个凭据互不覆盖（不同类别/标识落在不同条目）', (WidgetTester tester) async {
    final CredentialKey ai = key('ai-provider:main');
    final CredentialKey search = key('search-provider:main');
    final String aiValue = _fakeValue('ai');
    final String searchValue = _fakeValue('search');

    expect((await store.write(ai, aiValue)).isOk, isTrue);
    expect((await store.write(search, searchValue)).isOk, isTrue);
    expect((await store.read(ai)).valueOrNull, aiValue);
    expect((await store.read(search)).valueOrNull, searchValue);
  });

  testWidgets('删除不存在的条目也成功（幂等）', (WidgetTester tester) async {
    final CredentialKey k = key('never-written');
    expect((await store.delete(k)).isOk, isTrue);
    expect((await store.delete(k)).isOk, isTrue);
  });
}
