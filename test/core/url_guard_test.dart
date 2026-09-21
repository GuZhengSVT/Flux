// T021：出网地址守卫的纯函数判据。
//
// 为什么这一层要单独测：它是订阅抓取与图片抓取**共用**的那一条判据（架构第 8 节
// 「不把请求打到内网」）。判据只在纯函数层能穷举——写实测试会被真实 DNS 与网络
// 环境绑架，而这里每个边界都用一个字符串就能钉住。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

void main() {
  group('协议与主机', () {
    test('只允许 http/https', () {
      for (final String url in <String>[
        'file:///etc/passwd',
        'ftp://example.com/a.png',
        'data:image/png;base64,AAAA',
        'javascript:alert(1)',
      ]) {
        final UrlGuardResult result = checkUrlGuarded(
          Uri.parse(url),
          UrlGuardPolicy.embeddedContent,
        );
        expect(result.allowed, isFalse, reason: url);
        expect(result.failure, UrlGuardFailure.scheme);
      }
    });

    test('http 与 https 都允许（公网地址）', () {
      for (final String url in <String>[
        'https://cdn.example.com/a.png',
        'http://cdn.example.com/a.png',
      ]) {
        final UrlGuardResult result = checkUrlGuarded(
          Uri.parse(url),
          UrlGuardPolicy.embeddedContent,
        );
        expect(result.allowed, isTrue, reason: url);
      }
    });
  });

  group('私网与回环（embeddedContent 才拦）', () {
    const List<String> privateHosts = <String>[
      '127.0.0.1',
      '127.1',
      'localhost',
      'sub.localhost',
      '10.0.0.1',
      '10.255.255.255',
      '172.16.0.1',
      '172.31.255.254',
      '192.168.0.1',
      '169.254.169.254',
      '100.64.0.1',
      '0.0.0.0',
      '198.18.0.1',
      '224.0.0.1',
      'printer.local',
      'service.internal',
      '2130706433',
      '0x7f000001',
      '::1',
      'fc00::1',
      'fd12:3456::1',
      'fe80::1',
    ];

    /// 能直接放进 URL 的主机形态：裸 IPv6 必须带方括号（Uri.parse('https://::1/')
    /// 会直接抛 FormatException）。
    List<String> urlHostsFor(String host) =>
        host.contains(':') ? <String>['[$host]'] : <String>[host];

    test('指向本机或私有网络的主机被拒绝', () {
      for (final String host in privateHosts) {
        expect(isPrivateHostLiteral(host), isTrue, reason: '$host 应被判为私网/回环');
        for (final String urlHost in urlHostsFor(host)) {
          final UrlGuardResult result = checkUrlGuarded(
            Uri.parse('https://$urlHost/a.png'),
            UrlGuardPolicy.embeddedContent,
          );
          expect(result.allowed, isFalse, reason: urlHost);
        }
      }
    });

    test('通配 DNS 服务（把 IP 编进域名）由解析后的复检挡住，而不是靠字面量', () {
      // 127.0.0.1.nip.io 这类服务的域名本身不像私网，字面量判据**故意**不拦它；
      // 真正的防线是解析之后对每个结果再判一次（见 media_fetcher_test 的 DNS 复检用例）。
      expect(isPrivateHostLiteral('127.0.0.1.nip.io'), isFalse);
    });

    test('公网 IP 与域名不被误判（本实现第一版曾把所有点分 IP 都拒掉）', () {
      for (final String host in <String>[
        '93.184.216.34',
        '8.8.8.8',
        '1.1.1.1',
        '172.32.0.1',
        '172.15.255.255',
        '192.169.0.1',
        '11.0.0.1',
        'cdn.example.com',
        'example.com',
        'a-b.c-d.org',
      ]) {
        expect(isPrivateHostLiteral(host), isFalse, reason: '$host 是公网地址，不应被拦');
      }
    });

    test('用户显式配置的源允许私网（自己的内网 RSS 是正当需求）', () {
      for (final String host in privateHosts) {
        for (final String urlHost in urlHostsFor(host)) {
          final UrlGuardResult result = checkUrlGuarded(
            Uri.parse('https://$urlHost/feed.xml'),
            UrlGuardPolicy.configuredSource,
          );
          expect(result.allowed, isTrue, reason: urlHost);
        }
      }
    });
  });

  group('IPv4 网段', () {
    test('私网段被识别', () {
      for (final String ip in <String>[
        '10.0.0.1',
        '172.16.0.1',
        '172.31.0.1',
        '192.168.1.1',
        '127.0.0.1',
        '169.254.1.1',
        '100.64.0.1',
        '198.18.0.1',
        '240.0.0.1',
      ]) {
        expect(isPrivateIPv4(ip), isTrue, reason: ip);
      }
    });

    test('公网段不被识别为私网', () {
      for (final String ip in <String>[
        '8.8.8.8',
        '93.184.216.34',
        '172.32.0.1',
        '192.169.0.1',
        '100.128.0.1',
        '198.20.0.1',
      ]) {
        expect(isPrivateIPv4(ip), isFalse, reason: ip);
      }
    });
  });

  group('guardUrl（Result 包装）', () {
    test('通过返回 Ok，拒绝返回带原因的 Err，且标记不可重试', () {
      expect(
        guardUrl(
          Uri.parse('https://cdn.example.com/a.png'),
          UrlGuardPolicy.embeddedContent,
        ).isOk,
        isTrue,
      );
      final Result<void> blocked = guardUrl(
        Uri.parse('http://127.0.0.1/a.png'),
        UrlGuardPolicy.embeddedContent,
      );
      expect(blocked.isErr, isTrue);
      expect(blocked.errorOrNull, isA<NetworkError>());
      expect(blocked.errorOrNull!.isRetryable, isFalse);
    });
  });
}
