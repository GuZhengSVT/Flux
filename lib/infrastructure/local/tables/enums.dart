// 持久化层枚举（T009）。
//
// 为什么放在 infrastructure/local：这些枚举首先是**数据库取值域**的一部分
// （列的 CHECK 约束、导入导出的稳定字符串），T009 的交付范围是数据层，因此在
// 这里定义可避免 T009 提前建立上层业务模块。
//
// 迁移注意：数据库里存的是**枚举名文本**（drift `textEnum`），不是序号。
// 因此可以安全地新增取值，但**重命名或删除已有取值会让历史数据变成非法值**。
// 若 T017/T041 需要把它们提升为 domain 层类型，必须保持名称与 @name 注解不变，
// 并保留这里已落库的字符串取值。
library;

/// 文章阅读状态（架构 4.1，D-10）。
///
/// 三值是**互斥**的单一字段，不存在“已读且稍后再读”的组合；收藏是独立布尔列，
/// 见 `articles.favorite`。数据库层用 CHECK 约束拒绝未列出的取值。
enum ReadingState {
  unread,
  read,

  /// 稍后再读：打开后仍保持 later，只有用户显式“标为已读”才变为 read。
  later,
}

/// 文章正文完整性（架构 4.2）。
///
/// - [sourceBody]：来源 feed 提供了完整正文内容；
/// - [summaryOnly]：来源只有摘要，不能当作全文；
/// - [extracted]：本机通过静态网页提取得到的正文（T024）；
/// - [unknown]：尚未判定（默认值）。
enum BodyCompleteness { sourceBody, summaryOnly, extracted, unknown }

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

/// 引用的材料获取方式（架构 4.4）。
///
/// 用于区分“只读 RSS 未联网核验”与真实联网获取的证据。
enum CitationAccessMethod { rss, fetch, search }

/// 兜底指纹的可靠度（架构 4.1：不可靠兜底身份保留诊断，不用于误合并）。
///
/// - [reliable]：来源 + 标题 + **已知发布时间**都在，指纹可以参与匹配；
/// - [unreliable]：发布时间缺失，指纹只由来源 + 标题构成，容易把不同文章
///   误判成同一篇。这类行允许入库并保留诊断，但同步/合并时不得据此静默合并。
enum FingerprintReliability { reliable, unreliable }
