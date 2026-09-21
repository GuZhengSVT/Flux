// ai（AI 提供商、模型、工具执行器）目录出口 —— T025–T035 落地。
//
// 能力按 provider 声明，不按模型名猜测（架构第 4.3 节）。
//
// T025 已落地：
//   domain/ai_protocol.dart      协议标识（三个协议，未实现的适配器显式标注）
//   domain/ai_message.dart       统一请求/消息/事件（delta、usage、done）与取消信号
//   domain/model_capability.dart 五项独立能力 + 保守预算回退（SET-033）
//   domain/ai_model.dart         模型记录与取值域校验（SET-030/032/033）
//   domain/ai_provider.dart      AIProvider 契约与适配器工厂
//   domain/ai_credential_store.dart 凭据端口（SET-031）
//   application/model_manager.dart   CRUD、排序/启停、引用检查、最小生成测试
//   application/model_manager_controller.dart 页面状态与失败分类
//   presentation/ai_services_page.dart + ai_model_form.dart
//
// T026 已落地：infrastructure/network/{sse,ai_stream_guard,ai_http}.dart、
//   chat_completions_adapter.dart、responses_adapter.dart、ai_provider_factory.dart
//   （三个协议各一个适配器，工厂是唯一装配点）。
// T027 已落地：anthropic_messages_adapter.dart（x-api-key + anthropic-version、
//   顶层 system、必填 max_tokens、content 分量数组、带 type 的事件流、usage 拼合、
//   529 → 可重试的 overloaded）。
// T029 已落地：application/ai_task_budget.dart（三个上限 + 在途额度 + 等待调度）、
//   application/ai_failover.dart（失败分类与五次计数、保守 Token 估算）、
//   application/ai_task_runner.dart（有预算的队列：串行故障转移、子取消、单次硬时限、
//   429 一次、离线暂停、状态机接线）。**不再**用「TODO」占位它。
// T030 已落地：domain/ai_task_record.dart（任务记录、输入快照、缓存键）、
//   domain/ai_task_store.dart（持久任务与结果缓存两个端口）、
//   application/persistent_ai_task_service.dart（先查缓存再执行、成功才写缓存、
//   启动标中断、重新开始走新任务）、presentation/ai_task_list_page.dart。
// T031 已落地：domain/search_protocol.dart（三个搜索协议与认证方式）、
//   domain/search_result.dart（统一结果结构与 sourceId 摘要）、
//   domain/search_service.dart（服务记录，SET-038/040/041）、
//   domain/search_service_store.dart、domain/search_credential_store.dart（SET-039，
//   与 AI 凭据分属不同 Keychain 类别）、domain/search_provider.dart（SearchProvider 契约）、
//   domain/search_errors.dart（搜索口径的错误映射、结果地址守卫、访问类别、高亮剥离）、
//   application/search_manager.dart（CRUD/排序/引用检查/最小检索测试）、
//   application/search_manager_controller.dart、
//   presentation/search_services_page.dart + search_service_form.dart；
//   infrastructure/network/{search_http,tavily_search_adapter,brave_search_adapter,
//   searxng_search_adapter,search_provider_factory}.dart。
// TODO(T032): search/fetchPage/inspectImage 受控工具。
library;
