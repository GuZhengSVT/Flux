// news（今日总结、来源核验、prompt 与定时）目录入口 —— T036–T040 已全部落地。
//
// 依赖方向（架构第 2.2 节）：presentation -> application -> core/domain；
// infrastructure 由 app 在组合根注入，features 内部不得直接 import
// 'package:flux/infrastructure/...'。
//
// 已落地（T036–T040，见手册 R036–R040）：
//   application/news_source_config.dart      来源配置、版本化 prompt 与组合（T036）
//   application/news_run_inputs.dart         输入快照、选材去重与材料构造（T037，纯函数）
//   application/news_run_service.dart        编排：快照 → 必访 → 检索 → 生成 → 保存（T037）
//   application/news_verification_service.dart 独立来源核验与引用校验（T038）
//   application/news_today_controller.dart   今日页状态：日期/版本/进度/取消（T038/T039）
//   application/daily_news_scheduler.dart    默认开启的定时调度（T040）
//   application/daily_news_run.dart          定时任务的运行占位与收尾（T040）
//   presentation/news_today_page.dart        今日页（T038/T039）
//   presentation/news_source_settings_page.dart 设置页（T036）＋定时小节（T040）
//
// 时间规则本身住在 core/domain/news_schedule.dart（纯函数，可逐秒断言）。
library;
