// 文章身份与正文完整性（架构 4.1、4.2）——同样是产品规则，不是存储细节。
//
// 提升理由与 reading_state.dart 相同：T013 的解析/去重发生在 features/feeds/domain，
// 而 features 层不得 import infrastructure。取值名称与顺序保持不变，落库文本不变。
library;

/// 文章身份判定依据（架构 4.1）。
///
/// 优先级：GUID → 规范化链接 → 来源/标题/时间指纹。身份**不**使用正文哈希，
/// 正文哈希只用于判断修订。
enum IdentityBasis {
  /// 源内 GUID，仅在所属 Feed 范围内识别。
  guid,

  /// 无 GUID 时使用规范化链接。
  normalizedLink,

  /// 前三者都缺失时使用来源/标题/时间指纹兜底。
  fingerprint,
}

/// 兜底指纹的可靠度（架构 4.1：不可靠兜底身份保留诊断，不用于误合并）。
///
/// - [reliable]：来源 + 标题 + **已知发布时间**都在，指纹可以参与匹配；
/// - [unreliable]：发布时间缺失，指纹只由来源 + 标题构成，容易把不同文章
///   误判成同一篇。这类行允许入库并保留诊断，但同步/合并时不得据此静默合并。
enum FingerprintReliability { reliable, unreliable }

/// 文章正文完整性（架构 4.2）。
///
/// - [sourceBody]：来源 feed 提供了完整正文内容；
/// - [summaryOnly]：来源只有摘要，不能当作全文；
/// - [extracted]：本机通过静态网页提取得到的正文（T024）；
/// - [unknown]：尚未判定（默认值）。
enum BodyCompleteness { sourceBody, summaryOnly, extracted, unknown }
