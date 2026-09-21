# AI 适配器夹具（T026）

按**协议分文件**，两个协议不共用任何期望文件——它们的事件流形状、usage 字段名与
错误体结构都不同，共用一份夹具会让「把 Responses 的解析器接到 Chat Completions 上」
这类错误在测试里看起来仍然通过（架构 4.3 明确要求两者独立建模、不能只改 URL）。

| 文件 | 协议 | 用途 |
| --- | --- | --- |
| `chat_completions_stream.sse` | Chat Completions | 正常流：角色 chunk、增量、finish_reason、末位 usage chunk、[DONE] |
| `chat_completions_multiline.sse` | Chat Completions | 边界：CRLF 行尾、SSE 注释心跳、多行 data、空行填空 chunk |
| `chat_completions_truncated.sse` | Chat Completions | 断流：没有 [DONE]、也没有 finish_reason |
| `chat_completions_error_429.json` | Chat Completions | 错误体：rate_limit_exceeded（配合 Retry-After 头使用） |
| `responses_stream.sse` | Responses | 正常事件流：response.created、output_text.delta、response.completed（含 usage） |
| `responses_multiline.sse` | Responses | 边界：CRLF、注释心跳、未知事件类型必须被忽略 |
| `responses_truncated.sse` | Responses | 断流：有 delta 但没有 response.completed |
| `responses_error_filter.json` | Responses | 错误体：content_filter（400） |

约定：
- 只使用保留域名（example.com）与**明显的假凭据**（`sk-fixture-...`），不含任何真实 Key；
- 文件保留原始 SSE 字节（含 CRLF 的那两份刻意保留），因为「行尾处理」正是要验的行为。

