// 地址秘密参数剥离（T015；SET-027）。
//
// 这是导出侧的最后一道秘密防线，因此单独测它：导出用规范化地址，而规范化刻意
// 保留非跟踪参数（架构 4.1），所以带 token 的地址会原样进入导出路径，必须在这里
// 被剥掉。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

void main() {
  group('stripUrlSecrets', () {
    test('移除明确的秘密参数（含 URL 语境下的短名）', () {
      for (final String name in <String>[
        'token',
        'access_token',
        'api_key',
        'apikey',
        'password',
        'secret',
        'authorization',
        // URL 语境下才视为秘密的短名（普通文本里可能是业务词）。
        'key',
        'auth',
        'code',
      ]) {
        final UrlSecretStripResult result = stripUrlSecrets(
          'https://example.com/feed.xml?$name=SECRET_VALUE',
        );

        expect(result.removed, <String>[name], reason: name);
        expect(
          result.url,
          isNot(contains('SECRET_VALUE')),
          reason: '参数值必须被移除：$name',
        );
        expect(
          result.url,
          'https://example.com/feed.xml',
          reason: '移除后不留尾随问号（那是一个与原型不同的地址）',
        );
      }
    });

    test('含关键片段的参数名变体也被移除', () {
      for (final String name in <String>[
        'x-access-token',
        'session_token',
        'my_secret_key',
        'user-password',
      ]) {
        final UrlSecretStripResult result = stripUrlSecrets(
          'https://example.com/feed.xml?$name=SECRET_VALUE',
        );

        expect(result.changed, isTrue, reason: name);
        expect(result.url, isNot(contains('SECRET_VALUE')), reason: name);
      }
    });

    test('业务参数原样保留（剥掉会让订阅失效）', () {
      // 注意用 page 而不是 p：p 在 URL 语境下被 SecretRedaction 视为秘密名（它对常见
      // 承载凭据的短名宁可多遮），因此它属于上面的「秘密参数」一类。
      const String url =
          'https://example.com/feed.xml?channel=c-8f21ba90a7c34d5e&lang=zh&page=2';

      final UrlSecretStripResult result = stripUrlSecrets(url);

      expect(result.changed, isFalse);
      expect(result.url, url, reason: '没有任何秘密参数时返回原串（不重建，避免编码形式微变）');
    });

    test('混合场景：只摘掉秘密参数，其余保持原样与原有顺序', () {
      final UrlSecretStripResult result = stripUrlSecrets(
        'https://example.com/feed.xml?lang=zh&token=X&channel=c1',
      );

      expect(result.removed, <String>['token']);
      expect(result.url, 'https://example.com/feed.xml?lang=zh&channel=c1');
    });

    test('多个秘密参数：逐个移除并如实报告参数名', () {
      final UrlSecretStripResult result = stripUrlSecrets(
        'https://example.com/feed.xml?token=X&api_key=Y&lang=zh',
      );

      expect(result.removed, <String>['token', 'api_key']);
      expect(result.url, 'https://example.com/feed.xml?lang=zh');
    });

    test('userinfo 里的凭据不进入结果（host 部分重建时被丢弃）', () {
      final UrlSecretStripResult result = stripUrlSecrets(
        'https://user:pass@example.com/feed.xml?token=X',
      );

      expect(result.changed, isTrue);
      // 关键：凭据不在结果里。这里不做「保留 userinfo」的处理——导出文件带上
      // 明文口令比订阅失效严重得多。
      expect(result.url, isNot(contains('pass')));
    });

    test('没有查询串的地址原样返回', () {
      const String url = 'https://example.com/feed.xml';

      final UrlSecretStripResult result = stripUrlSecrets(url);

      expect(result.changed, isFalse);
      expect(result.url, url);
    });

    test('非 http(s) 或无法解析：原样返回（不猜测结构）', () {
      for (final String url in <String>[
        'ftp://example.com/feed.xml?token=X',
        'not a url at all',
        '',
      ]) {
        final UrlSecretStripResult result = stripUrlSecrets(url);

        expect(result.removed, isEmpty, reason: url);
      }
    });
  });
}
