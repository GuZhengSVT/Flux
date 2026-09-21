# 测试夹具（T008）

本目录是**共享夹具**：网络、解析、渲染和 AI 协议的测试都从这里取输入，不再各自
内联一份样本。夹具是虚构内容，不含任何真实订阅、真实正文或真实凭据。

| 文件 | 用途 | 主要消费任务 |
| --- | --- | --- |
| `rss_sample.rss2.xml` | RSS 2.0 最小样本：单 channel、两 item、含 GUID/pubDate/content:encoded | T013（抓取与解析）、T017 |
| `rss_sample.atom.xml` | Atom 1.0 最小样本：feed 级元数据、entry、link rel 变体 | T013 |
| `rss_sample.atom_xhtml.xml` | Atom 中 XHTML 正文（`type="xhtml"`）与 `<content>` 差异样本 | T013/T019（渲染） |
| `opml_sample.opml` | OPML 2.0：含分组嵌套、扁平订阅、重复地址、缺 `xmlUrl` 的无效项 | T015（导入预览/重试） |
| `markdown_math_sample.md` | 常用 LaTeX（架构 4.2 列表）与 Markdown 结构混排 | T004 固化 / T019/T020（渲染） |
| `fake_ai_response.json` | `chat.completions` 形状的假文本响应，含完整 `usage` 明细 | T026（Chat 适配器）、T029（预算核算） |
| `fake_ai_tool_call_response.json` | `chat.completions` 形状的工具调用响应（`finish_reason: tool_calls`） | T026/T032（工具执行器） |
| `tavily_search_response.json` | Tavily 搜索响应：三条结果（含 1 条链路本地地址、1 条缺时间/分数）、answer、response_time | T031（Tavily 适配器） |
| `tavily_search_error_429.json` | Tavily 限流错误体（结构字段形态） | T031 |
| `brave_search_response.json` | Brave 搜索响应：`web.results` 嵌套、带 `<b>` 高亮的标题与片段、`age` 相对时间、1 条回环地址 | T031（Brave 适配器） |
| `searxng_search_response.json` | SearXNG 响应：`results` + `number_of_results`，含带 `+08:00` 偏移的 `publishedDate` 与一条无字段结果 | T031（SearXNG 适配器） |
| `searxng_private_response.json` | SearXNG 响应：结果 URL 指向私网地址、`publishedDate` 非法 | T031（结果地址守卫） |

约定：

- 夹具中的时间全部写死为 UTC，测试不得依赖“当前时间”；
- 夹具中的 URL 一律使用 `example.com` 等保留域名，避免测试意外触网；
- 修改夹具视为接口变更：相关测试必须同步更新，不能在测试里就地打补丁绕过。
