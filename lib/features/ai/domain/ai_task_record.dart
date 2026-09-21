// AI 任务的持久记录、输入快照与结果缓存键（T030；架构 4.5、5.1、D-09）。
//
// 这一层刻意只描述**事实**，不做 IO：
//   - [AiTaskRecord] 是一次任务在某一刻的完整可持久化形态（状态九态、deadline、累计
//     消耗、结果、错误类别）；
//   - [AiInputSnapshot] 是「这次任务到底发出去什么」的规范化快照（消息、模型与参数），
//     它的哈希是缓存键与「输入变了」判断的唯一依据；
//   - [AiResultCacheKey] 把「任务类型 + 输入哈希 + 模型 + 语言 + 参数」合成一个缓存键。
//
// 两条关键语义（架构 4.5「缓存键包括任务类型、输入哈希/版本、目标语言、模板版本、
// 模型和参数」）：
//   1) **缓存键里的任何一项变化都是另一次缓存**。不做「部分匹配」也不做「相似就复用」：
//      一个把语言从中文改成英文的请求命中中文缓存，用户会看到一份语言不对的结果，
//      而界面上没有任何线索指向缓存；
//   2) **失败不写缓存**。只有通过校验的成功结果才进缓存，否则一次网络抖动会把「失败」
//      固化成之后所有同输入任务的结果。
library;

import 'package:flux/core/core.dart';

import 'ai_message.dart';

/// AI 任务的类型（缓存键的一部分，架构 4.5）。
///
/// 用稳定字符串落库（见 [AiTaskKind.id]），不用枚举序号：序号在枚举中间插一项之后
/// 会让历史行的含义整体漂移。
enum AiTaskKind {
  /// 每日总结（T036–T040）。
  summary(id: 'summary'),

  /// 选词解释（T034）。
  explain(id: 'explain'),

  /// 全文翻译（T035）。
  translate(id: 'translate'),

  /// 今日新闻初稿（T037）。
  news(id: 'news'),

  /// 其它一次性任务（诊断、连接测试等）。
  other(id: 'other');

  const AiTaskKind({required this.id});

  /// 落库与缓存键使用的稳定标识。
  final String id;

  /// 由稳定标识还原；未知标识返回 null（调用方据此报校验错误，而不是猜一个）。
  static AiTaskKind? fromId(String? id) {
    for (final AiTaskKind kind in AiTaskKind.values) {
      if (kind.id == id) {
        return kind;
      }
    }
    return null;
  }
}

/// 一次任务的输入快照（规范化后）。
///
/// 为什么要显式存快照而不是「从请求对象现算」：任务落库之后请求对象就不再存在
/// （进程重启只恢复记录），而「当时发的是什么」是排查与缓存判定都需要的**历史事实**。
final class AiInputSnapshot {
  /// 构造快照。
  const AiInputSnapshot({
    required this.messages,
    required this.modelId,
    this.language,
    this.temperature,
    this.maxTokens,
    this.imageCount = 0,
  });

  /// 从一次请求构造快照。
  factory AiInputSnapshot.fromRequest(AiRequest request, {String? language}) =>
      AiInputSnapshot(
        messages: request.messages,
        modelId: request.modelId,
        language: language,
        temperature: request.temperature,
        maxTokens: request.maxTokens,
        imageCount: request.messages.fold(
          0,
          (int sum, AiMessage m) => sum + m.images.length,
        ),
      );

  /// 消息序列（顺序即上下文顺序）。
  final List<AiMessage> messages;

  /// 服务商侧模型 ID。
  final String modelId;

  /// 目标语言（SET-011 的内容语言）；与任务类型一起决定缓存是否可复用。
  final String? language;

  /// 采样温度。
  final double? temperature;

  /// 输出上限。
  final int? maxTokens;

  /// 输入里的图片数量（T033）。
  ///
  /// **单独落一列字段而不是从 messages 现算**：图片的字节不落库（见 [toJson]），因此
  /// 从库里读回来的快照的 messages 里没有任何图片，「这次任务带过图」这个事实只能靠
  /// 一个显式的数字保留下来。没有它，「重新开始」会把一次带图任务静默当成纯文本任务
  /// 重放——那等于用另一份输入去请求，而用户看到的是一个「重新开始」按钮。
  final int imageCount;

  /// 输入里是否包含图片。
  bool get hasImages => imageCount > 0;

  /// 输入侧正文的规范化拼接（用于哈希与 Token 估算）。
  ///
  /// 用角色名与长度前缀做分隔，避免「两条消息拼接后与另一组消息撞成同一串」这类
  /// 边界歧义：把 AB + C 与 A + BC 区分开。
  ///
  /// **图片的内容摘要也进这里**（T033）：一次带图的请求与一次不带图的请求必须是两个
  /// 缓存键。用**内容摘要**而不是地址或字节：地址会变而图不变（不该让缓存失效），
  /// 字节会把整张图写进哈希输入与落库 JSON（几十 MiB 的文本列）。
  String get canonicalText {
    final StringBuffer buffer = StringBuffer();
    for (final AiMessage message in messages) {
      buffer
        ..write(message.role.wireName)
        ..write(':')
        ..write(message.content.length)
        ..write(':')
        ..write(message.content)
        ..write('\u0000');
      for (final AiImagePart image in message.images) {
        buffer
          ..write('img:')
          ..write(image.mimeType)
          ..write(':')
          ..write(image.digest)
          ..write('\u0000');
      }
    }
    return buffer.toString();
  }

