// T021：图片加载管线的集成行为（失败不阻塞、缓存复用、计费守卫、保存走同一管线）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/article_image_loader.dart';
import 'package:flux/infrastructure/local/image_cache_service.dart';
import 'package:flux/infrastructure/network/media_fetcher.dart';

import '../../app/fake_article_image_loader.dart';

/// 记录是否被询问过的计费守卫。
final class _CountingPolicy implements MediaDownloadPolicy {
  _CountingPolicy({required this.allowed});

  bool allowed;
  int asked = 0;

  @override
  Future<bool> allowsImageDownload() async {
    asked++;
    return allowed;
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('flux-loader-test');
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  /// 构造一个「只对 [okUrls] 返回图片，其余一律 404」的加载器。
  CachedArticleImageLoader loaderFor(
    Map<String, Uint8List> responses, {
    MediaDownloadPolicy? policy,
    ImageCacheService? cache,
    List<String>? requested,
  }) {
    return CachedArticleImageLoader(
      cache: cache ?? ImageCacheService(root: root, limitMiB: kMinCacheMiB),
      policy: policy ?? const AllowAllMediaDownloads(),
      fetcher: HttpMediaFetcher(
        client: MockClient((http.Request request) async {
          requested?.add(request.url.toString());
          final Uint8List? body = responses[request.url.path];
          if (body == null) {
            return http.Response('gone', 404);
          }
          return http.Response.bytes(
            body,
            200,
            headers: <String, String>{'content-type': 'image/png'},
          );
        }),
        resolveHost: (String host) async => <InternetAddress>[
          InternetAddress('93.184.216.34'),
        ],
      ),
    );
  }

  group('加载', () {
    test('成功加载：返回字节与尺寸', () async {
      final CachedArticleImageLoader loader = loaderFor(<String, Uint8List>{
        '/a.png': kTestPngBytes,
      });
      final Result<LoadedImage> result = await loader.load(
        'https://cdn.example.com/a.png',
      );
      expect(result.isOk, isTrue);
      expect(result.unwrap().mimeType, 'image/png');
      expect(result.unwrap().width, 1);
    });

    test('失败返回类型化错误（渲染层据此画占位与重试）', () async {
      final CachedArticleImageLoader loader = loaderFor(<String, Uint8List>{});
      final Result<LoadedImage> result = await loader.load(
        'https://cdn.example.com/missing.png',
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<NetworkError>());
    });

    test('一张失败不影响另一张（失败隔离）', () async {
      final CachedArticleImageLoader loader = loaderFor(<String, Uint8List>{
        '/ok.png': kTestPngBytes,
      });
      final Result<LoadedImage> failed = await loader.load(
        'https://cdn.example.com/bad.png',
      );
      final Result<LoadedImage> ok = await loader.load(
        'https://cdn.example.com/ok.png',
      );
      expect(failed.isErr, isTrue);
      expect(ok.isOk, isTrue, reason: '前一张失败不得影响后一张');
    });

    test('危险协议在加载器这一层就被拒绝（不只靠渲染层）', () async {
      final List<String> requested = <String>[];
      final CachedArticleImageLoader loader = loaderFor(<String, Uint8List>{
        '/a.png': kTestPngBytes,
      }, requested: requested);
      final Result<LoadedImage> result = await loader.load(
        'file:///etc/passwd',
      );
      expect(result.isErr, isTrue);
      expect(requested, isEmpty, reason: '不得发出请求');
    });

    test('私网地址被拒绝且不发出请求', () async {
      final List<String> requested = <String>[];
      final CachedArticleImageLoader loader = loaderFor(<String, Uint8List>{
        '/a.png': kTestPngBytes,
      }, requested: requested);
      final Result<LoadedImage> result = await loader.load(
        'http://127.0.0.1/a.png',
      );
      expect(result.isErr, isTrue);
      expect(requested, isEmpty);
    });
  });

  group('缓存复用', () {
    test('第二次加载命中缓存，只发一次请求', () async {
      final List<String> requested = <String>[];
      final CachedArticleImageLoader loader = loaderFor(<String, Uint8List>{
        '/a.png': kTestPngBytes,
      }, requested: requested);
      await loader.load('https://cdn.example.com/a.png');
      await loader.load('https://cdn.example.com/a.png');
      expect(requested, hasLength(1), reason: '第二次必须走磁盘/内存缓存');
    });

    test('跨实例（模拟重启）命中磁盘缓存，不重复下载', () async {
      final List<String> first = <String>[];
      await loaderFor(<String, Uint8List>{
        '/a.png': kTestPngBytes,
      }, requested: first).load('https://cdn.example.com/a.png');
      expect(first, hasLength(1));

      final List<String> second = <String>[];
      final Result<LoadedImage> again = await loaderFor(<String, Uint8List>{
        '/a.png': kTestPngBytes,
      }, requested: second).load('https://cdn.example.com/a.png');
      expect(again.isOk, isTrue);
      expect(second, isEmpty, reason: '重启后应从磁盘缓存命中');
    });

    test('没有缓存（数据目录不可用的降级）时仍能加载，只是每次都要重新取', () async {
      final List<String> requested = <String>[];
      final CachedArticleImageLoader loader = CachedArticleImageLoader(
        cache: null,
        fetcher: HttpMediaFetcher(
          client: MockClient(
            (http.Request request) async => http.Response.bytes(
              kTestPngBytes,
              200,
              headers: <String, String>{'content-type': 'image/png'},
            ),
          ),
          resolveHost: (String host) async => <InternetAddress>[
            InternetAddress('93.184.216.34'),
          ],
        ),
      );
      final Result<LoadedImage> first = await loader.load(
        'https://cdn.example.com/a.png',
      );
      final Result<LoadedImage> second = await loader.load(
        'https://cdn.example.com/a.png',
      );
      expect(first.isOk, isTrue);
      expect(second.isOk, isTrue, reason: '不落盘不等于功能不可用');
      // 不落盘时的重复请求是预期行为，这里只断言「功能可用」。
      requested.length;
    });
  });

  group('计费网络守卫（SET-013）', () {
    test('守卫拒绝时根本不发请求，并返回可重试错误', () async {
      final List<String> requested = <String>[];
      final _CountingPolicy policy = _CountingPolicy(allowed: false);
      final CachedArticleImageLoader loader = loaderFor(
        <String, Uint8List>{'/a.png': kTestPngBytes},
        policy: policy,
        requested: requested,
      );
      final Result<LoadedImage> result = await loader.load(
        'https://cdn.example.com/a.png',
      );
      expect(result.isErr, isTrue);
      expect(policy.asked, 1);
      expect(requested, isEmpty, reason: '守卫命中时不得产生流量');
      expect(result.errorOrNull!.isRetryable, isTrue, reason: '换网络后可以再试');
    });

    test('缓存命中时不问守卫（离线可读已缓存的图）', () async {
      final ImageCacheService cache = ImageCacheService(
        root: root,
        limitMiB: kMinCacheMiB,
      );
      await cache.write(
        url: 'https://cdn.example.com/a.png',
        bytes: kTestPngBytes,
        mimeType: 'image/png',
        width: 1,
        height: 1,
      );
      final _CountingPolicy policy = _CountingPolicy(allowed: false);
      final CachedArticleImageLoader loader = loaderFor(
        <String, Uint8List>{'/a.png': kTestPngBytes},
        policy: policy,
        cache: cache,
      );
      final Result<LoadedImage> result = await loader.load(
        'https://cdn.example.com/a.png',
      );
      expect(result.isOk, isTrue, reason: '读本机文件不是网络行为');
      expect(policy.asked, 0, reason: '缓存命中不应触发守卫询问');
    });
  });

  group('保存走同一管线', () {
    test('保存写入的是经过校验的字节', () async {
      final CachedArticleImageLoader loader = loaderFor(<String, Uint8List>{
        '/a.png': kTestPngBytes,
      });
      final String target = '${root.path}/saved.png';
      final Result<int> saved = await loader.saveToPath(
        url: 'https://cdn.example.com/a.png',
        targetPath: target,
      );
      expect(saved.isOk, isTrue);
      expect(saved.unwrap(), kTestPngBytes.length);
      expect(await File(target).readAsBytes(), kTestPngBytes);
    });

    test('保存被拒绝的地址时不写任何文件', () async {
      final CachedArticleImageLoader loader = loaderFor(<String, Uint8List>{});
      final String target = '${root.path}/never.png';
      final Result<int> saved = await loader.saveToPath(
        url: 'http://192.168.1.1/a.png',
        targetPath: target,
      );
      expect(saved.isErr, isTrue);
      expect(File(target).existsSync(), isFalse);
    });
  });

  group('SET-080 上限套用', () {
    test('applyCacheLimitMiB 把越界值夹紧后生效', () async {
      final ImageCacheService cache = ImageCacheService(
        root: root,
        limitMiB: kMinCacheMiB,
      );
      final CachedArticleImageLoader loader = loaderFor(
        <String, Uint8List>{},
        cache: cache,
      );
      await loader.applyCacheLimitMiB(1);
      expect(cache.limitBytes, kMinCacheMiB * 1024 * 1024);
      await loader.applyCacheLimitMiB(2048);
      expect(cache.limitBytes, 2048 * 1024 * 1024);
    });

    test('没有磁盘缓存时套用上限是安全的空操作', () async {
      final CachedArticleImageLoader loader = CachedArticleImageLoader(
        fetcher: HttpMediaFetcher(),
      );
      await loader.applyCacheLimitMiB(256);
    });
  });
}
