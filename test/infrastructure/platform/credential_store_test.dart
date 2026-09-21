// T010：凭据存储接口与「无安全存储不回退」规则。
//
// 这里只测接口层与内存实现（纯 Dart，不需要平台通道）。真正写进 macOS Keychain 的
// 往返在 integration_test/keychain_test.dart 里用真实设备执行。
//
// 重点：
//   - CredentialKey 的 account 拼接可逆，不同类别/标识不互相覆盖；
//   - 「条目不存在」与「读取失败」是不同结果，上层能分别处理；
//   - 内存实现绝不落盘（作为无安全存储时的显式降级，而不是悄悄写文件）。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/platform/credential_store.dart';
import 'package:flux/infrastructure/platform/keychain_store.dart';

void main() {
  // MethodChannel 的 mock 处理器依赖二进制 messenger；必须先初始化测试绑定。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CredentialKey', () {
    test('account 由类别与标识拼接，便于在 Keychain 里定位', () {
      const CredentialKey key = CredentialKey(
        category: 'ai-provider',
        identifier: 'openai-main',
      );
      expect(key.account, 'ai-provider:openai-main');
    });

    test('标识里的冒号被转义，拼接可逆（不会与类别分隔符歧义）', () {
      const CredentialKey key = CredentialKey(
        category: 'feed-auth',
        identifier: 'user:pass',
      );
      expect(key.account, 'feed-auth:user%3Apass');
    });

    test('相等性基于类别与标识，可安全用作 Map 键', () {
      const CredentialKey a = CredentialKey(
        category: 'ai-provider',
        identifier: 'x',
      );
      const CredentialKey b = CredentialKey(
        category: 'ai-provider',
        identifier: 'x',
      );
      const CredentialKey c = CredentialKey(
        category: 'search-provider',
        identifier: 'x',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  group('内存凭据实现（无安全存储时的显式降级）', () {
    test('写入后可读回', () async {
      final InMemoryCredentialStore store = InMemoryCredentialStore();
      const CredentialKey key = CredentialKey(
        category: 'ai-provider',
        identifier: 'test',
      );
      expect((await store.write(key, 'fake-value')).isOk, isTrue);
      expect((await store.read(key)).valueOrNull, 'fake-value');
      expect((await store.exists(key)).valueOrNull, isTrue);
    });

    test('未写入时读取返回「条目不存在」，而不是空字符串', () async {
      final InMemoryCredentialStore store = InMemoryCredentialStore();
      const CredentialKey key = CredentialKey(
        category: 'ai-provider',
        identifier: 'absent',
      );
      final Result<String> result = await store.read(key);
      expect(result.isErr, isTrue);
      expect(isCredentialMissing(result.errorOrNull!), isTrue);
      expect((await store.exists(key)).valueOrNull, isFalse);
    });

    test('删除是幂等的，删除后读取报不存在', () async {
      final InMemoryCredentialStore store = InMemoryCredentialStore();
      const CredentialKey key = CredentialKey(
        category: 'webdav',
        identifier: 'main',
      );
      await store.write(key, 'fake');
      expect((await store.delete(key)).isOk, isTrue);
      expect((await store.delete(key)).isOk, isTrue);
      expect((await store.read(key)).isErr, isTrue);
    });

    test('不同类别的同名标识互不覆盖', () async {
      final InMemoryCredentialStore store = InMemoryCredentialStore();
      const CredentialKey ai = CredentialKey(
        category: 'ai-provider',
        identifier: 'token',
      );
      const CredentialKey search = CredentialKey(
        category: 'search-provider',
        identifier: 'token',
      );
      await store.write(ai, 'ai-value');
      await store.write(search, 'search-value');
      expect((await store.read(ai)).valueOrNull, 'ai-value');
      expect((await store.read(search)).valueOrNull, 'search-value');
    });

    test('内存实现不创建任何文件（降级不等于明文落盘）', () async {
      final Directory before = Directory.systemTemp;
      final Set<String> beforeNames = before
          .listSync()
          .map((FileSystemEntity e) => e.path)
          .toSet();

      final InMemoryCredentialStore store = InMemoryCredentialStore();
      await store.write(
        const CredentialKey(category: 'ai-provider', identifier: 'tmp'),
        'fake-value',
      );

      final Set<String> afterNames = before
          .listSync()
          .map((FileSystemEntity e) => e.path)
          .toSet();
      expect(afterNames, beforeNames, reason: '内存实现不得写任何文件');
      expect(await store.isAvailable(), isTrue);
    });
  });

  group('Keychain 适配的错误翻译（不驱动真实通道）', () {
    /// 构造一个固定返回指定错误的通道，用于验证翻译逻辑。
    MethodChannel channelThrowing(String code) {
      const MethodChannel channel = MethodChannel(
        'io.github.guzhengsvt.flux/keychain.test',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            throw PlatformException(code: code);
          });
      return channel;
    }

    test('itemNotFound 翻译为「条目不存在」的 StorageError', () async {
      final KeychainCredentialStore store = KeychainCredentialStore(
        channel: channelThrowing('itemNotFound'),
      );
      final Result<String> result = await store.read(
        const CredentialKey(category: 'ai-provider', identifier: 'x'),
      );
      expect(result.isErr, isTrue);
      expect(isCredentialMissing(result.errorOrNull!), isTrue);
    });

    test('其他 OSStatus 翻译为读取失败（不是「不存在」）', () async {
      final KeychainCredentialStore store = KeychainCredentialStore(
        channel: channelThrowing('osstatus-25300'),
      );
      final Result<String> result = await store.read(
        const CredentialKey(category: 'ai-provider', identifier: 'x'),
      );
      expect(result.isErr, isTrue);
      expect(isCredentialMissing(result.errorOrNull!), isFalse);
      expect(result.errorOrNull, isA<StorageError>());
    });

    test('平台错误不把原始 message 透出（避免带出条目细节）', () async {
      const MethodChannel channel = MethodChannel(
        'io.github.guzhengsvt.flux/keychain.leaky',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            throw PlatformException(
              code: 'osstatus-1',
              message: 'secret-looking-detail-value',
            );
          });
      final KeychainCredentialStore store = KeychainCredentialStore(
        channel: channel,
      );
      final Result<void> result = await store.write(
        const CredentialKey(category: 'ai-provider', identifier: 'x'),
        'fake-value',
      );
      expect(result.isErr, isTrue);
      expect(
        result.errorOrNull!.toLogString(),
        isNot(contains('secret-looking-detail-value')),
      );
    });

    test('通道缺失时明确失败，且 isAvailable 为 false（不明文回退）', () async {
      // 不注册任何 handler：调用会抛 MissingPluginException。
      const MethodChannel channel = MethodChannel(
        'io.github.guzhengsvt.flux/keychain.missing',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      final KeychainCredentialStore store = KeychainCredentialStore(
        channel: channel,
      );
      final Result<void> write = await store.write(
        const CredentialKey(category: 'ai-provider', identifier: 'x'),
        'fake-value',
      );
      expect(write.isErr, isTrue);
      expect(
        (write.errorOrNull! as StorageError).operation,
        'keychain.unavailable',
      );
      expect(await store.isAvailable(), isFalse);
    });
  });
}
