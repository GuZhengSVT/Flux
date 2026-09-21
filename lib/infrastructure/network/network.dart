// infrastructure/network：RSS/静态网页、AI/Search 适配器、WebDAV。
//
// 所有出网请求都必须经过本层，以便统一实现超时、取消、限流与脱敏；
// 业务层不得直接拼接 HTTP 请求（架构第 2.2、8 节）。
//
// TODO(T013): RSS/Atom 抓取与清洗。
// TODO(T024): StaticPageFetcher。
// TODO(T026+): AI/Search 适配器。
library;
