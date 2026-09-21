// 脱敏工具测试（T007）。
//
// 这是错误体系“message 不含秘密”保证的底层依据，单独测以保证规则本身可信。

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

/// 测试用**假**凭据：形如真实 Key 的固定字符串，但只是本文件内的常量，
/// 不指向任何真实账号或服务。保留 `sk-` 前缀是为了让脱敏规则能被真实触发。
const String _key = 'sk-abcdef1234567890abcdef1234567890';

void main() {
  group('URL 脱敏', () {
    test('遮盖敏感 query 参数，保留非敏感参数', () {
      final String out = SecretRedaction.sanitizeUrlString(
        'https://example.com/rss?token=$_key&page=3&lang=zh',
      );
      expect(out, isNot(contains(_key)));
      expect(out, contains('token=***'));
      expect(out, contains('page=3'));
      expect(out, contains('lang=zh'));
    });

    test('URL 语境下 key/code/p 等短名也按秘密处理', () {
      final String out = SecretRedaction.sanitizeUrlString(
        'https://example.com/api?key=abc123&code=def456&q=hello',
      );
      expect(out, contains('key=***'));
      expect(out, contains('code=***'));
      expect(out, contains('q=hello'));
    });

    test('高熵无名单值也遮盖（避免未知参数名漏遮）', () {
      const String highEntropy = 'Zx9Kq2Wm8Pl4Vt7Ry1Nb6Cj3Hs5Gd0';
      final String out = SecretRedaction.sanitizeUrlString(
        'https://example.com/feed?$highEntropy',
      );
      expect(out, isNot(contains(highEntropy)));
      expect(out, contains('***'));
    });

    test('短值且非敏感名时不遮盖，避免把正常参数遮没', () {
      final String out = SecretRedaction.sanitizeUrlString(
        'https://example.com/feed?page=2&sort=desc',
      );
      expect(out, contains('page=2'));
      expect(out, contains('sort=desc'));
    });

    test('遮盖 userinfo 凭据，保留 host 与 path', () {
      const String password = 'hunter2secret';
      final String out = SecretRedaction.sanitizeUrlString(
        'https://alice:$password@example.com/private/feed.xml',
      );
      expect(out, isNot(contains('hunter2secret')));
      expect(out, contains('example.com'));
      expect(out, contains('/private/feed.xml'));
    });

    test('保留 scheme/host/path，便于从日志定位端点', () {
      final String out = SecretRedaction.sanitizeUrlString(
        'https://api.example.com/v1/chat/completions',
      );
      expect(out, 'https://api.example.com/v1/chat/completions');
    });

    test('空串与纯空白安全返回空串', () {
      expect(SecretRedaction.sanitizeUrlString(''), '');
      expect(SecretRedaction.sanitizeUrlString('   '), '');
    });

    test('sanitizeUri 返回可解析且已脱敏的 Uri', () {
      final Uri uri = SecretRedaction.sanitizeUri(
        Uri.parse('https://example.com/feed?apikey=$_key&page=1'),
      );
      expect(uri.toString(), isNot(contains(_key)));
      expect(uri.host, 'example.com');
      expect(uri.queryParameters['page'], '1');
      expect(uri.queryParameters['apikey'], '***');
    });
  });

  group('凭据串脱敏', () {
    test('遮盖裸 Bearer 串（无 name= 前缀时由 Bearer 规则处理）', () {
      final String out = SecretRedaction.redact('retry with Bearer $_key now');
      expect(out, isNot(contains(_key)));
      expect(out, contains('Bearer ***'));
    });

    test('遮盖 Authorization 头的整个值（不只第一个词）', () {
      // 这是刻意的安全取舍：凭据在第二个词上，因此把整行值一并遮盖，
      // 避免 "Bearer <token>" 中的 token 残留在日志里。
      final String out = SecretRedaction.redact('Authorization: Bearer $_key');
      expect(out, isNot(contains(_key)));
      expect(out, 'Authorization: ***');
    });

    test('遮盖常见前缀凭据（sk-/ghp_/xoxb/AKIA），即使没有 name= 前缀', () {
      for (final String credential in <String>[
        'sk-abcdef1234567890abcdef',
        'ghp_abcdefghijklmnopqrst',
        'xoxb-123456789012-abcdefghij',
        'AKIAIOSFODNN7EXAMPLE',
      ]) {
        final String out = SecretRedaction.redact('请求失败：$credential 无效');
        expect(out, isNot(contains(credential)), reason: credential);
      }
    });

    test('遮盖普通文本中的敏感 name=value 与 name: value', () {
      final String eq = SecretRedaction.redact('api_key=$_key');
      expect(eq, 'api_key=***');

      final String colon = SecretRedaction.redact('password: hunter2secret');
      expect(colon, 'password: ***');
    });

    test('引号包裹的秘密值也被遮盖', () {
      final String out = SecretRedaction.redact('token="$_key"');
      expect(out, isNot(contains(_key)));
    });

    test('非敏感 name=value 不被误遮', () {
      final String out = SecretRedaction.redact('page=2 lang=zh sort=desc');
      expect(out, 'page=2 lang=zh sort=desc');
    });

    test('null 与空串安全返回空串', () {
      expect(SecretRedaction.redact(null), '');
      expect(SecretRedaction.redact(''), '');
    });

    test('同时出现 URL 与凭据时都能被遮盖', () {
      final String out = SecretRedaction.redact(
        'GET https://api.example.com/v1?token=$_key failed; '
        'retry with Bearer $_key',
      );
      expect(out, isNot(contains(_key)));
      expect(out, contains('api.example.com'));
    });
  });

  group('参数名判定', () {
    test('无歧义的秘密名在任何语境都判为敏感', () {
      for (final String name in <String>[
        'token',
        'api_key',
        'API-KEY',
        'password',
        'authorization',
      ]) {
        expect(
          SecretRedaction.isSensitiveName(name, inUrl: false),
          isTrue,
          reason: name,
        );
      }
    });

    test('短名只在 URL 语境判为敏感，避免日常文本被过度遮盖', () {
      expect(SecretRedaction.isSensitiveName('key', inUrl: true), isTrue);
      expect(SecretRedaction.isSensitiveName('key', inUrl: false), isFalse);
    });

    test('URL 语境下含 token/secret 等词的变体名也判为敏感', () {
      expect(
        SecretRedaction.isSensitiveName('some_token', inUrl: true),
        isTrue,
      );
      expect(SecretRedaction.isSensitiveName('x-apikey', inUrl: true), isTrue);
      expect(
        SecretRedaction.isSensitiveName('utm_source', inUrl: true),
        isFalse,
      );
      expect(SecretRedaction.isSensitiveName('page', inUrl: true), isFalse);
    });

    test('大小写与空白不影响判定', () {
      expect(
        SecretRedaction.isSensitiveName('  ToKeN  ', inUrl: false),
        isTrue,
      );
    });

    test('looksLikeSecretValue 对短值/含空格值返回 false', () {
      expect(SecretRedaction.looksLikeSecretValue('abc'), isFalse);
      expect(
        SecretRedaction.looksLikeSecretValue('this is a sentence with spaces'),
        isFalse,
      );
      expect(
        SecretRedaction.looksLikeSecretValue('Zx9Kq2Wm8Pl4Vt7Ry1Nb6Cj3Hs5Gd0'),
        isTrue,
      );
    });
  });
}
