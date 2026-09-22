// infrastructure/network：RSS/静态网页、AI/Search 适配器、WebDAV。
//
// 所有出网请求都必须经过本层，以便统一实现超时、取消、限流与脱敏；
// 业务层不得直接拼接 HTTP 请求（架构第 2.2、8 节）。
//
// TODO(T013): RSS/Atom 抓取与清洗。
// 已落地：feed_fetcher（T013）、media_fetcher（T021）、static_page_fetcher（T024）、
// 三个 AI 协议适配器（T026/T027）、三个搜索协议适配器（T031）、
// webdav_client 与 webdav_snapshot_publisher（T042，条件发布协议）。
library;
