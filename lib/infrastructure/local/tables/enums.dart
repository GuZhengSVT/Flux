// 持久化层枚举（T009 定义，T012 改为**转出口**）。
//
// 取值本身已提升到 lib/core/domain/（架构第 4 节把它们定义为产品规则：三态互斥、
// 身份判定顺序、正文完整性四态、引用获取方式），因为 UI 控件与用例层也要用它们，
// 而 features 层不得 import infrastructure。
//
// 为什么保留这个文件而不是让调用方都改 import：
//   - 迁移与存储层的既有测试（migration*_test.dart、schema_snapshot_test.dart、
//     article_store_test.dart）以 `tables/enums.dart` 为入口。它们是 T009/T010 的
//     证据，本任务无权因为「换个更漂亮的路径」就让它们失效——那会让一次纯重构
//     看起来像行为变更；
//   - 转出口不会产生第二份类型定义，落库文本与 CHECK 约束完全不变，因此**不需要
//     数据迁移**（enums.dart 原本就写明提升时必须保持名称与 @name 注解不变）。
library;

export 'package:flux/core/domain/domain.dart';
