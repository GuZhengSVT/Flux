// 工具参数校验与图片材料集合（T032；架构 4.3、SET-061/062）。
//
// 为什么把校验做成**纯函数**而不是散在执行器里：
//   1) 每个拒绝分支都必须能被逐条断言（尤其是「fetchPage 指向 169.254.169.254」这类
//      攻击面）——把它们藏在 IO 之后，测试就得先制造一次真实请求才能触达；
//   2) 「参数校验」与「网络目的地校验」是两件事：前者看字符串形态，后者看地址含义。
//      混在一起会让「一个格式合法但指向内网的地址」在参数层被放过。
//
// 本文件是纯 Dart（不联网、无 IO），只依赖 core 的地址守卫与 features/ai 的领域类型。
library;

import 'package:flux/core/core.dart';

import 'search_service.dart';
import 'tool_call.dart';

/// 参数校验结果（成功时带回解析出的值）。
///
/// 用密封类而不是「返回 null」：拒绝时**必须**带上原因与参数名，否则界面只能显示
/// 「工具调用失败」，而用户看不出是模型编的参数还是我们拦下的安全问题。
sealed class ToolArgumentCheck<T> {
  const ToolArgumentCheck();
}

/// 通过。
final class ToolArgumentsOk<T> extends ToolArgumentCheck<T> {
  /// 构造通过结果。
  const ToolArgumentsOk(this.value);

  /// 解析出的值。
  final T value;
}

/// 拒绝。
final class ToolArgumentsRejected<T> extends ToolArgumentCheck<T> {
  /// 构造拒绝结果。
  const ToolArgumentsRejected({required this.reason, required this.detail});

  /// 拒绝原因。
  final ToolRejectionReason reason;

  /// 结构性说明（**不含**参数值本身：参数可能含用户查询词或页面地址）。
  final String detail;
}

/// search 的参数。
final class SearchToolArgs {
  /// 构造参数。
  const SearchToolArgs({required this.query, required this.count});

  /// 查询词。
  final String query;

  /// 期望条数。
  final int count;
}

/// 校验 search 的参数。
///
/// 规则与 toolDeclarations 里发给模型的 schema 逐条对应（不一致的后果见该函数的说明）：
///   - query 必填、非空、长度上限 kSearchQueryMaxLength；
///   - count 可选，缺省用 defaultCount；给了就必须是不越界的**整数**。
///     不做「字符串转整数」的宽容处理：模型发错类型说明它没按 schema 走，猜它的意图
///     会把一次接口错误变成一次真实计费调用。
ToolArgumentCheck<SearchToolArgs> checkSearchArguments(
  Map<String, Object?> args, {
  required int defaultCount,
}) {
  final Object? rawQuery = args['query'];
  if (rawQuery == null) {
    return const ToolArgumentsRejected<SearchToolArgs>(
      reason: ToolRejectionReason.invalidArguments,
      detail: '缺少 query',
    );
  }
  if (rawQuery is! String) {
    return const ToolArgumentsRejected<SearchToolArgs>(
      reason: ToolRejectionReason.invalidArguments,
      detail: 'query 必须是字符串',
    );
  }
  // 查询词校验复用 T031 的那一份（同一个取值域只应有一处判据）。
  final Result<void> validQuery = validateSearchQueryText(rawQuery);
  if (validQuery.isErr) {
    return ToolArgumentsRejected<SearchToolArgs>(
      reason: ToolRejectionReason.invalidArguments,
      detail: validQuery.errorOrNull is ValidationError
          ? (validQuery.errorOrNull! as ValidationError).reason
          : 'query 不合法',
    );
  }

  final Object? rawCount = args['count'];
  int count = defaultCount;
  if (rawCount != null) {
    if (rawCount is! int) {
      return const ToolArgumentsRejected<SearchToolArgs>(
        reason: ToolRejectionReason.invalidArguments,
        detail: 'count 必须是整数',
      );
    }
    if (rawCount < kSearchMinResults || rawCount > kSearchMaxResults) {
      // 超界**拒绝**而不是夹紧：夹紧会让模型以为它要的 999 条拿到了，而实际只拿到 20
      // 条——一次被静默裁剪的结果集与一次真实的 20 条结果看起来完全一样。
      return const ToolArgumentsRejected<SearchToolArgs>(
        reason: ToolRejectionReason.invalidArguments,
        detail: 'count 必须在 kSearchMinResults–kSearchMaxResults 之间',
      );
    }
    count = rawCount;
  }
  return ToolArgumentsOk<SearchToolArgs>(
    SearchToolArgs(query: rawQuery.trim(), count: count),
  );
}

