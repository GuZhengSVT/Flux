// SHA-256（FIPS 180-4）最小实现（T013）。
//
// 为什么不加 crypto 包：本任务的依赖白名单只有 flutter_svg 与 xml，而正文哈希与
// 指纹确实需要 SHA-256。crypto 虽然已经在依赖图里（sqlite3 的传递依赖），但把它提升为
// **直接依赖**会扩大供应链面，而这里需要的只是一条公开、固定、完全可测的算法。
// 因此自己实现：算法由标准定义，且有 NIST 官方测试向量可以逐条钉住（见
// test/core/sha256_test.dart），比信任一个包更可验证。
//
// 用途（都不是密码学用途，只是稳定的内容摘要）：
//   - fallbackFingerprint：把「来源 + 标题 + 时间」压成固定长度的身份指纹；
//   - bodyHashOf：判断正文是否发生了修订。
// 因此本实现**不**追求抗侧信道等密码学工程属性，追求的是「与标准完全一致」。
library;

/// SHA-256 的初始哈希值（前 8 个素数平方根的小数部分前 32 位）。
const List<int> _initialState = <int>[
  0x6a09e667,
  0xbb67ae85,
  0x3c6ef372,
  0xa54ff53a,
  0x510e527f,
  0x9b05688c,
  0x1f83d9ab,
  0x5be0cd19,
];

/// 轮常量（前 64 个素数立方根的小数部分前 32 位）。
const List<int> _roundConstants = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

/// 计算 [input] 的 SHA-256，返回 64 个小写十六进制字符。
String sha256Hex(List<int> input) {
  // ---- 填充：0x80 + 若干 0x00 + 64 位大端比特长度 --------------------------
  final int messageLength = input.length;
  final int bitLengthHigh = (messageLength >> 29) & 0xFFFFFFFF; // 长度上限 2^61 字节
  final int bitLengthLow = (messageLength << 3) & 0xFFFFFFFF;

  // 填充到 56 mod 64，再追加 8 字节长度。
  final int paddedLength = ((messageLength + 8) ~/ 64 + 1) * 64;
  final List<int> padded = List<int>.filled(paddedLength, 0);
  for (int i = 0; i < messageLength; i++) {
    padded[i] = input[i] & 0xFF;
  }
  padded[messageLength] = 0x80;
  _writeUint32BigEndian(padded, paddedLength - 8, bitLengthHigh);
  _writeUint32BigEndian(padded, paddedLength - 4, bitLengthLow);

  // ---- 逐块压缩 -----------------------------------------------------------
  final List<int> hash = List<int>.of(_initialState);
  final List<int> w = List<int>.filled(64, 0);

  for (int block = 0; block < paddedLength; block += 64) {
    for (int i = 0; i < 16; i++) {
      w[i] = _readUint32BigEndian(padded, block + i * 4);
    }
    for (int i = 16; i < 64; i++) {
      final int s0 =
          _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final int s1 =
          _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = _add32(_add32(w[i - 16], s0), _add32(w[i - 7], s1));
    }

    int a = hash[0];
    int b = hash[1];
    int c = hash[2];
    int d = hash[3];
    int e = hash[4];
    int f = hash[5];
    int g = hash[6];
    int h = hash[7];

    for (int i = 0; i < 64; i++) {
      final int s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final int ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
      final int temp1 = _add32(
        _add32(_add32(_add32(h, s1), ch), _roundConstants[i]),
        w[i],
      );
      final int s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final int maj = (a & b) ^ (a & c) ^ (b & c);
      final int temp2 = _add32(s0, maj);

      h = g;
      g = f;
      f = e;
      e = _add32(d, temp1);
      d = c;
      c = b;
      b = a;
      a = _add32(temp1, temp2);
    }

    hash[0] = _add32(hash[0], a);
    hash[1] = _add32(hash[1], b);
    hash[2] = _add32(hash[2], c);
    hash[3] = _add32(hash[3], d);
    hash[4] = _add32(hash[4], e);
    hash[5] = _add32(hash[5], f);
    hash[6] = _add32(hash[6], g);
    hash[7] = _add32(hash[7], h);
  }

  final StringBuffer out = StringBuffer();
  for (final int word in hash) {
    out.write(word.toRadixString(16).padLeft(8, '0'));
  }
  return out.toString();
}

/// 计算字符串 UTF-8 编码的 SHA-256。
String sha256HexOfString(String input) => sha256Hex(_utf8Bytes(input));

/// 32 位加法（模 2^32）。
int _add32(int a, int b) => (a + b) & 0xFFFFFFFF;

/// 32 位循环右移。
int _rotr(int value, int amount) =>
    ((value >> amount) | (value << (32 - amount))) & 0xFFFFFFFF;

int _readUint32BigEndian(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

void _writeUint32BigEndian(List<int> bytes, int offset, int value) {
  bytes[offset] = (value >> 24) & 0xFF;
  bytes[offset + 1] = (value >> 16) & 0xFF;
  bytes[offset + 2] = (value >> 8) & 0xFF;
  bytes[offset + 3] = value & 0xFF;
}

/// UTF-8 编码。
///
/// 自己编码而不是用 `utf8.encode`：后者返回 `Uint8List`，本身没问题，但这里只需要
/// 「字符串 → 字节」这一件事，显式写出编码规则可以让「非 ASCII 字符（中文标题）参与
/// 指纹」这条行为被测试直接验证，而不是依赖对标准库行为的记忆。
List<int> _utf8Bytes(String input) {
  final List<int> out = <int>[];
  for (final int rune in input.runes) {
    if (rune <= 0x7F) {
      out.add(rune);
    } else if (rune <= 0x7FF) {
      out.add(0xC0 | (rune >> 6));
      out.add(0x80 | (rune & 0x3F));
    } else if (rune <= 0xFFFF) {
      out.add(0xE0 | (rune >> 12));
      out.add(0x80 | ((rune >> 6) & 0x3F));
      out.add(0x80 | (rune & 0x3F));
    } else {
      out.add(0xF0 | (rune >> 18));
      out.add(0x80 | ((rune >> 12) & 0x3F));
      out.add(0x80 | ((rune >> 6) & 0x3F));
      out.add(0x80 | (rune & 0x3F));
    }
  }
  return out;
}
