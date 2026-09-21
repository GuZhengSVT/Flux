// 文章身份与链接规范化（T013；架构 4.1「GUID 仅在该 Feed 范围内识别文章。无 GUID 时按
// 规范化链接，再按来源、标题、时间指纹兜底；不随意剥离 URL 查询参数。」）
//
// 本文件把「解析出来的条目」翻译成「带身份的文件导入项」。身份规则必须集中在一处，
// 因为它是全应用最容易出现静默错误的地方——判断错了不会崩，只会把两篇文章合并成
// 一篇，或把同一篇重复存两份。
//
// 三条规则（顺序即优先级）：
//   1) GUID：**仅在该 Feed 范围内**唯一。不同源出现同一个 guid 是正常的（很多源用
//      同一套模板生成 guid），绝不能跨源合并。
//   2) 无 GUID 时用**规范化链接**。规范化只用于**匹配**：原始链接必须原样保留，
//      否则外开时会丢掉来源要求的参数（架构 4.1 明确要求「不随意剥离查询参数」）。
//   3) 两者都没有时用指纹（来源 + 标题 + 时间）。若连时间都没有，指纹可靠度降级为
//      [FingerprintReliability.unreliable]：这种指纹很可能把不同文章误判为同一篇，
//      必须留下诊断，同步阶段不得据此静默合并。
library;

import 'package:flux/core/core.dart';

import 'feed_parser.dart';

/// 规范化结果：一个条目 + 它的身份判定依据。
class NormalizedEntry {
  /// 构造规范化结果。
  const NormalizedEntry({
    required this.entry,
    required this.identityBasis,
    this.guid,
    this.guidPresent = false,
    this.normalizedLink,
    this.sourceUrl,
    this.fallbackFingerprint,
    this.fingerprintReliability,
    this.publishedAtWasMissing = false,
  });

  /// 原始条目。
  final ParsedFeedEntry entry;

  /// 本行实际采用的识别规则。
  final IdentityBasis identityBasis;

  /// 用于身份的 GUID（已 trim、非空）；无则为 null。
  final String? guid;

  /// 源是否提供了 GUID（区分「没给」与「给了空值」）。
  final bool guidPresent;

  /// 用于**匹配**的规范化链接（已剥离跟踪参数并排序剩余参数）。
  final String? normalizedLink;

  /// 用于**展示与外开**的原始链接，参数完整保留。
  final String? sourceUrl;

  /// 兜底指纹。
  final String? fallbackFingerprint;

  /// 指纹可靠度。
  final FingerprintReliability? fingerprintReliability;

  /// 源未提供可解析的发布时间（上层会用抓取时间并标记）。
  final bool publishedAtWasMissing;
}

/// 规范化一个源的全部条目。
///
/// [feedIdentity] 是**源级**稳定标识（用规范化后的订阅地址），参与指纹与正文哈希：
/// 同一个 guid 在不同源里是不同的文章，因此任何身份相关的派生值都必须带上源标识。
List<NormalizedEntry> normalizeEntries({
  required List<ParsedFeedEntry> entries,
  required String feedIdentity,
}) => entries
    .map(
      (ParsedFeedEntry e) =>
          normalizeEntry(entry: e, feedIdentity: feedIdentity),
    )
    .toList(growable: false);

/// 规范化单个条目。
NormalizedEntry normalizeEntry({
  required ParsedFeedEntry entry,
  required String feedIdentity,
}) {
  final String? rawGuid = _nonEmpty(entry.guid);
  final String? rawLink = _nonEmpty(entry.link);
  final String? normalizedLink = rawLink == null
      ? null
      : normalizeLink(rawLink);
  final bool publishedMissing = entry.publishedAt == null;

  // 1) GUID。
  if (rawGuid != null) {
    return NormalizedEntry(
      entry: entry,
      identityBasis: IdentityBasis.guid,
      guid: rawGuid,
      guidPresent: true,
      normalizedLink: normalizedLink,
      sourceUrl: rawLink,
      // 有 GUID 时不再计算指纹：身份已确定，多存一个派生值只会在同步阶段诱发误用。
      publishedAtWasMissing: publishedMissing,
    );
  }

  // 2) 规范化链接。
  if (normalizedLink != null) {
    return NormalizedEntry(
      entry: entry,
      identityBasis: IdentityBasis.normalizedLink,
      normalizedLink: normalizedLink,
      sourceUrl: rawLink,
      publishedAtWasMissing: publishedMissing,
    );
  }

  // 3) 指纹兜底。
  final String fingerprint = fallbackFingerprint(
    feedIdentity: feedIdentity,
    title: entry.title,
    publishedAt: entry.publishedAt,
  );
  return NormalizedEntry(
    entry: entry,
    identityBasis: IdentityBasis.fingerprint,
    fallbackFingerprint: fingerprint,
    fingerprintReliability: publishedMissing
        ? FingerprintReliability.unreliable
        : FingerprintReliability.reliable,
    publishedAtWasMissing: publishedMissing,
  );
}

