// feeds（订阅/分组/OPML）目录占位 —— T013–T016 落地。
//
// 依赖方向（架构第 2.2 节）：presentation -> application -> domain；
// infrastructure 由 app 在组合根注入，features 内部不得直接 import
// 'package:flux/infrastructure/...'。
//
// TODO(T013): RSS/Atom 网络、解析、去重。
// TODO(T014): 单源导入、编辑、分组/排序/置顶/加精。
// TODO(T015): OPML 预览、批量导入、导出。
// TODO(T016): 刷新调度与网络策略。
library;
