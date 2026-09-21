// SSE（Server-Sent Events）解析（T026；两个 OpenAI 协议共用）。
//
// 为什么把「切 SSE」抽出来共用而不是各适配器写一遍：Chat Completions 与 Responses
// 的**事件负载**完全不同（前者是 chunk 里的 choices/delta，后者是带 type 的事件对象），
// 但**传输层语法是同一套**：行以 \n 分隔、`data:` 前缀、空行表示一个事件结束、
// 以 `:` 开头的行是注释（心跳）。写两份的结果必然是其中一份漏了某个边界。
//
// 四条边界在这里被显式处理（每一条都是实测/推演出来的必踩点）：
//   1) **按字节切行，再解码整行**。这是最关键的一条：如果对每个收到的字节块单独做
//      utf8.decode，一个被 TCP 分段切开的多字节字符会解成替换字符（「连接」变成
//      「\uFFFD接」）。中文输出下这条几乎必然触发，因此解码必须发生在**完整行**上；
//      跨块仍未闭合的尾部字节保留到下一块。
//   2) **CRLF**：行尾剥掉 \r（服务商与中间代理都可能用 CRLF）；
//   3) **多行 data**：SSE 规范允许一个事件有多行 data，用 \n 拼成一个负载；
//   4) **上限**：单个事件与整条流都有上限，避免异常响应把内存吃光（实现防线，
//      不是产品设置项）。
//
// 不做的事：不解析 `event:` / `id:` / `retry:`。两个协议的事件类型都在 JSON 负载
// 内部（Responses 有 `type` 字段，Chat Completions 靠 chunk 形状），解析 `event:` 只会
// 多出一份可能与负载不一致的真相来源。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flux/core/core.dart';

/// 单个 SSE 事件负载的字节上限（超过即判为异常响应）。
///
/// 取 1 MiB：正常的增量文本块是几十到几千字节，1 MiB 已经比任何合法事件大几个数量级；
/// 而一旦某个中间代理把整段 HTML 错误页当作一个 data 行发出来，这条限制会让它明确失败，
/// 而不是把几百 MB 塞进内存。
const int maxSseEventBytes = 1024 * 1024;

/// 单个响应流的累计字节上限（16 MiB）。
///
/// 一个很长的模型输出（例如 8k token 的中文）也只有几十 KiB；16 MiB 是数量级余量，
/// 同时保证「服务商发了一个无限流」不会让进程无界增长。
const int maxSseStreamBytes = 16 * 1024 * 1024;

/// 换行字节。
const int _lf = 0x0A;

/// 回车字节。
const int _cr = 0x0D;

/// 把一个字节流解析成 SSE 事件负载序列（按到达顺序）。
Stream<String> sseEventPayloads(
  Stream<List<int>> bytes, {
  required Uri endpoint,
}) async* {
  final List<String> dataLines = <String>[];
  // 跨块保留的**未闭合行字节**（可能以半个多字节字符结尾，因此必须是字节而非字符串）。
  final BytesBuilder pending = BytesBuilder(copy: false);
  int totalBytes = 0;

  String? takeLine() {
    final Uint8List buffered = pending.takeBytes();
    final int index = buffered.indexOf(_lf);
    if (index < 0) {
      // 没有完整行：把字节放回去等下一块。
      pending.add(buffered);
      return null;
    }
    pending.add(Uint8List.sublistView(buffered, index + 1, buffered.length));
    return _decodeLine(Uint8List.sublistView(buffered, 0, index));
  }

  await for (final List<int> chunk in bytes) {
    totalBytes += chunk.length;
    if (totalBytes > maxSseStreamBytes) {
      throw NetworkError(
        uri: endpoint.toString(),
        reason: '流式响应超过上限 $maxSseStreamBytes 字节',
      );
    }
    pending.add(chunk);
    while (true) {
      final String? line = takeLine();
      if (line == null) {
        break;
      }
      final String? payload = _consumeLine(line, dataLines, endpoint);
      if (payload != null) {
        yield payload;
      }
    }
  }

  // 流结束时处理最后一行（服务商少发末尾换行是常见偏差，丢掉它会让最后一次增量、
  // 甚至 usage，静默消失）。
  final Uint8List tail = pending.takeBytes();
  if (tail.isNotEmpty) {
    final String? payload = _consumeLine(
      _decodeLine(tail),
      dataLines,
      endpoint,
    );
    if (payload != null) {
      yield payload;
    }
  }
  if (dataLines.isNotEmpty) {
    yield dataLines.join('\n');
  }
}

/// 处理一行：返回非 null 表示该行**结束了一个事件**且需要派发负载。
String? _consumeLine(String rawLine, List<String> dataLines, Uri endpoint) {
  // 空行 = 一个事件结束。没有 data 行的事件（例如只有注释、只有 event: 行）不产生负载。
  if (rawLine.isEmpty) {
    if (dataLines.isEmpty) {
      return null;
    }
    final String payload = dataLines.join('\n');
    dataLines.clear();
    return payload;
  }
  // 注释行（心跳）。必须显式忽略：把它当数据会让解析器看到一个非 JSON 负载。
  if (rawLine.startsWith(':')) {
    return null;
  }
  if (!rawLine.startsWith('data:')) {
    // event: / id: / retry: 等字段：两个协议都不需要（事件类型在负载内部）。
    return null;
  }
  // 剥掉 "data:" 与其后的**一个**可选空格（规范如此；多余的空白属于负载）。
  String payload = rawLine.substring(5);
  if (payload.startsWith(' ')) {
    payload = payload.substring(1);
  }
  if (payload.length > maxSseEventBytes) {
    throw NetworkError(
      uri: endpoint.toString(),
      reason: '单个 SSE 事件超过上限 $maxSseEventBytes 字节',
    );
  }
  dataLines.add(payload);
  return null;
}

/// 解码一整行字节并剥掉行尾 CR。
///
/// allowMalformed: 服务商在流中途被截断时可能留下半个多字节字符。丢掉那半个字符远
/// 好过让整个调用以「UTF-8 解码失败」结束——后者会把一次可恢复的断流描述成一个与
/// 真实原因无关的错误。
String _decodeLine(Uint8List line) {
  final Uint8List trimmed = line.isNotEmpty && line.last == _cr
      ? Uint8List.sublistView(line, 0, line.length - 1)
      : line;
  return utf8.decode(trimmed, allowMalformed: true);
}
