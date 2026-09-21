// T021：受控图片抓取（MIME 白名单、单图上限、重定向逐跳校验、守卫、字节校验）。
//
// 全部用 MockClient 与注入的 DNS 解析，不联网。DNS 必须可注入：本文件要断言「公网
// 域名解析到 127.0.0.1 时被拒绝」，而这只有能控制解析结果才测得出来。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/network/media_fetcher.dart';

import '../../app/fake_article_image_loader.dart';

/// 构造一个固定应答的抓取器。
HttpMediaFetcher _fetcher({
  required http.Response Function(http.Request request) handler,
  List<String>? resolvedHosts,
}) => HttpMediaFetcher(
  client: MockClient((http.Request request) async => handler(request)),
  // 默认解析到一个公网地址：只测「内容校验」的用例不该被 DNS 守卫挡住。
  resolveHost: (String host) async => <InternetAddress>[
    InternetAddress(resolvedHosts?.first ?? '93.184.216.34'),
  ],
);

/// 一张 1×1 PNG（魔数与 IHDR 正确）。
Uint8List _png({int width = 1, int height = 1}) {
  final Uint8List bytes = Uint8List.fromList(kTestPngBytes);
  bytes[16] = (width >> 24) & 0xFF;
  bytes[17] = (width >> 16) & 0xFF;
  bytes[18] = (width >> 8) & 0xFF;
  bytes[19] = width & 0xFF;
  bytes[20] = (height >> 24) & 0xFF;
  bytes[21] = (height >> 16) & 0xFF;
  bytes[22] = (height >> 8) & 0xFF;
  bytes[23] = height & 0xFF;
  return bytes;
}

http.Response _ok(Uint8List body, {String? contentType}) => http.Response.bytes(
  body,
  200,
  headers: <String, String>{'content-type': ?contentType},
);

