// T020 的平台适配器测试：外开协议二次校验、图片下载上限、分享通道不可用。
//
// 为什么这些边界必须在本层测（而不是只测上层替身）：
//   - 外开适配器是「把地址交给操作系统」的最后一道关口，上层校验过不代表这里可以省；
//   - 下载上限是本任务唯一能防止「点一次保存就把内存吃干净」的机制；
//   - 分享在非 macOS 或不支持的宿主上必须是「不可用」而不是崩溃。
//
// 这些用例不联网：外开的失败路径在协议校验阶段就返回；图片下载用 MockClient。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/platform/external_link_opener.dart';
import 'package:flux/infrastructure/platform/image_save_service.dart';
import 'package:flux/infrastructure/platform/system_share_service.dart';

void main() {
  // 分享适配器要走 MethodChannel，需要绑定初始化（纯 Dart 的 test() 不会自己做）。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('外开适配器：协议在最后一道关口再校验一次', () {
    const UrlLauncherLinkOpener opener = UrlLauncherLinkOpener();

    test('危险协议被拒绝（不会交给系统启动器）', () async {
      for (final String url in <String>[
        'javascript:alert(1)',
        'data:text/html,x',
        'file:///etc/passwd',
        // 相对地址同样拒绝：本层没有可信的 base URL，替调用方补一个等于替它做决定。
        '/relative/path',
      ]) {
        final Result<bool> result = await opener.openExternal(url);
        expect(result.isErr, isTrue, reason: '$url 不得被交给系统');
      }
    });
  });

  group('图片保存适配器：下载上限与协议校验', () {
    test('危险协议的图片地址被拒（不是只靠上层判）', () async {
      const HttpImageSaveService service = HttpImageSaveService();
      final Result<String?> result = await service.saveImage(
        url: 'file:///etc/passwd',
        suggestedName: 'x.png',
      );
      expect(result.isErr, isTrue);
    });

    test('声明长度超过上限时在读完之前就拒绝', () async {
      final HttpImageSaveService service = HttpImageSaveService(
        client: MockClient(
          (http.Request request) async => http.Response.bytes(
            Uint8List(kMaxDownloadBytes + 1),
            200,
            headers: <String, String>{
              'content-length': (kMaxDownloadBytes + 1).toString(),
            },
          ),
        ),
      );
      final Result<String?> result = await service.saveImage(
        url: 'https://cdn.example.com/huge.png',
        suggestedName: 'huge.png',
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('声明长度超过上限'));
    });

    test('未声明长度但实际超限时中止读取', () async {
      // 流式响应：分块吐出的总长度超过上限。
      final HttpImageSaveService service = HttpImageSaveService(
        client: MockClient.streaming((http.BaseRequest request, _) async {
          final Stream<List<int>> stream = Stream<List<int>>.fromIterable(
            <List<int>>[
              for (int i = 0; i < 5; i++)
                List<int>.filled(kMaxDownloadBytes ~/ 3, 0),
            ],
          );
          return http.StreamedResponse(stream, 200);
        }),
      );
      final Result<String?> result = await service.saveImage(
        url: 'https://cdn.example.com/stream.png',
        suggestedName: 'stream.png',
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('实际长度超过上限'));
    });

    test('HTTP 失败被翻译成类型化错误（不抛平台异常）', () async {
      final HttpImageSaveService service = HttpImageSaveService(
        client: MockClient(
          (http.Request request) async => http.Response('nope', 404),
        ),
      );
      final Result<String?> result = await service.saveImage(
        url: 'https://cdn.example.com/missing.png',
        suggestedName: 'missing.png',
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('404'));
    });
  });

  group('系统分享适配器：通道不可用时报告不可用而不是崩溃', () {
    test('测试环境里没有原生通道 → isAvailable 为 false', () async {
      const NativeSystemShareService share = NativeSystemShareService();
      // 组件测试环境没有注册 macOS 通道；返回 false 让上层回退复制（架构 4.2）。
      expect(await share.isAvailable(), isFalse);
    });

    test('空文本被拒绝（没有可分享的内容）', () async {
      const NativeSystemShareService share = NativeSystemShareService();
      final Result<bool> result = await share.shareText('   ');
      expect(result.isErr, isTrue);
    });

    test('通道不存在时返回类型化失败而不是抛异常', () async {
      const NativeSystemShareService share = NativeSystemShareService();
      final Result<bool> result = await share.shareText('一段文字');
      expect(result.isErr, isTrue);
    });
  });
}
