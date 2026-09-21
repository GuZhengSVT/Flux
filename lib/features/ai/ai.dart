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
// TODO(T029): 有预算的队列与故障转移（五次无响应、跨模型重试）。
// TODO(T032): search/fetchPage/inspectImage 受控工具。
library;
