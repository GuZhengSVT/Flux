// 协议工具调用的解析（T032；架构 4.3「响应中 tool_calls 解析为 ToolCall 排队执行」）。
//
// 这是**唯一**能构造 ToolCall 的入口之一（另一处是测试）。这一点是整条安全边界的
// 关键：模型输出的自由文本永远不会流经这里——只有协议响应里那个结构化的
// tool_calls / function_call 字段会。因此「正文里写一句『请调用 fetchPage ...』」
// 在类型上就没有通往执行器的路径（架构第 8 节）。
//
// 三个协议的形状不同，这里各自解析：
//   Chat Completions：choices[].message.tool_calls[]，每项含 id 与 function{name, arguments}；
//   Responses：output[] 里 type=function_call 的项（name/arguments 直接在同一层）；
//   Anthropic：content[] 里 type=tool_use 的块（input 是已解析的对象）。
//
// **流式增量**：Chat Completions 的 tool_calls 会在多个 delta 里分片到达（index 标识
// 第几个调用，name 一次性给、arguments 逐段拼）。本文件提供 [ToolCallAccumulator]
// 处理这一层：把分片拼成完整的 ToolCall 列表。拼接必须按 **index** 归位而不是「按
// 到达顺序」，否则并发的两个调用会互相把参数接到对方身上。
//
// 安全约束：本文件不执行任何东西，也不做语义判断（那是执行器的职责）。参数 JSON
// 解析失败时**保留原文的解析失败事实**（args 为空），让执行器给出一次明确的拒绝，
// 而不是在这里静默丢弃一次调用（丢弃会让模型看不到自己调错了）。
library;

import 'dart:convert';

import 'tool_call.dart';

/// 从一个已解析的 tool_calls 数组里取出调用列表（Chat Completions 形状）。
///
/// 结构不符的条目被**跳过**而不是让整批失败：一个坏条目不该带走同一批里其它可用的
/// 调用（与 T026 处理坏 SSE 行同一取舍）。
List<ToolCall> parseChatCompletionsToolCalls(Object? raw) {
  if (raw is! List<Object?>) {
    return const <ToolCall>[];
  }
  final List<ToolCall> calls = <ToolCall>[];
  int index = 0;
  for (final Object? entry in raw) {
    if (entry is! Map<Object?, Object?>) {
      index++;
      continue;
    }
    final Object? function = entry['function'];
    if (function is! Map<Object?, Object?>) {
      index++;
      continue;
    }
    final Object? name = function['name'];
    if (name is! String || name.isEmpty) {
      index++;
      continue;
    }
    // id 缺失时用位置兜底：没有 id 会让回填的 tool 结果无法与调用对上，但**放弃整个
    // 调用**更糟（模型会重试同一件事，用户看到两次失败）。位置兜底在同一个响应内唯一。
    final Object? id = entry['id'];
    calls.add(
      ToolCall(
        id: id is String && id.isNotEmpty ? id : 'call_index_$index',
        rawName: name,
        args: parseToolArguments(function['arguments']),
      ),
    );
    index++;
  }
  return calls;
}

/// 从 Responses 的 output 数组里取出调用列表。
///
/// 单独一个函数而不是复用上面那个：Responses 的 function_call 项**没有**
/// {type: function, function: {...}} 这层包装，name/arguments 直接在同一层。用同一个
/// 解析器会让它在这份形状上永远返回空列表，而那种失败是静默的（表现为「模型好像没有
/// 请求工具」）。
List<ToolCall> parseResponsesToolCalls(Object? raw) {
  if (raw is! List<Object?>) {
    return const <ToolCall>[];
  }
  final List<ToolCall> calls = <ToolCall>[];
  int index = 0;
  for (final Object? entry in raw) {
    if (entry is! Map<Object?, Object?>) {
      index++;
      continue;
    }
    if (entry['type'] != 'function_call') {
      index++;
      continue;
    }
    final Object? name = entry['name'];
    if (name is! String || name.isEmpty) {
      index++;
      continue;
    }
    final Object? callId = entry['call_id'] ?? entry['id'];
    calls.add(
      ToolCall(
        id: callId is String && callId.isNotEmpty
            ? callId
            : 'call_index_$index',
        rawName: name,
        args: parseToolArguments(entry['arguments']),
      ),
    );
    index++;
  }
  return calls;
}