void main() {
  group('MIME 白名单', () {
    test('未声明 Content-Type 的响应被拒绝（不按扩展名猜）', () async {
      final HttpMediaFetcher fetcher = _fetcher(handler: (_) => _ok(_png()));
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.png'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('没有声明图片类型'));
    });

    test('image/svg+xml 被拒绝（可携带脚本，不在白名单内）', () async {
      final HttpMediaFetcher fetcher = _fetcher(
        handler: (_) => _ok(
          Uint8List.fromList('<svg/>'.codeUnits),
          contentType: 'image/svg+xml',
        ),
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.svg'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('不在允许列表内'));
    });

    test('Content-Type 带参数时仍能识别（image/jpeg; charset=binary）', () async {
      final HttpMediaFetcher fetcher = _fetcher(
        handler: (_) => _ok(
          // 最小合法 JPEG 头：SOI + SOF0（含 1×1 尺寸）。
          Uint8List.fromList(<int>[
            0xFF,
            0xD8,
            0xFF,
            0xC0,
            0x00,
            0x11,
            0x08,
            0x00,
            0x01,
            0x00,
            0x01,
            0x03,
            0x01,
            0x11,
            0x00,
            0x02,
            0x11,
            0x01,
            0x03,
            0x11,
            0x01,
          ]),
          contentType: 'image/jpeg; charset=binary',
        ),
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.jpg'),
      );
      expect(result.isOk, isTrue);
      expect(result.unwrap().mimeType, 'image/jpeg');
    });
  });

  group('声明与字节不一致', () {
    test('声明 image/png 但字节是 JPEG：拒绝，不按实际类型渲染', () async {
      final HttpMediaFetcher fetcher = _fetcher(
        handler: (_) => _ok(
          Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]),
          contentType: 'image/png',
        ),
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.png'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('不一致'));
    });

    test('image/jpg 与 image/jpeg 都接受（真实源两种写法都有）', () async {
      final Uint8List jpeg = Uint8List.fromList(<int>[
        0xFF,
        0xD8,
        0xFF,
        0xC0,
        0x00,
        0x11,
        0x08,
        0x00,
        0x01,
        0x00,
        0x01,
        0x03,
        0x01,
        0x11,
        0x00,
        0x02,
        0x11,
        0x01,
        0x03,
        0x11,
        0x01,
      ]);
      for (final String mime in <String>['image/jpg', 'image/jpeg']) {
        final HttpMediaFetcher fetcher = _fetcher(
          handler: (_) => _ok(jpeg, contentType: mime),
        );
        final Result<MediaFetchResult> result = await fetcher.fetch(
          Uri.parse('https://cdn.example.com/a.jpg'),
        );
        expect(result.isOk, isTrue, reason: '$mime 应被接受');
      }
    });

    test('无法识别的字节被拒绝', () async {
      final HttpMediaFetcher fetcher = _fetcher(
        handler: (_) => _ok(
          Uint8List.fromList(List<int>.filled(64, 0x41)),
          contentType: 'image/png',
        ),
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.png'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('无法识别'));
    });
  });

  group('体积上限', () {
    test('声明长度超过单图上限时在读完之前就拒绝', () async {
      // 必须用 streaming + 显式 contentLength：http.Response 的 contentLength 由**实际
      // 字节数**决定，手写 content-length 头会被覆盖，那样就测不到「按声明预检」。
      final HttpMediaFetcher fetcher = HttpMediaFetcher(
        client: MockClient.streaming((http.BaseRequest request, _) async {
          return http.StreamedResponse(
            Stream<List<int>>.value(_png()),
            200,
            contentLength: kMaxImageBytes + 1,
            headers: <String, String>{'content-type': 'image/png'},
          );
        }),
        resolveHost: (String host) async => <InternetAddress>[
          InternetAddress('93.184.216.34'),
        ],
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.png'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('声明长度'));
    });

    test('未声明长度但实际超限时中止（流式计数）', () async {
      final HttpMediaFetcher fetcher = HttpMediaFetcher(
        client: MockClient.streaming((http.BaseRequest request, _) async {
          // 分块吐出一个超限的 PNG，且不带 content-length。
          final Uint8List chunk = Uint8List(kMaxImageBytes ~/ 4 + 1);
          chunk.setRange(0, kTestPngBytes.length, kTestPngBytes);
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[
              chunk,
              chunk,
              chunk,
              chunk,
              chunk,
            ]),
            200,
            headers: <String, String>{'content-type': 'image/png'},
          );
        }),
        resolveHost: (String host) async => <InternetAddress>[
          InternetAddress('93.184.216.34'),
        ],
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.png'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('实际长度超过上限'));
    });

    test('可调上限：配置更小的上限时按配置拒绝', () async {
      final HttpMediaFetcher fetcher = HttpMediaFetcher(
        config: const MediaFetchConfig(maxBytes: 32),
        client: MockClient(
          (http.Request request) async => _ok(_png(), contentType: 'image/png'),
        ),
        resolveHost: (String host) async => <InternetAddress>[
          InternetAddress('93.184.216.34'),
        ],
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.png'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('上限'));
    });
  });

  group('解码上限', () {
    test('头部声明尺寸超过解码像素上限时拒绝（在解码之前）', () async {
      // 60000×60000 = 3.6e9 像素，超过 50 MP。
      final HttpMediaFetcher fetcher = _fetcher(
        handler: (_) =>
            _ok(_png(width: 60000, height: 60000), contentType: 'image/png'),
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.png'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('解码上限'));
    });

    test('正常尺寸通过并带回真实像素尺寸', () async {
      final HttpMediaFetcher fetcher = _fetcher(
        handler: (_) =>
            _ok(_png(width: 1200, height: 800), contentType: 'image/png'),
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.png'),
      );
      expect(result.isOk, isTrue);
      expect(result.unwrap().dimensions.width, 1200);
      expect(result.unwrap().dimensions.height, 800);
    });
  });

  group('地址守卫（与订阅抓取共用判据）', () {
    test('字面量私网与回环地址被拒绝，且不发出请求', () async {
      int requests = 0;
      final HttpMediaFetcher fetcher = HttpMediaFetcher(
        client: MockClient((http.Request request) async {
          requests++;
          return _ok(_png(), contentType: 'image/png');
        }),
      );
      for (final String url in <String>[
        'http://127.0.0.1/a.png',
        'http://localhost/a.png',
        'http://192.168.1.10/a.png',
        'http://10.0.0.5/a.png',
        'http://169.254.169.254/latest/meta-data/a.png',
        'http://[::1]/a.png',
      ]) {
        final Result<MediaFetchResult> result = await fetcher.fetch(
          Uri.parse(url),
        );
        expect(result.isErr, isTrue, reason: '$url 必须被拒绝');
      }
      expect(requests, 0, reason: '被守卫拦下的地址不得产生任何请求');
    });

    test('公网域名解析到私网地址时被拒绝（DNS 复检）', () async {
      final HttpMediaFetcher fetcher = HttpMediaFetcher(
        client: MockClient(
          (http.Request request) async => _ok(_png(), contentType: 'image/png'),
        ),
        resolveHost: (String host) async => <InternetAddress>[
          InternetAddress('127.0.0.1'),
        ],
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://evil.example.com/a.png'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('私有网络'));
    });

    test('解析出多个地址时，只要有一个是私网就拒绝', () async {
      final HttpMediaFetcher fetcher = HttpMediaFetcher(
        client: MockClient(
          (http.Request request) async => _ok(_png(), contentType: 'image/png'),
        ),
        resolveHost: (String host) async => <InternetAddress>[
          InternetAddress('93.184.216.34'),
          InternetAddress('10.1.2.3'),
        ],
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://mixed.example.com/a.png'),
      );
      expect(result.isErr, isTrue);
    });

    test('非 http(s) 协议被拒绝', () async {
      final HttpMediaFetcher fetcher = _fetcher(
        handler: (_) => _ok(_png(), contentType: 'image/png'),
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('file:///etc/passwd'),
      );
      expect(result.isErr, isTrue);
    });
  });

  group('重定向', () {
    test('重定向到内网被拒绝（逐跳都校验）', () async {
      final HttpMediaFetcher fetcher = _fetcher(
        handler: (http.Request request) => http.Response(
          '',
          302,
          headers: <String, String>{'location': 'http://127.0.0.1/secret.png'},
        ),
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.png'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('私有网络'));
    });

    test('重定向到非 http(s) 协议被拒绝', () async {
      final HttpMediaFetcher fetcher = _fetcher(
        handler: (http.Request request) => http.Response(
          '',
          302,
          headers: <String, String>{'location': 'file:///etc/passwd'},
        ),
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.png'),
      );
      expect(result.isErr, isTrue);
    });

    test('正常跟随重定向并记录跳数', () async {
      final HttpMediaFetcher fetcher = _fetcher(
        handler: (http.Request request) {
          if (request.url.path == '/a.png') {
            return http.Response(
              '',
              302,
              headers: <String, String>{'location': '/b.png'},
            );
          }
          return _ok(_png(), contentType: 'image/png');
        },
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.png'),
      );
      expect(result.isOk, isTrue);
      expect(result.unwrap().redirectCount, 1);
    });

    test('重定向成环被拒绝（防同一地址无限跳）', () async {
      final HttpMediaFetcher fetcher = _fetcher(
        handler: (http.Request request) => http.Response(
          '',
          302,
          headers: <String, String>{'location': '/loop.png'},
        ),
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/loop.png'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('成环'));
    });
  });

  group('HTTP 失败', () {
    test('404 返回类型化错误（一张图失败不阻塞文章）', () async {
      final HttpMediaFetcher fetcher = _fetcher(
        handler: (_) => http.Response('gone', 404),
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.png'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<NetworkError>());
    });

    test('空响应体被拒绝', () async {
      final HttpMediaFetcher fetcher = _fetcher(
        handler: (_) => _ok(Uint8List(0), contentType: 'image/png'),
      );
      final Result<MediaFetchResult> result = await fetcher.fetch(
        Uri.parse('https://cdn.example.com/a.png'),
      );
      expect(result.isErr, isTrue);
    });
  });
}
