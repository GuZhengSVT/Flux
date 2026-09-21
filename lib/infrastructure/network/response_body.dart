// 有界响应体读取与文本解码（T024 从 T013 的 feed_fetcher 中抽出）。
//
// 为什么必须共用而不是各写一份：这里全部是**体积与解压防线**（响应体上限、边解压边
// 计数的 gzip 上限、BOM/charset 解码）。写两份的必然结果是其中一份被加固而另一份没跟上，
// 于是「订阅抓取挡住了压缩炸弹、静态网页抓取没挡住」——而这两条路径面对的是同一类
// 不可信输入（第三方网页）。T021 已经把**地址守卫**抽成共用的 UrlGuardPolicy，这里
// 抽出的是同一层里另一半：字节边界。
//
// 三条不可退让的实现选择（与 T013 原实现一致，行为不变）：
//   1) **流式计数**而不是读完后检查长度：后者在 10 GiB 响应面前已经先把内存吃光；
//   2) **chunked 解压**而不是 gzip.decode(bytes)：一次性转换器会先构造出完整结果，
//      上限等于没有；chunked 入口允许在每个输出分块上计数并立刻中止；
//   3) **非空输入解出空结果**视为损坏：dart:io 的增量解压对截断输入是宽容的（不报错、
//      只是不再产出），不显式检查就会把损坏响应描述成「成功、正文为空」。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';

/// 已读取但尚未解码的响应体。
final class RawResponseBody {
  /// 构造原始体。
  const RawResponseBody({required this.bytes, this.contentEncoding});

  /// 原始字节（可能是压缩的）。
  final Uint8List bytes;

  /// Content-Encoding 头。
  final String? contentEncoding;
}

/// 按上限流式读取响应体。
///
/// [limitKind] 只用于超时错误的类别标识，让诊断里能分辨「订阅抓取超时」与「网页抓取
/// 超时」，而不是都记成同一个字符串。
Future<Result<RawResponseBody>> readBoundedBody(
  http.StreamedResponse response, {
  required int maxBytes,
  required Duration timeout,
  required String limitKind,
}) async {
  final int? declared = response.contentLength;
  if (declared != null && declared > maxBytes) {
    return Err<RawResponseBody>(
      NetworkError(
        uri: response.request?.url.toString() ?? '',
        reason: '响应体声明长度 $declared 超过上限 $maxBytes',
      ),
    );
  }

  final BytesBuilder builder = BytesBuilder(copy: false);
  int total = 0;
  try {
    await for (final List<int> chunk in response.stream.timeout(
      timeout,
      onTimeout: (EventSink<List<int>> sink) =>
          sink.addError(TimeoutException(limitKind, timeout)),
    )) {
      total += chunk.length;
      if (total > maxBytes) {
        return Err<RawResponseBody>(
          NetworkError(
            uri: response.request?.url.toString() ?? '',
            reason: '响应体超过上限 $maxBytes 字节',
          ),
        );
      }
      builder.add(chunk);
    }
  } on TimeoutException {
    return Err<RawResponseBody>(
      DeadlineExceededError(limitKind: limitKind, limit: timeout),
    );
  } on Exception catch (error) {
    return Err<RawResponseBody>(
      NetworkError(
        uri: response.request?.url.toString() ?? '',
        reason: '读取响应体失败（${error.runtimeType}）',
        cause: error,
      ),
    );
  }

  return Ok<RawResponseBody>(
    RawResponseBody(
      bytes: builder.takeBytes(),
      contentEncoding: response.headers['content-encoding'],
    ),
  );
}

/// 解压（如需要）并解码为文本；解压**后**同样限长。
Result<String> decodeResponseBody(
  RawResponseBody raw, {
  required int maxBytes,
}) {
  Uint8List bytes = raw.bytes;
  final String? encoding = raw.contentEncoding?.toLowerCase();
  if (encoding != null && encoding.contains('gzip')) {
    final Result<Uint8List> inflated = gunzipBounded(bytes, maxBytes: maxBytes);
    if (inflated.isErr) {
      return Err<String>(inflated.errorOrNull!);
    }
    bytes = inflated.unwrap();
  }
  return Ok<String>(decodeText(bytes));
}

/// 有界 gzip 解压（压缩炸弹防线）。
Result<Uint8List> gunzipBounded(Uint8List input, {required int maxBytes}) {
  final _BoundedSink sink = _BoundedSink(maxBytes);
  try {
    final ByteConversionSink decoder = ZLibDecoder(gzip: true)
        .startChunkedConversion(sink);
    // 分块喂入：输入侧已受上限限制，这里按 64 KiB 切片是为了让「边解压边计数」
    // 尽可能早地触发中止。
    const int chunkSize = 64 * 1024;
    for (int offset = 0; offset < input.length; offset += chunkSize) {
      final int end = (offset + chunkSize).clamp(0, input.length);
      decoder.add(input.sublist(offset, end));
    }
    decoder.close();
  } on _BodyTooLargeException {
    return Err<Uint8List>(
      NetworkError(uri: '', reason: '解压后超过上限 $maxBytes 字节（疑似压缩炸弹）'),
    );
  } on FormatException catch (error) {
    return Err<Uint8List>(
      NetworkError(
        uri: '',
        reason: 'gzip 数据非法（${error.message}）',
        cause: error,
      ),
    );
  } on Exception catch (error) {
    return Err<Uint8List>(
      NetworkError(
        uri: '',
        reason: 'gzip 解压失败（${error.runtimeType}）',
        cause: error,
      ),
    );
  }
  final Uint8List decoded = sink.takeBytes();
  if (input.isNotEmpty && decoded.isEmpty) {
    return Err<Uint8List>(
      NetworkError(uri: '', reason: 'gzip 数据损坏或被截断（非空输入未解出任何内容）'),
    );
  }
  return Ok<Uint8List>(decoded);
}

/// 字节转文本：先看 BOM，再尝试 UTF-8，最后退到 latin-1。
///
/// 退到 latin-1 而不是「用替换字符填充」：latin-1 对任意字节都能构造出确定文本，
/// 至少不会让整篇正文变成一个问号；源站编码声明错误是现实里很常见的情况。
String decodeText(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return decodeUtf16(bytes.sublist(2), littleEndian: false);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes, allowInvalid: true);
  }
}

/// UTF-16（带 BOM 的两种字节序）。
String decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final List<int> units = <int>[];
  for (int i = 0; i + 1 < bytes.length; i += 2) {
    units.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(units);
}

/// 超出体积上限的内部信号。
class _BodyTooLargeException implements Exception {
  const _BodyTooLargeException();
}

/// 带输出上限的字节收集器（gzip 解压的输出侧防线）。
///
/// 作为 ByteConversionSink 接收解码器的输出：每次 add 都在累计长度上检查，超限立即
/// 抛 _BodyTooLargeException。因为解码器是 chunked 的，异常会在解压**过程中**抛出，
/// 而不是等整段解完——这正是「上限真的挡得住压缩炸弹」与「上限只是事后检查」的区别。
class _BoundedSink extends ByteConversionSinkBase {
  _BoundedSink(this.limit);

  final int limit;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  int _length = 0;

  @override
  void add(List<int> chunk) {
    if (chunk.isEmpty) {
      return;
    }
    _length += chunk.length;
    if (_length > limit) {
      throw const _BodyTooLargeException();
    }
    _builder.add(chunk);
  }

  @override
  void close() {}

  /// 取出已收集的全部字节。
  Uint8List takeBytes() => _builder.takeBytes();
}
