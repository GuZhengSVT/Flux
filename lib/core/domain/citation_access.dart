// 引用材料获取方式（架构 4.4）。
//
// 提升理由同 article_identity.dart：引用的「是否真的联网核验过」属于产品事实，
// 需要被 AI 引用校验（T036–T040）与解析层共同引用。
library;

/// 引用的材料获取方式（架构 4.4）。
///
/// 用于区分“只读 RSS 未联网核验”与真实联网获取的证据。
enum CitationAccessMethod { rss, fetch, search }
