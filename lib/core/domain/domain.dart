// 领域取值类型（T012 提升，架构第 4 节）。
//
// 这些枚举是**产品规则的可执行形式**（阅读三态互斥、身份判定顺序、正文完整性
// 四态、引用获取方式），被 UI 控件、用例与存储共同引用。放在 core 使
// features 层可以在不依赖 infrastructure 的前提下使用它们。
library;

export 'article_identity.dart';
export 'citation_access.dart';
export 'reading_state.dart';