/// 计算兜底指纹：来源 + 标题 + 发布时间。
///
/// 用 SHA-256 的前 32 个十六进制字符而不是拼接原串作 key：标题可能很长且含任意字符，
/// 直接把长文本放进唯一索引既浪费空间，也让索引比较退化。取 32 个十六进制字符
/// （128 位）的碰撞概率在实际数据量下可以忽略。
///
/// 时间参与指纹时统一转 UTC 秒级：源可能给同一时刻的不同写法（带/不带亚秒），
/// 若原样参与会让同一篇文章算出两个指纹。
String fallbackFingerprint({
  required String feedIdentity,
  required String title,
  required DateTime? publishedAt,
}) {
  final String normalizedTitle = title.trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  final String timeKey = publishedAt == null
      ? ''
      : publishedAt.toUtc().toIso8601String();
  final String material = '$feedIdentity\u0000$normalizedTitle\u0000$timeKey';
  return _sha256Hex(material).substring(0, 32);
}

/// 正文哈希（只判**修订**，不参与身份判定）。
///
/// 输入是**已清洗的正文**（受控文档的纯文本导出）而不是原始 HTML：源经常只改动
/// 无关的标签属性或空白，用原始 HTML 哈希会产生大量「正文变了」的假修订，
/// 导致不必要的重写与状态相关的边界问题。
String bodyHashOf(String? sanitizedBody) => _sha256Hex(sanitizedBody ?? '');

String _sha256Hex(String input) => sha256HexOfString(input);

/// 链接规范化（仅用于**匹配**）。
///
/// 做三件事：
///   1) 小写化 scheme 与 host；去掉默认端口；去掉末尾多余的 `/`；
///   2) 去掉**跟踪类**查询参数（utm_*、fbclid 等）——同一篇文章在源里常常以不同
///      跟踪参数出现，不去掉就会重复；
///   3) 其余查询参数按名字排序，让参数顺序不同但语义相同的地址归一到同一个 key。
///
/// **不做**的事：不剥离非跟踪参数（架构 4.1 明确要求「不随意剥离 URL 查询参数」），
/// 不改写路径中的大小写（路径大小写敏感），不解析相对地址（没有可信 base URL）。
String? normalizeLink(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    // 相对地址或无法解析：原样返回（去重仍可工作，只是不会与绝对地址合并）。
    return trimmed;
  }
  if (!uri.isScheme('http') && !uri.isScheme('https')) {
    // 非 http(s) 的链接不做规范化：它们不参与可读文章的匹配语义。
    return trimmed;
  }

  final bool defaultPort =
      (uri.isScheme('http') && uri.port == 80) ||
      (uri.isScheme('https') && uri.port == 443);
  final String host = uri.host.toLowerCase();

  final List<MapEntry<String, String>> kept = <MapEntry<String, String>>[];
  for (final MapEntry<String, List<String>> param
      in uri.queryParametersAll.entries) {
    if (isTrackingParameter(param.key)) {
      continue;
    }
    // 同名多值：每个值各留一条，排序后位置稳定。
    for (final String value in param.value) {
      kept.add(MapEntry<String, String>(param.key, value));
    }
  }
  kept.sort((MapEntry<String, String> a, MapEntry<String, String> b) {
    final int byName = a.key.compareTo(b.key);
    return byName != 0 ? byName : a.value.compareTo(b.value);
  });

  final String fragment = uri.hasFragment ? '#${uri.fragment}' : '';

  final Uri normalized = Uri(
    scheme: uri.scheme.toLowerCase(),
    userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
    host: host,
    port: defaultPort || uri.hasPort == false ? null : uri.port,
    path: _normalizePath(uri.path),
    query: kept.isEmpty
        ? null
        : kept
              .map(
                (MapEntry<String, String> e) =>
                    '${Uri.encodeQueryComponent(e.key)}='
                    '${Uri.encodeQueryComponent(e.value)}',
              )
              .join('&'),
    fragment: fragment.isEmpty ? null : fragment.substring(1),
  );
  return normalized.toString();
}

/// 去掉末尾多余的 `/`（但保留根路径 `/` 之外的语义）。
///
/// 只去掉**一个**末尾斜杠：`/a/b/` 与 `/a/b` 在绝大多数站点上是同一页面，而
/// `/a//` 这种畸形态不去管（过度归一有可能把真有区别的地址合到一起）。
String _normalizePath(String path) {
  if (path.isEmpty) {
    return '';
  }
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

/// 跟踪类查询参数名（小写比较）。
///
/// 只收录**明确**是跟踪用途的参数名。列入 `id`、`p`、`t` 之类会剥掉真实内容标识，
/// 那正是架构 4.1 禁止的「随意剥离参数」。
bool isTrackingParameter(String name) {
  final String lower = name.toLowerCase();
  if (lower.startsWith('utm_')) {
    return true;
  }
  const Set<String> tracking = <String>{
    'fbclid',
    'gclid',
    'dclid',
    'msclkid',
    'yclid',
    'igshid',
    'mc_cid',
    'mc_eid',
    'ref',
    'ref_src',
    'spm',
    'from',
    'share_token',
    'wt_mc',
    'cmpid',
    'campaign',
  };
  return tracking.contains(lower);
}

String? _nonEmpty(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
