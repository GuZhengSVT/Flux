# AI 适配器夹具（T026/T027）

按**协议分文件**，两个协议不共用任何期望文件——它们的事件流形状、usage 字段名与
错误体结构都不同，共用一份夹具会让「把 Responses 的解析器接到 Chat Completions 上」
这类错误在测试里看起来仍然通过（架构 4.3 明确要求两者独立建模、不能只改 URL）。
Anthropic Messages 是**第三个独立协议**（T027）：认证头、max_tokens 必填、顶层 system、
content 分量数组、带 type 的事件流、input/output 两处 usage 都与前两者不同。

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
| `anthropic_stream.sse` | Anthropic Messages | 正常事件流：message_start（含 input_tokens）、content_block_start/delta/stop、message_delta（output_tokens 累计）、message_stop |
| `anthropic_multiline.sse` | Anthropic Messages | 边界：CRLF 行尾、ping 注释、**多 content block**（两个 index）、未知事件必须被忽略 |
| `anthropic_truncated.sse` | Anthropic Messages | 断流：有 message_start 与 delta 但没有 message_stop |
| `anthropic_error_429.json` | Anthropic Messages | 错误体：rate_limit_error（429，配合 Retry-After 头） |
| `anthropic_error_529.json` | Anthropic Messages | 错误体：overloaded_error（529，Anthropic 特有的可重试类别） |

约定：
- 只使用保留域名（example.com）与**明显的假凭据**（`sk-fixture-...`），不含任何真实 Key；
- 文件保留原始 SSE 字节（含 CRLF 的那两份刻意保留），因为「行尾处理」正是要验的行为。
