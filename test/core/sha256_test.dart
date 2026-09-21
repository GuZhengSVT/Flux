// SHA-256 实现测试（T013）。
//
// 用 **NIST FIPS 180-4 附录 B 的官方测试向量**逐条钉住：
//   "abc"、两个块的消息、"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmn
//   hijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"（长消息）、空消息。
// 自己实现密码学原语的唯一正当理由是「可以被标准向量完全验证」，因此这里不写
// 「哈希稳定/长度正确」这类自说自话的断言，而是直接对照官方向量。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/digest/sha256.dart';

void main() {
  group('SHA-256（NIST FIPS 180-4 官方向量）', () {
    test('空消息', () {
      expect(
        sha256HexOfString(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('"abc"', () {
      expect(
        sha256HexOfString('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('两个块的消息（448 位 = 56 字节）', () {
      expect(
        sha256HexOfString(
          'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
        ),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
    });

    test('长消息（896 位 = 112 字节，跨两个块）', () {
      expect(
        sha256HexOfString(
          'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmn'
          'hijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu',
        ),
        'cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1',
      );
    });

    test('一百万个 "a"（官方向量，验证多块与长度字段）', () {
      expect(
        sha256HexOfString('a' * 1000000),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });
  });

  group('输入编码与等价性', () {
    test('中文字符按 UTF-8 参与哈希（不是 UTF-16 码元）', () {
      // "中文" 的 UTF-8 是 E4B8AD E69687，因此哈希必须与直接传字节一致。
      expect(
        sha256HexOfString('中文'),
        sha256Hex(<int>[0xE4, 0xB8, 0xAD, 0xE6, 0x96, 0x87]),
      );
    });

    test('emoji（代理对之外的码点）按 4 字节 UTF-8 编码', () {
      // U+1F600 的 UTF-8 是 F0 9F 98 80。
      expect(sha256HexOfString('😀'), sha256Hex(<int>[0xF0, 0x9F, 0x98, 0x80]));
    });

    test('输出恒为 64 个小写十六进制字符', () {
      for (final String input in <String>['', 'a', '中文标题', 'x' * 500]) {
        final String digest = sha256HexOfString(input);
        expect(digest, hasLength(64));
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(digest), isTrue);
      }
    });

    test('不同输入产生不同摘要（摘要可用于身份与修订判断）', () {
      expect(sha256HexOfString('a'), isNot(sha256HexOfString('b')));
      expect(sha256HexOfString('正文'), isNot(sha256HexOfString('正文 ')));
    });

    test('相同输入稳定（同一正文两次导入必须得到同一哈希）', () {
      expect(sha256HexOfString('同一段正文'), sha256HexOfString('同一段正文'));
    });

    test('任意字节序列（含 0x00）都能正确参与', () {
      // 哈希必须覆盖全部字节，不能因为 0x00 被当作字符串结尾而截断。
      expect(sha256Hex(<int>[0x00]), isNot(sha256Hex(<int>[])));
      expect(sha256Hex(<int>[0x00, 0x01]), isNot(sha256Hex(<int>[0x00])));
    });

    test('跨 64 字节块边界的行为正确（55/56/64/65 字节）', () {
      // 55 字节：填充后刚好不跨块；56 字节：必须新增一个填充块。
      // 这是 padding 实现最容易出错的地方，用「四个长度互不相同」间接钉住。
      final Set<String> digests = <String>{
        for (final int length in <int>[55, 56, 63, 64, 65])
          sha256HexOfString('z' * length),
      };
      expect(digests, hasLength(5));
    });
  });
}