/// fetchPage 的参数。
final class FetchPageToolArgs {
  /// 构造参数。
  const FetchPageToolArgs({required this.uri});

  /// 已通过守卫的地址。
  final Uri uri;
}

/// 网页地址的长度上限。
///
/// 为什么要有：一个几十 KB 的「地址」要么是注入尝试（把内容塞进一个会被服务端记录的
/// 字段），要么是模型把整段 HTML 当成了 URL。真实网页地址极少超过 2000 字符。
const int kFetchPageMaxUrlLength = 2000;

/// 校验 fetchPage 的参数（含**地址含义**校验）。
///
/// 这是本任务的核心安全断言之一：模型输出的 http://169.254.169.254/ 必须在这里被
/// 拒绝，而不是等请求发出去才由网络层报错。判据复用 core 的 checkUrlGuarded
/// （embeddedContent 策略），因此「哪些地址危险」只有一份定义（T021/T024 已用它拦
/// 正文图片与源站地址）。
ToolArgumentCheck<FetchPageToolArgs> checkFetchPageArguments(
  Map<String, Object?> args,
) {
  final Object? rawUrl = args['url'];
  if (rawUrl == null) {
    return const ToolArgumentsRejected<FetchPageToolArgs>(
      reason: ToolRejectionReason.invalidArguments,
      detail: '缺少 url',
    );
  }
  if (rawUrl is! String) {
    return const ToolArgumentsRejected<FetchPageToolArgs>(
      reason: ToolRejectionReason.invalidArguments,
      detail: 'url 必须是字符串',
    );
  }
  final String trimmed = rawUrl.trim();
  if (trimmed.isEmpty) {
    return const ToolArgumentsRejected<FetchPageToolArgs>(
      reason: ToolRejectionReason.invalidArguments,
      detail: 'url 不能为空',
    );
  }
  if (trimmed.length > kFetchPageMaxUrlLength) {
    return const ToolArgumentsRejected<FetchPageToolArgs>(
      reason: ToolRejectionReason.invalidArguments,
      detail: 'url 过长（上限 kFetchPageMaxUrlLength）',
    );
  }
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return const ToolArgumentsRejected<FetchPageToolArgs>(
      reason: ToolRejectionReason.invalidArguments,
      detail: 'url 不是合法地址',
    );
  }
  final UrlGuardResult guard = checkUrlGuarded(
    uri,
    UrlGuardPolicy.embeddedContent,
  );
  if (!guard.allowed) {
    // 协议与目的地分开报：前者是模型给了个不可能的东西（file://、data:），
    // 后者是**安全事件**（试图访问本机或内网），两者的日志级别与后续处理不同。
    return ToolArgumentsRejected<FetchPageToolArgs>(
      reason: guard.failure == UrlGuardFailure.scheme
          ? ToolRejectionReason.forbiddenScheme
          : ToolRejectionReason.forbiddenDestination,
      detail: guard.detail ?? '地址被拒绝',
    );
  }
  return ToolArgumentsOk<FetchPageToolArgs>(FetchPageToolArgs(uri: uri));
}

/// inspectImage 的参数。
final class InspectImageToolArgs {
  /// 构造参数。
  const InspectImageToolArgs({required this.imageRef});

  /// 客户端给出的图片引用。
  final String imageRef;
}

/// 图片引用长度上限。
const int kImageRefMaxLength = 256;

