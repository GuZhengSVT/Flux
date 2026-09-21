// 设置 ID（T010，架构第 6 节）。
//
// 为什么用「值对象 + 具名常量」而不是裸字符串：
//   - SET 编号是架构说明书里的稳定主键（SET-001..084），配置读写、同步投影、
//     设置页入口都以它为准。用 const 常量可以让拼错编号在编译期暴露，而不是
//     悄悄写进一个永远读不到的键；
//   - 编号在文档里有**空隙**（001–016、020–028、030–042、050–066、070–084），
//     这里只收录文档确实存在的编号，不为「看起来连续」而造号。
//
// 说明：仅集合内这些编号存在。测试会把 all 与架构第 6 节表格逐条对齐。
library;

/// 一个设置项标识（形如 SET-004）。
final class SettingId implements Comparable<SettingId> {
  /// 以文档编号构造；编号字符串即主键，不再额外维护映射。
  const SettingId(this.code);

  /// 文档编号，例如 SET-004。
  final String code;

  // ---------------------------------------------------------------------
  // 6.1 通用、外观与阅读
  // ---------------------------------------------------------------------

  /// 界面语言（跟随系统/简体中文/English）。
  static const SettingId set001 = SettingId('SET-001');

  /// 主题（系统/浅/深）。
  static const SettingId set002 = SettingId('SET-002');

  /// 浅/深主题背景图。
  static const SettingId set003 = SettingId('SET-003');

  /// 背景不透明度/模糊/亮度。
  static const SettingId set004 = SettingId('SET-004');

  /// UI/文章/新闻字体。
  static const SettingId set005 = SettingId('SET-005');

  /// UI/文章/新闻字号。
  static const SettingId set006 = SettingId('SET-006');

  /// 纸张背景、阅读专用字体和字号倍率。
  static const SettingId set007 = SettingId('SET-007');

  /// 列表视图/桌面栏宽。
  static const SettingId set008 = SettingId('SET-008');

  /// 列表排序/筛选/返回位置。
  static const SettingId set009 = SettingId('SET-009');

  /// 成功显示正文自动标已读。
  static const SettingId set010 = SettingId('SET-010');

  /// 翻译目标语言/生成语言。
  static const SettingId set011 = SettingId('SET-011');

  /// 自动加载远程图片。
  static const SettingId set012 = SettingId('SET-012');

  /// 允许计费网络下载媒体/后台请求。
  static const SettingId set013 = SettingId('SET-013');

  /// 减少动态效果。
  static const SettingId set014 = SettingId('SET-014');

  /// 阅读统计/空闲暂停时间。
  static const SettingId set015 = SettingId('SET-015');

  /// 专注阅读布局。
  static const SettingId set016 = SettingId('SET-016');

  // ---------------------------------------------------------------------
  // 6.2 订阅与刷新
  // ---------------------------------------------------------------------

  /// 全局自动刷新及间隔。
  static const SettingId set020 = SettingId('SET-020');

  /// 启动时刷新。
  static const SettingId set021 = SettingId('SET-021');

  /// 单源名称/分组/启用/刷新间隔。
  static const SettingId set022 = SettingId('SET-022');

  /// 单源加精。
  static const SettingId set023 = SettingId('SET-023');

  /// 分组名称/排序/置顶。
  static const SettingId set024 = SettingId('SET-024');

  /// 分组展开/折叠。
  static const SettingId set025 = SettingId('SET-025');

  /// OPML 导入分组策略。
  static const SettingId set026 = SettingId('SET-026');

  /// 私密源凭据/URL 秘密参数（秘密）。
  static const SettingId set027 = SettingId('SET-027');

  /// 订阅抓取并发/单源超时。
  static const SettingId set028 = SettingId('SET-028');

  // ---------------------------------------------------------------------
  // 6.3 AI 与搜索服务
  // ---------------------------------------------------------------------

  /// AI 提供商预设/协议/Base URL/别名。
  static const SettingId set030 = SettingId('SET-030');

  /// AI API Key/认证秘密（秘密）。
  static const SettingId set031 = SettingId('SET-031');

  /// 模型 ID/启用/排序/删除。
  static const SettingId set032 = SettingId('SET-032');

  /// 模型能力与上下文/输出上限。
  static const SettingId set033 = SettingId('SET-033');

  /// 专用视觉模型。
  static const SettingId set034 = SettingId('SET-034');

  /// 故障转移及允许目标。
  static const SettingId set035 = SettingId('SET-035');

  /// AI 并发/首响应超时/流停滞超时。
  static const SettingId set036 = SettingId('SET-036');

  /// 缺摘要时自动 AI 摘要。
  static const SettingId set037 = SettingId('SET-037');

  /// 搜索服务协议/端点/排序/启用。
  static const SettingId set038 = SettingId('SET-038');

  /// 搜索 API Key/实例认证（秘密）。
  static const SettingId set039 = SettingId('SET-039');

  /// 每次搜索结果数/单次超时。
  static const SettingId set040 = SettingId('SET-040');

  /// 允许指定内网/HTTP 服务端点。
  static const SettingId set041 = SettingId('SET-041');