  /// 提示内容的哈希（输入变化的唯一判据）。
  ///
  /// 用工程自实现的 SHA-256（T013，无第三方依赖）；不用 String.hashCode——
  /// 它跨进程不稳定，会让重启后的缓存判定给出不同答案。
  String get promptHash => sha256HexOfString(canonicalText);

  /// 落库形态（JSON）。
  ///
  /// 图片**只落摘要，不落字节**：快照是「当时发出去什么」的记录，而一张 4 MiB 的图
  /// 写进这一列会让任务表被图片撑大，也会把用户的图片内容复制进明文备份与同步包
  /// （架构第 8 节）。摘要足以回答「这次任务带了图吗、图变了吗」，而重放带图任务由
  /// [hasImages] 明确拦住。
  Map<String, Object?> toJson() => <String, Object?>{
    'modelId': modelId,
    if (language != null) 'language': language,
    if (temperature != null) 'temperature': temperature,
    if (maxTokens != null) 'maxTokens': maxTokens,
    if (imageCount > 0) 'imageCount': imageCount,
    'messages': <Object?>[
      for (final AiMessage message in messages)
        <String, Object?>{
          'role': message.role.wireName,
          'content': message.content,
          if (message.images.isNotEmpty)
            'imageDigests': <Object?>[
              for (final AiImagePart image in message.images)
                <String, Object?>{
                  'mimeType': image.mimeType,
                  'digest': image.digest,
                  'width': image.width,
                  'height': image.height,
                  'downsampled': image.downsampled,
                  'byteLength': image.byteLength,
                },
            ],
        },
    ],
  };

  /// 从落库形态还原；结构不符时返回 null（调用方按「快照损坏」处理，不猜内容）。
  static AiInputSnapshot? fromJson(Map<String, Object?> json) {
    final Object? rawMessages = json['messages'];
    if (rawMessages is! List<Object?>) {
      return null;
    }
    final List<AiMessage> messages = <AiMessage>[];
    for (final Object? item in rawMessages) {
      if (item is! Map<Object?, Object?>) {
        return null;
      }
      final Object? role = item['role'];
      final Object? content = item['content'];
      if (role is! String || content is! String) {
        return null;
      }
      final AiRole? parsed = _roleFrom(role);
      if (parsed == null) {
        return null;
      }
      messages.add(AiMessage(role: parsed, content: content));
    }
    final Object? modelId = json['modelId'];
    if (modelId is! String) {
      return null;
    }
    final Object? temperature = json['temperature'];
    final Object? maxTokens = json['maxTokens'];
    final Object? language = json['language'];
    // 图片数量只在库里那一份里有（字节与摘要都不还原）：这不影响「这次任务带过图吗」
    // 这个判断，而它对「重新开始」是必需的（见 [imageCount] 的说明）。
    final Object? imageCount = json['imageCount'];
    return AiInputSnapshot(
      messages: messages,
      modelId: modelId,
      language: language is String ? language : null,
      temperature: temperature is num ? temperature.toDouble() : null,
      maxTokens: maxTokens is int ? maxTokens : null,
      imageCount: imageCount is int && imageCount > 0 ? imageCount : 0,
    );
  }

  static AiRole? _roleFrom(String wireName) {
    for (final AiRole role in AiRole.values) {
      if (role.wireName == wireName) {
        return role;
      }
    }
    return null;
  }
}

/// 结果缓存的键（架构 4.5）。
///
/// 组成项全部是「会影响产出内容」的事实。任何一项变化都会得到另一个键，因此
/// 「输入/模型/语言任一变化即失效」是**结构性**的，不依赖任何调用点记得清缓存。
final class AiResultCacheKey {
  /// 构造缓存键。
  const AiResultCacheKey({
    required this.kind,
    required this.promptHash,
    required this.modelId,
    this.language,
    this.temperature,
    this.maxTokens,
    this.digest,
  });

  /// 从任务类型、快照与路由结果计算缓存键。
  ///
  /// [routeModelIds] 是这次任务**实际会依序尝试**的模型 ID 列表：把整条候选链纳入键，
  /// 因此「换了故障转移顺序」或「换了主用模型」都会得到新键——一份由 A 模型产出的
  /// 结果不应当被当成「用 B 模型配置」的答案复用。
  factory AiResultCacheKey.of({
    required AiTaskKind kind,
    required AiInputSnapshot snapshot,
    required List<String> routeModelIds,
  }) {
    final Map<String, Object?> canonical = <String, Object?>{
      'kind': kind.id,
      'promptHash': snapshot.promptHash,
      'route': routeModelIds,
      'language': snapshot.language,
      'temperature': snapshot.temperature,
      'maxTokens': snapshot.maxTokens,
    };
    return AiResultCacheKey(
      kind: kind,
      promptHash: snapshot.promptHash,
      modelId: routeModelIds.join(','),
      language: snapshot.language,
      temperature: snapshot.temperature,
      maxTokens: snapshot.maxTokens,
      digest: sha256HexOfString(_canonicalJson(canonical)),
    );
  }

