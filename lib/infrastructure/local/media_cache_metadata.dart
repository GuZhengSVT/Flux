// 图片缓存条目元数据（T021）。
//
// 为什么需要一份元数据文件，而不是从图片字节里现读：
//   - MIME 与尺寸在**下载时**已由 media_fetcher 校验过，读回来时重新嗅探等于把已经
//     成立的校验重做一遍，还多一个「这次嗅探失败怎么办」的分支；
//   - 字节长度是**完整性检查**的依据：文件被截断（写入中断、磁盘满）时长度不符，
//     必须能判定为损坏并丢弃，而不是把半个图交给解码器。
//
// 用 JSON 而不是二进制前缀：缓存文件要能被人工查看与排查，且本项目已在
// settings/diagnostics 里统一用 JSON 表达「结构化的小数据」。
library;

import 'dart:convert';

/// 缓存条目的元数据。
final class CachedImageMeta {
  /// 构造元数据。
  const CachedImageMeta({
    required this.mimeType,
    required this.width,
    required this.height,
    required this.byteLength,
    required this.storedAt,
  });

  /// MIME（下载时已校验的类型）。
  final String mimeType;

  /// 宽。
  final int width;

  /// 高。
  final int height;

  /// 字节长度（完整性检查）。
  final int byteLength;

  /// 写入时间（UTC）。
  final DateTime storedAt;

  /// 编码为 JSON 文本。
  String encode() => jsonEncode(<String, Object?>{
    'mimeType': mimeType,
    'width': width,
    'height': height,
    'byteLength': byteLength,
    'storedAt': storedAt.toUtc().toIso8601String(),
  });

  /// 解析 JSON 文本；结构不合法时返回 null（调用方按损坏处理）。
  ///
  /// 不抛异常：元数据来自磁盘，损坏是可预期的（半写、手工编辑、旧版本格式），
  /// 让调用方用一条 if 处理比用 try/catch 更清楚。
  static CachedImageMeta? parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      // 半写或手工改动过的文件：明确的「不是合法 JSON」，按损坏处理。
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final Object? mimeType = decoded['mimeType'];
    final Object? width = decoded['width'];
    final Object? height = decoded['height'];
    final Object? byteLength = decoded['byteLength'];
    final Object? storedAt = decoded['storedAt'];
    if (mimeType is! String ||
        width is! int ||
        height is! int ||
        byteLength is! int ||
        storedAt is! String) {
      return null;
    }
    if (width <= 0 || height <= 0 || byteLength <= 0) {
      return null;
    }
    final DateTime? parsedAt = DateTime.tryParse(storedAt);
    if (parsedAt == null) {
      return null;
    }
    return CachedImageMeta(
      mimeType: mimeType,
      width: width,
      height: height,
      byteLength: byteLength,
      storedAt: parsedAt.toUtc(),
    );
  }
}
