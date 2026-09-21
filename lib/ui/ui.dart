// lib/ui 统一出口（barrel）——共享控件层（T012）。
//
// 为什么需要独立的一层，而不是把控件放进 lib/features 或 lib/app：
//
//   - features 不得 import lib/app（T011 已固化为守卫测试：设置页曾因为
//     「顺手拿个颜色」import package:flux/app/theme 而与 app 形成目录级循环）；
//   - 但「空态 / 状态横幅 / 卡片 / 三态控件」会被**多个** feature 共同使用
//     （feeds 的订阅列表、articles 的文章列表与详情、news 的今日页、settings）；
//     放在任一 feature 下，其他 feature 就要横向依赖它，形成 feature 之间的耦合；
//   - 因此设一层与特征无关的共享控件层：它只依赖 core（token）与 l10n，不依赖
//     app 或任何 feature。依赖方向为 app/features → ui → core，无环。
//
// 色值来源：lib/ui **不** import lib/app/theme。FluxTheme 已把架构第 7 节的 token
// 映射进标准 ColorScheme（primary=accent、tertiary=warning、error=danger、
// surfaceContainerHigh=selectedSurface、outline=border、onSurfaceVariant=textSecondary），
// 共享控件只读 ColorScheme，因此既拿得到精确 token，又不产生反向依赖。
library;

export 'controls/flux_control_status.dart';
export 'controls/flux_loading_indicator.dart';
export 'controls/flux_stateful_tap.dart';
export 'controls/reading_state_control.dart';
export 'icons/flux_icons.dart';
export 'widgets/flux_common_widgets.dart';
