// 卡片视图模式（T019+；架构第 7 节「卡片：紧凑无图、正常右图 96×72、宽松上图 16:9」）。
//
// 三种模式的差异是**产品口径**，因此各自的行数与尺寸写在这里，而不是散落在控件的
// 构建代码里：卡片形态正是「一眼看不出但确实错」的那类东西（标题少一行、图少 24 逻辑
// 像素都不会崩），把它们集中成一份可直接断言的数值，测试才能逐项钉住。
//
// 与 SET-008 的关系：listView 分量的取值就是这里的稳定字符串名（compact/normal/
// relaxed）。落库与同步都用这个名，不用序号——序号会在插入一种新模式时把所有人的
// 设置悄悄改指向另一种模式。
library;

/// 卡片视图模式。
enum ArticleCardViewMode {
  /// 紧凑：无图，标题 2 行 + 摘要 1 行。
  compact('compact'),

  /// 正常：右侧 96×72 缩略图，标题 2 行 + 摘要 2 行。
  normal('normal'),

  /// 宽松：上方 16:9 大图，标题 3 行 + 摘要 3 行。
  relaxed('relaxed');

  const ArticleCardViewMode(this.storageName);

  /// 落库/同步用的稳定名（SET-008 里 listView 分量的取值）。
  final String storageName;

  /// 按设置值解析；未知值回退到 [normal]。
  ///
  /// 回退而不是抛错：一个损坏或来自更新版本的设置值不应该让整页读不出来。回退目标取
  /// 文档给 SET-008 的**默认值** normal，而不是「上一个用过的模式」——后者需要一份
  /// 我们没有的第二状态。
  static ArticleCardViewMode fromStorage(String? value) {
    for (final ArticleCardViewMode mode in values) {
      if (mode.storageName == value) {
        return mode;
      }
    }
    return ArticleCardViewMode.normal;
  }

  /// 标题最多显示几行（架构第 7 节）。
  int get titleLines => switch (this) {
    ArticleCardViewMode.compact => 2,
    ArticleCardViewMode.normal => 2,
    ArticleCardViewMode.relaxed => 3,
  };

  /// 摘要最多显示几行。
  int get summaryLines => switch (this) {
    ArticleCardViewMode.compact => 1,
    ArticleCardViewMode.normal => 2,
    ArticleCardViewMode.relaxed => 3,
  };

  /// 是否在卡片上参与图片位布局。
  ///
  /// 紧凑模式**没有**图位（不是「图位但空着」）：缺图不占位是架构第 7 节对缺图的
  /// 要求，而紧凑模式的整体取舍就是「用图换密度」，因此它连图位都不参与布局。
  bool get showsImage => this != ArticleCardViewMode.compact;

  /// 图是否画在标题上方（宽松）还是右侧（正常）。
  bool get imageOnTop => this == ArticleCardViewMode.relaxed;
}

/// 右侧缩略图的逻辑宽度（架构第 7 节：96×72）。
const double kCardThumbWidth = 96;

/// 右侧缩略图的逻辑高度（架构第 7 节：96×72）。
const double kCardThumbHeight = 72;

/// 宽松模式大图的宽高比（架构第 7 节：16:9）。
const double kCardCoverAspectRatio = 16 / 9;
