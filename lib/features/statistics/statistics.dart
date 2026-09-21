// statistics（阅读会话、热力图、七日统计）—— T023。
//
// 统计是本机估计值，首发不跨设备相加（架构第 5.3 节）。
//
// 分层：domain（core/domain/*）定义会话与图形的纯规则；application 负责会话追踪与
// 页面状态；presentation 只做映射。infrastructure 由组合根注入。
library;

export 'application/reading_stats_controller.dart';
export 'application/reading_stats_ports.dart';
export 'application/reading_stats_state.dart';
export 'application/reading_session_tracker.dart';
export 'presentation/heatmap_cell_tile.dart';
export 'presentation/reading_stats_page.dart';