  /// 任务类型。
  final AiTaskKind kind;

  /// 输入提示哈希。
  final String promptHash;

  /// 参与路由的模型 ID（多个时以逗号连接，已含顺序）。
  final String modelId;

  /// 目标语言。
  final String? language;

  /// 采样温度。
  final double? temperature;

  /// 输出上限。
  final int? maxTokens;

  /// 全部组成的摘要（落库主键）。
  final String? digest;

  /// 稳定键文本。
  String get value => digest ?? '${kind.id}|$promptHash|$modelId|$language';

  /// 把键的组成部分拼成确定性字符串（键序固定，避免同一逻辑键算出两个哈希）。
  static String _canonicalJson(Map<String, Object?> canonical) {
    final List<String> keys = canonical.keys.toList()..sort();
    final StringBuffer buffer = StringBuffer('{');
    for (final String key in keys) {
      buffer
        ..write(key)
        ..write('=')
        ..write(canonical[key] ?? '')
        ..write(';');
    }
    return (buffer..write('}')).toString();
  }
}

/// 一条结果缓存记录。
final class AiResultCacheEntry {
  /// 构造记录。
  const AiResultCacheEntry({
    required this.key,
    required this.text,
    required this.providerAlias,
    required this.modelId,
    required this.createdAt,
  });

  /// 缓存键。
  final String key;

  /// 成功产出的文本。
  final String text;

  /// 产出它的提供商别名。
  final String providerAlias;

  /// 产出它的模型 ID。
  final String modelId;

  /// 写入时刻（UTC）。
  final DateTime createdAt;
}

/// 一次任务的持久记录（架构 5.1 的 AITask / Attempt / Result）。
final class AiTaskRecord {
  /// 构造记录。
  const AiTaskRecord({
    required this.taskId,
    required this.kind,
    required this.snapshot,
    required this.modelAliases,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.deadline,
    this.consumedTokens = 0,
    this.attemptCount = 0,
    this.resultText,
    this.finishReason,
    this.errorKind,
    this.providerAlias,
    this.cacheKey,
    this.fromCache = false,
  });

  /// 任务标识（本机唯一）。
  final String taskId;

  /// 任务类型。
  final AiTaskKind kind;

  /// 输入快照（当时实际发出去的内容）。
  final AiInputSnapshot snapshot;

  /// 参与故障转移的模型别名（按顺序）。
  final List<String> modelAliases;

  /// 状态九态。
  final TaskStatus status;

  /// 创建时刻（UTC）。
  final DateTime createdAt;

  /// 最后更新时刻（UTC）。
  final DateTime updatedAt;

  /// 任务总时限的绝对时刻；一旦设定不重置（SET-059）。
  final DateTime? deadline;

  /// 累计消耗 token。
  final int consumedTokens;

  /// 已发生的 HTTP 尝试次数。
  final int attemptCount;

  /// 成功（或部分成功）的产出文本。
  final String? resultText;

  /// 服务商给出的结束原因。
  final String? finishReason;

  /// 失败错误的类别（AppError.kind），不存错误正文。
  final String? errorKind;

  /// 产出该结果的提供商别名。
  final String? providerAlias;

  /// 命中/写入的缓存键。
  final String? cacheKey;

  /// 本次结果是否直接来自缓存（未发请求）。
  final bool fromCache;

  /// 是否为成功或部分成功（终态里「有产出」的两态）。
  bool get hasResult =>
      (status == TaskStatus.succeeded || status == TaskStatus.partial) &&
      resultText != null &&
      resultText!.isNotEmpty;

  /// 是否为中断留下的记录（进程被终止/崩溃）。
  bool get isInterrupted => status == TaskStatus.interrupted;

  /// 复制并覆盖部分字段。
  AiTaskRecord copyWith({
    TaskStatus? status,
    DateTime? updatedAt,
    DateTime? deadline,
    int? consumedTokens,
    int? attemptCount,
    String? resultText,
    String? finishReason,
    String? errorKind,
    String? providerAlias,
    String? cacheKey,
    bool? fromCache,
  }) => AiTaskRecord(
    taskId: taskId,
    kind: kind,
    snapshot: snapshot,
    modelAliases: modelAliases,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deadline: deadline ?? this.deadline,
    consumedTokens: consumedTokens ?? this.consumedTokens,
    attemptCount: attemptCount ?? this.attemptCount,
    resultText: resultText ?? this.resultText,
    finishReason: finishReason ?? this.finishReason,
    errorKind: errorKind ?? this.errorKind,
    providerAlias: providerAlias ?? this.providerAlias,
    cacheKey: cacheKey ?? this.cacheKey,
    fromCache: fromCache ?? this.fromCache,
  );

  @override
  String toString() =>
      'AiTaskRecord($taskId, kind=${kind.id}, ${status.name}, '
      'tokens=$consumedTokens, attempts=$attemptCount, fromCache=$fromCache)';
}