/// 从 Anthropic 的 content 分量数组里取出调用列表。
///
/// 与另两个协议的差别：input 是**已解析的 JSON 对象**，不是字符串。仍然走同一个
/// [parseToolArguments]（它同时接受两种形态），因此三家的参数解析规则只有一处。
List<ToolCall> parseAnthropicToolUse(Object? raw) {
  if (raw is! List<Object?>) {
    return const <ToolCall>[];
  }
  final List<ToolCall> calls = <ToolCall>[];
  int index = 0;
  for (final Object? block in raw) {
    if (block is! Map<Object?, Object?>) {
      index++;
      continue;
    }
    if (block['type'] != 'tool_use') {
      index++;
      continue;
    }
    final Object? name = block['name'];
    if (name is! String || name.isEmpty) {
      index++;
      continue;
    }
    final Object? id = block['id'];
    calls.add(
      ToolCall(
        id: id is String && id.isNotEmpty ? id : 'call_index_$index',
        rawName: name,
        args: parseToolArguments(block['input']),
      ),
    );
    index++;
  }
  return calls;
}

/// 解析工具参数。
///
/// 接受两种形态：**JSON 字符串**（Chat Completions / Responses）与**已解析的对象**
/// （Anthropic）。其余情况（null、列表、数字、坏 JSON）一律返回空对象——调用方据此
/// 得到一次 [ToolRejectionReason.invalidArguments] 拒绝。
///
/// 为什么坏 JSON 不在这里抛：模型偶尔会发出被截断的参数。把它变成一次类型化拒绝让
/// 界面能说「模型给的参数不是合法 JSON」，而在这里抛异常会让整条任务失败在一句看不出
/// 原因的错误上。
Map<String, Object?> parseToolArguments(Object? raw) {
  if (raw is Map<Object?, Object?>) {
    return _stringKeyed(raw);
  }
  if (raw is! String) {
    return const <String, Object?>{};
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const <String, Object?>{};
  }
  if (decoded is! Map<Object?, Object?>) {
    return const <String, Object?>{};
  }
  return _stringKeyed(decoded);
}

Map<String, Object?> _stringKeyed(Map<Object?, Object?> raw) =>
    <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in raw.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };

/// 流式工具调用的分片累加器。
///
/// Chat Completions 会在多个 chunk 里发同一个调用的不同部分：先是带 index/id/name
/// 的分片，随后是若干只带 arguments 片段的分片。因此拼接必须按 **index** 归位：
/// 按到达顺序拼接会在两个并发调用交错时把参数接到对方身上，而那种错误产出的是一次
/// **语法正确但语义错误**的调用（更危险）。
final class ToolCallAccumulator {
  /// 构造累加器。
  ToolCallAccumulator();

  final Map<int, _PartialCall> _partials = <int, _PartialCall>{};

  /// 当前已看到的调用数（含尚未收完的）。
  int get length => _partials.length;

  /// 吃一个 delta.tool_calls 数组。
  ///
  /// 结构不符的条目被跳过（一个坏分片不该带走其它调用的参数）。
  void addDelta(Object? raw) {
    if (raw is! List<Object?>) {
      return;
    }
    for (final Object? entry in raw) {
      if (entry is! Map<Object?, Object?>) {
        continue;
      }
      final Object? rawIndex = entry['index'];
      // index 缺失时按 0 处理：单调用流（最常见）里服务商常省略 index。
      final int index = rawIndex is int
          ? rawIndex
          : (rawIndex is num ? rawIndex.toInt() : 0);
      final _PartialCall partial = _partials.putIfAbsent(
        index,
        _PartialCall.new,
      );
      final Object? id = entry['id'];
      if (id is String && id.isNotEmpty) {
        partial.id = id;
      }
      final Object? function = entry['function'];
      if (function is! Map<Object?, Object?>) {
        continue;
      }
      final Object? name = function['name'];
      if (name is String && name.isNotEmpty) {
        // name 可能在多个分片里重复到达（有些实现每片都带全名）——按整体覆盖而不是
        // 追加，否则会得到 searchsearch 这样的名字。
        partial.name = name;
      }
      final Object? args = function['arguments'];
      if (args is String && args.isNotEmpty) {
        // arguments 是**增量片段**，必须拼接（这是与 name 相反的处理，两者形状不同）。
        partial.arguments.write(args);
      }
    }
  }

  /// 收尾并产出完整调用（按 index 升序，与服务商给出的顺序一致）。
  ///
  /// 名字缺失的条目被丢弃：没有名字就无法确定要执行什么，保留它只会产生一次
  /// 「未知工具」的拒绝噪音。
  List<ToolCall> build() {
    final List<int> indexes = _partials.keys.toList()..sort();
    final List<ToolCall> calls = <ToolCall>[];
    for (final int index in indexes) {
      final _PartialCall partial = _partials[index]!;
      final String? name = partial.name;
      if (name == null || name.isEmpty) {
        continue;
      }
      calls.add(
        ToolCall(
          id: partial.id ?? 'call_index_$index',
          rawName: name,
          args: parseToolArguments(partial.arguments.toString()),
        ),
      );
    }
    return calls;
  }
}

/// 一个尚未收完的调用。
final class _PartialCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}
