// 出网地址守卫（T021；架构 4.2 图片安全与第 8 节「不得把请求打到内网」）。
//
// 存在的理由：**第三方内容里的地址不是我们的地址**。订阅源是用户自己配置的
// （他可能确实在局域网里跑了一个 RSS 服务），而文章正文里的图片地址是**远端页面
// 控制的**——一个被投毒的源可以塞进 http://127.0.0.1:8080/... 或
// http://169.254.169.254/latest/meta-data/，让阅读器替攻击者去访问内网服务。
// 这就是 SSRF（服务端请求伪造）在客户端的形态：目标不是我们的服务器，而是用户
// 所在的那张网。
//
// 因此守卫分两档，由调用方按「这个地址是谁给的」选择：
//   - [UrlGuardPolicy.configuredSource]：用户显式配置的地址（订阅源）。允许私网与
//     回环——用户想订阅自己内网的服务是正当需求（SET-041 给的是「显式批准」的入口，
//     这里不因为还没做那个 UI 就把内网源一律封死，那会表现为「我的源全都用不了」）；
//   - [UrlGuardPolicy.embeddedContent]：内容里嵌的地址（正文图片、卡片封面）。拒绝
//     私网、回环、链路本地与唯一本地地址。
//
// 为什么要单独一个文件而不是继续放在 feed_fetcher 里：图片抓取（T021）与订阅抓取
// （T013）必须用**同一条**判据。判据写两份的必然结果是其中一份被更新而另一份没跟上，
// 于是「源里拦住了、图片里没拦住」——正是这类守卫最典型的失效方式。
//
// 本文件是**纯函数**：只做字面量判断（协议、主机名、IP 字面量），不做 DNS 解析。
// DNS 是 I/O，属于 infrastructure；只写字面量检查是不够的（evil.example.com 可以
// 解析到 127.0.0.1），所以基础设施侧还必须**解析后再验一遍**，见
// lib/infrastructure/network/media_fetcher.dart。
library;

import '../error/app_error.dart';
import '../result.dart';

/// 守卫策略：这个地址是谁给的。
enum UrlGuardPolicy {
  /// 用户显式配置的地址（订阅源）。允许私网/回环。
  configuredSource,

  /// 内容里嵌的地址（正文图片、卡片封面）。拒绝私网/回环/链路本地。
  embeddedContent,
}

/// 地址守卫失败的原因类别。
///
/// 分开而不只给一句 message：界面与测试需要区分「协议不对」（用户改地址就能解决）
/// 与「指向内网」（是安全问题，不是配置问题），两者的提示与处理完全不同。
enum UrlGuardFailure {
  /// 协议不是 http/https。
  scheme,

  /// 缺少主机名。
  missingHost,

  /// 指向私网/回环/链路本地地址（仅 [UrlGuardPolicy.embeddedContent] 会出现）。
  privateAddress,
}

/// 一次守卫判定的结果。
final class UrlGuardResult {
  /// 构造结果。
  const UrlGuardResult._({required this.allowed, this.failure, this.detail});

  /// 允许通过。
  const UrlGuardResult.allowed() : this._(allowed: true);

  /// 拒绝。
  const UrlGuardResult.rejected(UrlGuardFailure failure, String detail)
    : this._(allowed: false, failure: failure, detail: detail);

  /// 是否允许。
  final bool allowed;

  /// 失败类别（允许时为 null）。
  final UrlGuardFailure? failure;

  /// 面向日志的细节（已脱敏；不含查询参数里的秘密）。
  final String? detail;
}

/// 判定 [uri] 是否可以通过守卫。
///
/// 只做字面量判断；调用方若面向第三方内容，还必须在 DNS 解析后对**每个**解析结果
/// 再调用 [isPrivateHostLiteral]（见本文件顶部说明）。
UrlGuardResult checkUrlGuarded(Uri uri, UrlGuardPolicy policy) {
  if (!uri.isScheme('http') && !uri.isScheme('https')) {
    return UrlGuardResult.rejected(
      UrlGuardFailure.scheme,
      '只允许 http/https（实际 ${uri.scheme.isEmpty ? '空' : uri.scheme}）',
    );
  }
  if (uri.host.isEmpty) {
    return const UrlGuardResult.rejected(UrlGuardFailure.missingHost, '缺少主机名');
  }
  if (policy == UrlGuardPolicy.embeddedContent &&
      isPrivateHostLiteral(uri.host)) {
    return UrlGuardResult.rejected(
      UrlGuardFailure.privateAddress,
      '主机 ${uri.host} 指向本机或私有网络',
    );
  }
  return const UrlGuardResult.allowed();
}

/// 把守卫结果翻译成类型化错误。
///
/// 单独一个函数而不是让每个调用点自己拼：错误文案与类别必须只有一处（同一件事在
/// 两个入口显示成两种错误，用户会以为是两个不同的问题）。
AppError urlGuardError(Uri uri) => NetworkError(
  uri: uri.toString(),
  reason: '地址被拒绝：指向本机或私有网络，或协议不被允许',
  isRetryable: false,
);

