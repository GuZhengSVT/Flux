// 最小 ZIP 写入/读取（T046；架构 5.3 的「明文 ZIP 备份」）。
//
// 为什么自己实现而不是引入 archive 包：
//   * 本任务的依赖清单里没有压缩库，而备份只要「多个文件打进一个容器」这一件事；
//   * 更关键的是**读取侧**：恢复路径必须能对条目名做路径检查（架构 5.3「压缩包拒绝绝对
//     路径和路径穿越」），而自实现让「解出哪些条目、写到哪里」完全在本工程手里——
//     第三方解压器把条目先落到磁盘再交给调用方检查，检查就晚了；
//   * 压缩用 dart:io 的 ZLibCodec(raw: true)（DEFLATE 裸流，ZIP 的压缩方法 8），
//     不需要任何第三方依赖。
//
// 支持范围（刻意的窄）：只写 entries（无目录条目、无 Zip64、无加密），读时接受
// stored(0) 与 deflate(8)，并对「不符声明」的条目**明确失败**而不是尽力而为。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 一个要写进 ZIP 的条目。
final class ZipEntry {
  /// 构造条目。
  const ZipEntry({required this.name, required this.bytes});

  /// 包内条目名（**正斜杠分隔的相对路径**；安全检查由调用方按域规则做）。
  final String name;

  /// 未压缩内容。
  final Uint8List bytes;
}

/// 解出来的一个条目。
final class ZipDecodedEntry {
  /// 构造条目。
  const ZipDecodedEntry({required this.name, required this.bytes});

  /// 包内条目名。
  final String name;

  /// 解压后的内容。
  final Uint8List bytes;
}

/// 编码一个 ZIP 存档（内容用 DEFLATE 压缩；小条目压缩后更大时退回 stored）。
Uint8List zipEncode(List<ZipEntry> entries) {
  final BytesBuilder body = BytesBuilder(copy: false);
  final List<_CentralRecord> records = <_CentralRecord>[];
  for (final ZipEntry entry in entries) {
    final List<int> nameBytes = utf8.encode(entry.name);
    final int crc = _crc32(entry.bytes);
    final List<int> deflated = _deflate(entry.bytes);
    final bool useDeflate = deflated.length < entry.bytes.length;
    final List<int> payload = useDeflate ? deflated : entry.bytes;
    final int method = useDeflate ? 8 : 0;
    final int offset = body.length;

    final BytesBuilder local = BytesBuilder(copy: false);
    local.add(_u32(0x04034b50)); // 本地文件头签名
    local.add(_u16(20)); // 需要版本 2.0（DEFLATE）
    // 通用标志位第 11 位（0x0800）：文件名是 UTF-8。不设它时，含非 ASCII 的名字
    // 在别人的解压器里会按 CP437 解读成乱码（而本工程的中文媒体路径并不罕见）。
    local.add(_u16(0x0800));
    local.add(_u16(method));
    local.add(_u16(0)); // 修改时间
    local.add(_u16(0)); // 修改日期
    local.add(_u32(crc));
    local.add(_u32(payload.length));
    local.add(_u32(entry.bytes.length));
    local.add(_u16(nameBytes.length));
    local.add(_u16(0)); // 扩展字段长度
    local.add(nameBytes);
    local.add(payload);
    body.add(local.takeBytes());

    records.add(
      _CentralRecord(
        nameBytes: nameBytes,
        crc: crc,
        compressedSize: payload.length,
        uncompressedSize: entry.bytes.length,
        method: method,
        offset: offset,
      ),
    );
  }

  final Uint8List bodyBytes = body.takeBytes();
  final BytesBuilder central = BytesBuilder(copy: false);
  for (final _CentralRecord record in records) {
    central.add(_u32(0x02014b50)); // 中央目录签名
    central.add(_u16(20)); // 创建版本
    central.add(_u16(20)); // 需要版本
    central.add(_u16(0x0800)); // 标志位（与本地头一致：UTF-8 文件名）
    central.add(_u16(record.method));
    central.add(_u16(0));
    central.add(_u16(0));
    central.add(_u32(record.crc));
    central.add(_u32(record.compressedSize));
    central.add(_u32(record.uncompressedSize));
    central.add(_u16(record.nameBytes.length));
    central.add(_u16(0)); // 扩展字段
    central.add(_u16(0)); // 注释
    central.add(_u16(0)); // 磁盘号
    central.add(_u16(0)); // 内部属性
    central.add(_u32(0)); // 外部属性
    central.add(_u32(record.offset));
    central.add(record.nameBytes);
  }
  final Uint8List centralBytes = central.takeBytes();

  final BytesBuilder out = BytesBuilder(copy: false);
  out.add(bodyBytes);
  out.add(centralBytes);
  out.add(_u32(0x06054b50)); // 中央目录结束记录
  out.add(_u16(0));
  out.add(_u16(0));
  out.add(_u16(records.length));
  out.add(_u16(records.length));
  out.add(_u32(centralBytes.length));
  out.add(_u32(bodyBytes.length));
  out.add(_u16(0)); // 注释长度
  return out.takeBytes();
}