/// 校验 inspectImage 的参数（**只做形态校验**）。
///
/// 「这个引用是不是客户端真的给过的材料」必须由调用方用 ImageMaterialRegistry 判定：
/// 那是一个跨调用的状态，不属于纯函数。这里只保证它是个非空、长度合理的字符串，并
/// 挡掉「模型把 URL 当引用传」这一种最常见的误用。
ToolArgumentCheck<InspectImageToolArgs> checkInspectImageArguments(
  Map<String, Object?> args,
) {
  final Object? rawRef = args['imageRef'];
  if (rawRef == null) {
    return const ToolArgumentsRejected<InspectImageToolArgs>(
      reason: ToolRejectionReason.invalidArguments,
      detail: '缺少 imageRef',
    );
  }
  if (rawRef is! String) {
    return const ToolArgumentsRejected<InspectImageToolArgs>(
      reason: ToolRejectionReason.invalidArguments,
      detail: 'imageRef 必须是字符串',
    );
  }
  final String trimmed = rawRef.trim();
  if (trimmed.isEmpty) {
    return const ToolArgumentsRejected<InspectImageToolArgs>(
      reason: ToolRejectionReason.invalidArguments,
      detail: 'imageRef 不能为空',
    );
  }
  if (trimmed.length > kImageRefMaxLength) {
    return const ToolArgumentsRejected<InspectImageToolArgs>(
      reason: ToolRejectionReason.invalidArguments,
      detail: 'imageRef 过长（上限 kImageRefMaxLength）',
    );
  }
  // 明确挡掉「模型直接把 URL 当 imageRef 传」：即使这个地址恰好也在材料集合里，也不该
  // 通过「看起来像地址」的写法进入——引用的形态是客户端给的短标识，不是地址
  // （架构 4.3「不能传任意 URL」）。
  final Uri? asUri = Uri.tryParse(trimmed);
  if (asUri != null && asUri.hasScheme && asUri.host.isNotEmpty) {
    return const ToolArgumentsRejected<InspectImageToolArgs>(
      reason: ToolRejectionReason.unknownImageReference,
      detail: 'imageRef 必须是材料引用而不是地址',
    );
  }
  return ToolArgumentsOk<InspectImageToolArgs>(
    InspectImageToolArgs(imageRef: trimmed),
  );
}

/// 一条已注册的图片材料。
final class ImageMaterial {
  /// 构造材料。
  const ImageMaterial({
    required this.ref,
    required this.sourceUrl,
    required this.origin,
  });

  /// 客户端给出的引用（模型用它请求查看）。
  final String ref;

  /// 原始地址（**只用于加载**，不交给模型）。
  final String sourceUrl;

  /// 来源（search / fetchPage），用于诊断与「这张图是从哪来的」。
  final String origin;

  @override
  String toString() => 'ImageMaterial($ref, origin=$origin)';
}

/// 本次任务里客户端**给过模型的**图片材料集合。
///
/// 这是 inspectImage 的全部合法输入来源。为什么必须是一个显式集合而不是「按需抓取
/// 任意地址」：架构 4.3 明确「不允许任意 URL」。有了这个集合之后，
///   - 模型只能查看它已经见过的图（它引用的名字来自我们回填的材料清单）；
///   - 一次 prompt 注入**无法**让执行器去下载一个攻击者选的地址，因为那个地址从
///     来没有进入过这个集合，而集合只能由客户端在检索/抓取流程里添加。
final class ImageMaterialRegistry {
  /// 构造空集合。
  ImageMaterialRegistry();

  final Map<String, ImageMaterial> _byRef = <String, ImageMaterial>{};

  /// 已注册的材料数。
  int get length => _byRef.length;

  /// 全部材料（按注册顺序，供回填材料清单）。
  Iterable<ImageMaterial> get materials => _byRef.values;

  /// 注册一张图片；返回客户端生成的引用。
  ///
  /// 引用是**顺序号 + 来源前缀**（img-fetchPage-1），而不是地址的哈希：模型看到的名字
  /// 不该泄漏地址内容，也不该让攻击者通过「猜一个地址的哈希」来探测这张图是否在
  /// 材料集合里（哈希可猜，顺序号不可猜）。同一地址重复注册返回同一个引用。
  String register({required String sourceUrl, required String origin}) {
    for (final ImageMaterial existing in _byRef.values) {
      if (existing.sourceUrl == sourceUrl && existing.origin == origin) {
        return existing.ref;
      }
    }
    final String ref = 'img-$origin-${_byRef.length + 1}';
    _byRef[ref] = ImageMaterial(ref: ref, sourceUrl: sourceUrl, origin: origin);
    return ref;
  }

  /// 按引用取材料；未知引用返回 null。
  ImageMaterial? lookup(String ref) => _byRef[ref];
}