/// 主机名是否**字面上**是本机/私有网络地址。
///
/// 覆盖三类真实会被用到的写法：
///   1) 特殊主机名（localhost 与 .localhost 后缀、.local（mDNS）、.internal）；
///   2) IP 字面量（IPv4 私网段/回环/链路本地，IPv6 回环/唯一本地/链路本地）；
///   3) IPv4 的等价写法不做展开——127.1、0x7f.1、2130706433 这类整数/八进制
///      写法**不是**合法 URI 主机名的常见形态，但 Uri 解析器会保留原样；因此这里
///      对「看起来像数字但没有点」的写法一律按可疑拒绝（宁可拒绝一个奇怪的公网地址，
///      也不要放过一个指向回环的整数写法）。
bool isPrivateHostLiteral(String host) {
  final String normalized = host.toLowerCase();
  // IPv6 字面量在 Uri.host 里带方括号。
  final String bare = normalized.startsWith('[') && normalized.endsWith(']')
      ? normalized.substring(1, normalized.length - 1)
      : normalized;

  if (bare == 'localhost' || bare.endsWith('.localhost')) {
    return true;
  }
  if (bare.endsWith('.local') || bare.endsWith('.internal')) {
    return true;
  }

  // IPv6：回环 ::1、唯一本地 fc00::/7、链路本地 fe80::/10，以及 IPv4 映射写法。
  if (bare.contains(':')) {
    if (bare == '::1' || bare == '0:0:0:0:0:0:0:1') {
      return true;
    }
    // 未指定地址 :: 在多数栈上被解析为本机。
    if (bare == '::' || bare == '::0') {
      return true;
    }
    final String head = bare.split(':').first;
    if (head.startsWith('fc') || head.startsWith('fd')) {
      return true; // 唯一本地地址 fc00::/7
    }
    if (head.startsWith('fe8') ||
        head.startsWith('fe9') ||
        head.startsWith('fea') ||
        head.startsWith('feb')) {
      return true; // 链路本地 fe80::/10
    }
    // IPv4 映射/兼容写法（::ffff:127.0.0.1）：取出尾部并按 IPv4 判定。
    final int lastColon = bare.lastIndexOf(':');
    final String tail = bare.substring(lastColon + 1);
    if (tail.contains('.') && isPrivateIPv4(tail)) {
      return true;
    }
    return false;
  }

  final bool? validIPv4 = tryParseIPv4(bare);
  if (validIPv4 == null) {
    return false; // 不是 IPv4 字面量：按普通域名处理（见下方数字形态的判断）
  }
  if (validIPv4) {
    return isPrivateIPv4(bare);
  }

  // 到了这里：写法「像」IP 但不是合法 IPv4（127.1、1.2.3.4.5、0x7f.1、2130706433）。
  // 不猜测它的真实取值，按可疑拒绝——这些正是绕过「点分四段」检查的常见写法。
  if (RegExp(r'^[0-9.a-fx]+$').hasMatch(bare)) {
    return true;
  }
  return false;
}

/// 尝试把 [host] 解析为**点分四段十进制** IPv4。
///
/// 返回 null 表示「一眼就不像 IP」（普通域名）；返回 true/false 表示「是/不是合法
/// IPv4 字面量」。三态是必需的：调用方要区分「普通域名，放行」与「像 IP 但不合法，
/// 拒绝」——用一个 bool 会把这两件事混在一起，于是要么放过绕过写法，要么误伤所有
/// 公网 IP 地址（本实现第一版就是这么错的，被 media_fetcher 的测试抓到）。
bool? tryParseIPv4(String host) {
  final bool looksNumeric = RegExp(r'^[0-9]').hasMatch(host);
  if (!looksNumeric) {
    return null;
  }
  final List<String> parts = host.split('.');
  if (parts.length != 4) {
    return false;
  }
  for (final String part in parts) {
    if (part.isEmpty ||
        part.length > 3 ||
        !RegExp(r'^[0-9]+$').hasMatch(part)) {
      return false;
    }
    if (int.parse(part) > 255) {
      return false;
    }
  }
  return true;
}

/// IPv4 字面量是否属于回环/私有/链路本地/未指定网段。
bool isPrivateIPv4(String host) {
  final List<String> parts = host.split('.');
  if (parts.length != 4) {
    return false;
  }
  final List<int> octets = <int>[];
  for (final String part in parts) {
    if (part.isEmpty ||
        part.length > 3 ||
        !RegExp(r'^[0-9]+$').hasMatch(part)) {
      return false;
    }
    final int value = int.parse(part);
    if (value > 255) {
      return false;
    }
    octets.add(value);
  }
  final int a = octets[0];
  final int b = octets[1];
  if (a == 0) {
    return true; // 0.0.0.0/8（「本网络」；0.0.0.0 更是明确的本机）
  }
  if (a == 127) {
    return true; // 回环
  }
  if (a == 10) {
    return true; // 10/8
  }
  if (a == 172 && b >= 16 && b <= 31) {
    return true; // 172.16/12
  }
  if (a == 192 && b == 168) {
    return true; // 192.168/16
  }
  if (a == 169 && b == 254) {
    return true; // 链路本地（含云元数据端点 169.254.169.254）
  }
  if (a == 100 && b >= 64 && b <= 127) {
    return true; // CGNAT 100.64/10
  }
  if (a == 198 && (b == 18 || b == 19)) {
    return true; // 基准测试网段 198.18/15
  }
  if (a >= 224) {
    return true; // 组播与保留段
  }
  return false;
}

/// 用守卫判定并返回 [Result]，供基础设施层直接串联。
Result<void> guardUrl(Uri uri, UrlGuardPolicy policy) {
  final UrlGuardResult result = checkUrlGuarded(uri, policy);
  if (result.allowed) {
    return const Ok<void>(null);
  }
  return Err<void>(urlGuardError(uri));
}