/// 解析一个 ZIP 存档。
///
/// 任何结构问题（不是 ZIP、截断、中央目录指向包外、CRC 不符、**压缩方法不支持**）都返回
/// null：恢复路径据此报「包损坏」并**不动原库**，而不是解开一半再失败。
List<ZipDecodedEntry>? zipDecode(Uint8List bytes) {
  final int? eocd = _findEndOfCentralDirectory(bytes);
  if (eocd == null) {
    return null;
  }
  final int total = _u16At(bytes, eocd + 10);
  final int centralSize = _u32At(bytes, eocd + 12);
  final int centralOffset = _u32At(bytes, eocd + 16);
  if (centralOffset + centralSize > bytes.length ||
      total == 0xffff ||
      centralOffset == 0xffffffff) {
    // Zip64（0xffff/0xffffffff）不在支持范围内：明确拒绝而不是猜一个偏移。
    return null;
  }

  final List<ZipDecodedEntry> entries = <ZipDecodedEntry>[];
  int cursor = centralOffset;
  for (int i = 0; i < total; i++) {
    if (cursor + 46 > bytes.length || _u32At(bytes, cursor) != 0x02014b50) {
      return null;
    }
    final int method = _u16At(bytes, cursor + 10);
    final int crc = _u32At(bytes, cursor + 16);
    final int compressedSize = _u32At(bytes, cursor + 20);
    final int uncompressedSize = _u32At(bytes, cursor + 24);
    final int nameLength = _u16At(bytes, cursor + 28);
    final int extraLength = _u16At(bytes, cursor + 30);
    final int commentLength = _u16At(bytes, cursor + 32);
    final int localOffset = _u32At(bytes, cursor + 42);
    final int nameStart = cursor + 46;
    if (nameStart + nameLength > bytes.length) {
      return null;
    }
    final String name = utf8.decode(
      bytes.sublist(nameStart, nameStart + nameLength),
      allowMalformed: true,
    );
    cursor = nameStart + nameLength + extraLength + commentLength;

    if (localOffset + 30 > bytes.length ||
        _u32At(bytes, localOffset) != 0x04034b50) {
      return null;
    }
    final int localNameLength = _u16At(bytes, localOffset + 26);
    final int localExtraLength = _u16At(bytes, localOffset + 28);
    final int dataStart = localOffset + 30 + localNameLength + localExtraLength;
    if (dataStart + compressedSize > bytes.length) {
      return null;
    }
    final Uint8List raw = Uint8List.sublistView(
      bytes,
      dataStart,
      dataStart + compressedSize,
    );
    final Uint8List? content = switch (method) {
      0 => Uint8List.fromList(raw),
      8 => _inflate(raw),
      _ => null,
    };
    if (content == null || content.length != uncompressedSize) {
      return null;
    }
    if (_crc32(content) != crc) {
      return null;
    }
    entries.add(ZipDecodedEntry(name: name, bytes: content));
  }
  return entries;
}

/// 从末尾向前找「中央目录结束记录」签名（ZIP 允许尾部有注释，最多 65535 字节）。
int? _findEndOfCentralDirectory(Uint8List bytes) {
  final int lowest = bytes.length - 22 - 0xffff;
  for (int i = bytes.length - 22; i >= 0 && i >= lowest; i--) {
    if (_u32At(bytes, i) == 0x06054b50) {
      return i;
    }
  }
  return null;
}

/// 原始 DEFLATE 压缩（ZIP 方法 8）。
List<int> _deflate(Uint8List input) =>
    ZLibCodec(raw: true, level: 6).encode(input);

/// 原始 DEFLATE 解压；数据非法时返回 null（不让异常穿透到恢复流程之外）。
Uint8List? _inflate(Uint8List input) {
  try {
    return Uint8List.fromList(ZLibCodec(raw: true).decode(input));
  } on Exception {
    return null;
  }
}

Uint8List _u16(int value) =>
    Uint8List.fromList(<int>[value & 0xff, (value >> 8) & 0xff]);

Uint8List _u32(int value) => Uint8List.fromList(<int>[
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
]);

int _u16At(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _u32At(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

/// CRC-32（ZIP 用的标准多项式 0xEDB88320，表驱动）。
int _crc32(List<int> bytes) {
  int crc = 0xffffffff;
  for (final int byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

/// CRC-32 查表（首次使用时按多项式生成）。
final List<int> _crcTable = List<int>.generate(256, (int index) {
  int value = index;
  for (int bit = 0; bit < 8; bit++) {
    value = (value & 1) == 1 ? 0xedb88320 ^ (value >> 1) : value >> 1;
  }
  return value & 0xffffffff;
}, growable: false);

/// 中央目录里一条记录需要的字段。
final class _CentralRecord {
  const _CentralRecord({
    required this.nameBytes,
    required this.crc,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.method,
    required this.offset,
  });

  final List<int> nameBytes;
  final int crc;
  final int compressedSize;
  final int uncompressedSize;
  final int method;
  final int offset;
}