  /// 连通性/最小生成/搜索测试（动作，不是持久设置）。
  static const SettingId set042 = SettingId('SET-042');

  // ---------------------------------------------------------------------
  // 6.4 新闻生成、prompt 与资源预算
  // ---------------------------------------------------------------------

  /// RSS 内容总开关/逐源开关。
  static const SettingId set050 = SettingId('SET-050');

  /// 必访问网站列表。
  static const SettingId set051 = SettingId('SET-051');

  /// 联网搜索关键词列表。
  static const SettingId set052 = SettingId('SET-052');

  /// 禁止发送的查询词/排除内容主题。
  static const SettingId set053 = SettingId('SET-053');

  /// 输出规范 prompt/重置。
  static const SettingId set054 = SettingId('SET-054');

  /// 总体任务说明/总 prompt 模式。
  static const SettingId set055 = SettingId('SET-055');

  /// 本设备自动定时总结。
  static const SettingId set056 = SettingId('SET-056');

  /// 每日执行时间。
  static const SettingId set057 = SettingId('SET-057');

  /// 新闻时区（只读「跟随设备」）。
  static const SettingId set058 = SettingId('SET-058');

  /// 每任务总时限。
  static const SettingId set059 = SettingId('SET-059');

  /// 每任务最多输入文章/必访站/搜索查询。
  static const SettingId set060 = SettingId('SET-060');

  /// 单材料文本预算。
  static const SettingId set061 = SettingId('SET-061');

  /// 工具调用总次数/模型 HTTP 尝试总数。
  static const SettingId set062 = SettingId('SET-062');

  /// 每任务累计输入+输出 Token 预算。
  static const SettingId set063 = SettingId('SET-063');

  /// 当天自动摘要任务数。
  static const SettingId set064 = SettingId('SET-064');

  /// 图像分析开关/最多图片/单图上传上限。
  static const SettingId set065 = SettingId('SET-065');

  /// 模型单价与费用提醒。
  static const SettingId set066 = SettingId('SET-066');

  // ---------------------------------------------------------------------
  // 6.5 同步、备份、存储与关于
  // ---------------------------------------------------------------------

  /// WebDAV URL/用户/远端目录/设备名。
  static const SettingId set070 = SettingId('SET-070');

  /// WebDAV 密码/Token（秘密）。
  static const SettingId set071 = SettingId('SET-071');

  /// 同步启用/启动同步/变更后同步。
  static const SettingId set072 = SettingId('SET-072');

  /// 自动同步间隔/手动同步。
  static const SettingId set073 = SettingId('SET-073');

  /// 共通设置/阅读状态同步范围。
  static const SettingId set074 = SettingId('SET-074');

  /// 首次同步/冲突处理。
  static const SettingId set075 = SettingId('SET-075');

  /// 导出明文备份/是否含媒体/恢复。
  static const SettingId set076 = SettingId('SET-076');

  /// 媒体/文章/总结自动清理开关与天数。
  static const SettingId set077 = SettingId('SET-077');

  /// 自动清理包含收藏/稍后再读。
  static const SettingId set078 = SettingId('SET-078');

  /// 清理预览/一键清缓存/占用刷新（动作，不是持久设置）。
  static const SettingId set079 = SettingId('SET-079');

  /// 媒体缓存上限。
  static const SettingId set080 = SettingId('SET-080');

  /// 删除订阅是否保留收藏。
  static const SettingId set081 = SettingId('SET-081');

  /// 诊断日志级别/保留天数。
  static const SettingId set082 = SettingId('SET-082');

  /// 检查更新/发布通道。
  static const SettingId set083 = SettingId('SET-083');

  /// 版本/GitHub/Issue/开发者/贡献者/许可（只读发布元数据）。
  static const SettingId set084 = SettingId('SET-084');

  /// 文档中存在的全部设置编号，按编号升序。
  ///
  /// 编号不连续是事实（文档本就按 001/020/030/050/070 分段），不要「补齐」。
  static const List<SettingId> all = <SettingId>[
    set001,
    set002,
    set003,
    set004,
    set005,
    set006,
    set007,
    set008,
    set009,
    set010,
    set011,
    set012,
    set013,
    set014,
    set015,
    set016,
    set020,
    set021,
    set022,
    set023,
    set024,
    set025,
    set026,
    set027,
    set028,
    set030,
    set031,
    set032,
    set033,
    set034,
    set035,
    set036,
    set037,
    set038,
    set039,
    set040,
    set041,
    set042,
    set050,
    set051,
    set052,
    set053,
    set054,
    set055,
    set056,
    set057,
    set058,
    set059,
    set060,
    set061,
    set062,
    set063,
    set064,
    set065,
    set066,
    set070,
    set071,
    set072,
    set073,
    set074,
    set075,
    set076,
    set077,
    set078,
    set079,
    set080,
    set081,
    set082,
    set083,
    set084,
  ];

  @override
  int compareTo(SettingId other) => code.compareTo(other.code);

  @override
  bool operator ==(Object other) => other is SettingId && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}
