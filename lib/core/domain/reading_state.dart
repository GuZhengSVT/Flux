// 阅读状态（架构 4.1、D-10）——**产品规则**，不是存储细节。
//
// 为什么从 infrastructure/local/tables/enums.dart 提升到 core：
//   - 该枚举的语义来自架构第 4 节：「readingState 是 unread/read/later 单一枚举，
//     收藏独立」。这是产品契约，被 UI 控件（T012 的 ReadingStateControl）、用例
//     （T017 的自动标已读）和存储共同引用；
//   - features 层不得 import infrastructure（test/core/architecture_layering_test.dart
//     会拦截），因此控件若要从 infrastructure 取这个类型就无法实现；
//   - enums.dart 里原本就写明「若 T017/T041 需要把它们提升为 domain 层类型，必须
//     保持名称与 @name 注解不变」。这里按该约定执行：名称、取值、顺序完全不变，
//     存储里落库的仍是同样的枚举名文本，因此**不需要数据迁移**。
//
// 不变量：三个取值互斥，不存在「已读且稍后再读」的组合；收藏是独立布尔值。
library;

/// 文章阅读状态（架构 4.1，D-10）。
///
/// 三值是**互斥**的单一字段，不存在“已读且稍后再读”的组合；收藏是独立布尔列，
/// 见 `articles.favorite`。数据库层用 CHECK 约束拒绝未列出的取值。
enum ReadingState {
  unread,
  read,

  /// 稍后再读：打开后仍保持 later，只有用户显式“标为已读”才变为 read。
  later,
}
