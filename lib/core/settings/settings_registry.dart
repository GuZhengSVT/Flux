// 设置注册表（T010）——架构说明书第 6 节的权威清单的可执行形式。
//
// 录入规则（写下来是为了让后来改这里的人知道边界在哪）：
//   1. 逐条对照架构第 6 节的 70 个编号，不合并、不省略、不补编号；
//   2. 默认值与范围**照抄文档**。文档给区间的写区间；文档没给区间的（颜色、
//      字体名、URL、枚举没有明确取值时）不臆造上/下限，否则会无故拒绝用户配置；
//   3. 第 4 列的 C/D/S 直接映射为 SettingClassification——它是同步投影（T041）
//      与「秘密不进普通存储」的判断依据，不能与文档漂移；
//   4. 文档写明「操作，不是持久设置」的编号用 ActionSpec 且 isPersistent = false；
//      标为只读的编号用 isReadOnly = true。
//
// 与文档的偏差必须在这里注明原因；测试会用固定清单交叉核对编号与分类。
library;

import 'setting_definition.dart';
import 'setting_id.dart';

/// 界面语言取值（SET-001）。
const List<String> _languageValues = <String>['system', 'zh-Hans', 'en'];

/// 主题取值（SET-002）。
const List<String> _themeValues = <String>['system', 'light', 'dark'];

/// 中/英两种内容的语言取值（SET-011）。
const List<String> _contentLanguageValues = <String>['zh-Hans', 'en'];

/// 全局刷新间隔取值（SET-020：手动、15/30/60/120 分钟）。
const List<String> _refreshIntervalValues = <String>[
  'manual',
  '15',
  '30',
  '60',
  '120',
];

/// 诊断日志级别取值（SET-082：默认 error，可选 warning/info）。
const List<String> _logLevelValues = <String>['error', 'warning', 'info'];

/// 设置注册表：编号 → 定义。
///
/// 用不可变 Map 暴露只读视图；写入只能通过本文件，避免运行期悄悄新增一项
/// 绕过文档与测试。
abstract final class SettingRegistry {
  /// 全部设置定义，按编号升序（与文档第 6 节的阅读顺序一致）。
  static const List<SettingDefinition> all = <SettingDefinition>[
    // -----------------------------------------------------------------------
    // 6.1 通用、外观与阅读
    // -----------------------------------------------------------------------

    // 界面语言：默认跟随系统；跟随系统时各设备自行解析，无匹配回退英文。
    SettingDefinition(
      id: SettingId.set001,
      title: '界面语言',
      spec: EnumSpec(values: _languageValues, defaultValue: 'system'),
      classification: SettingClassification.common,
    ),
    // 主题：默认跟随系统；各设备独立解析。
    SettingDefinition(
      id: SettingId.set002,
      title: '主题',
      spec: EnumSpec(values: _themeValues, defaultValue: 'system'),
      classification: SettingClassification.common,
    ),
    // 浅/深背景图各一张；默认无。
    SettingDefinition(
      id: SettingId.set003,
      title: '主题背景图',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'light', spec: StringSpec()),
          SettingField(name: 'dark', spec: StringSpec()),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 背景不透明度 20% / 模糊 8 / 亮度 100%；范围 0–40% / 0–24 / 50–150%。
    SettingDefinition(
      id: SettingId.set004,
      title: '背景不透明度/模糊/亮度',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'opacityPercent',
            spec: IntSpec(defaultValue: 20, min: 0, max: 40),
          ),
          SettingField(
            name: 'blur',
            spec: IntSpec(defaultValue: 8, min: 0, max: 24),
          ),
          SettingField(
            name: 'brightnessPercent',
            spec: IntSpec(defaultValue: 100, min: 50, max: 150),
          ),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // UI/文章/新闻字体：默认都用系统字体（文档「系统无衬线/系统正文/系统正文」）。
    // 字体名为平台相关字符串，文档未给取值集合，因此不做枚举限制。
    SettingDefinition(
      id: SettingId.set005,
      title: 'UI/文章/新闻字体',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'ui', spec: StringSpec()),
          SettingField(name: 'article', spec: StringSpec()),
          SettingField(name: 'news', spec: StringSpec()),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 字号：桌面 UI 14、手机 16；正文/新闻 18；UI 12–24、正文 14–28。
    SettingDefinition(
      id: SettingId.set006,
      title: 'UI/文章/新闻字号',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'uiDesktop',
            spec: IntSpec(defaultValue: 14, min: 12, max: 24),
          ),
          SettingField(
            name: 'uiMobile',
            spec: IntSpec(defaultValue: 16, min: 12, max: 24),
          ),
          SettingField(
            name: 'article',
            spec: IntSpec(defaultValue: 18, min: 14, max: 28),
          ),
          SettingField(
            name: 'news',
            spec: IntSpec(defaultValue: 18, min: 14, max: 28),
          ),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 纸张背景 浅 #F4EEDC / 深 #20221F、系统阅读字体、1.1 倍。
    SettingDefinition(
      id: SettingId.set007,
      title: '纸张背景/阅读字体/字号倍率',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'paperLight',
            spec: StringSpec(defaultValue: '#F4EEDC'),
          ),
          SettingField(
            name: 'paperDark',
            spec: StringSpec(defaultValue: '#20221F'),
          ),
          SettingField(name: 'fontFamily', spec: StringSpec()),
          SettingField(name: 'fontScale', spec: DoubleSpec(defaultValue: 1.1)),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 列表视图：手机正常、桌面多列；各设备记忆。
    // 文档未给列表视图的取值集合与栏宽数值范围，故只记录默认值形态，不加限制。
    SettingDefinition(
      id: SettingId.set008,
      title: '列表视图/桌面栏宽',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'listView',
            spec: StringSpec(defaultValue: 'normal'),
          ),
          SettingField(name: 'desktopColumnWidth', spec: IntSpec()),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 列表排序：发布时间倒序、筛选全部；返回位置按页面保留。
    SettingDefinition(
      id: SettingId.set009,
      title: '列表排序/筛选/返回位置',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'sort',
            spec: StringSpec(defaultValue: 'publishedAtDesc'),
          ),
          SettingField(
            name: 'filter',
            spec: StringSpec(defaultValue: 'all'),
          ),
          SettingField(
            name: 'rememberPosition',
            spec: BoolSpec(defaultValue: true),
          ),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 成功显示正文自动标已读：开；仅 unread→read，later 不自动变化。
    SettingDefinition(
      id: SettingId.set010,
      title: '成功显示正文自动标已读',
      spec: BoolSpec(defaultValue: true),
      classification: SettingClassification.common,
    ),
    // 翻译目标语言/生成语言：初次取界面语言后独立保存，可选中/英。
    SettingDefinition(
      id: SettingId.set011,
      title: '翻译目标语言/生成语言',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'translationTarget',
            spec: EnumSpec(
              values: _contentLanguageValues,
              defaultValue: 'zh-Hans',
            ),
          ),
          SettingField(
            name: 'generationLanguage',
            spec: EnumSpec(
              values: _contentLanguageValues,
              defaultValue: 'zh-Hans',
            ),
          ),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // 自动加载远程图片：开。
    SettingDefinition(
      id: SettingId.set012,
      title: '自动加载远程图片',
      spec: BoolSpec(defaultValue: true),
      classification: SettingClassification.device,
    ),
    // 允许计费网络下载媒体/后台请求：默认关。
    SettingDefinition(
      id: SettingId.set013,
      title: '允许计费网络下载媒体/后台请求',
      spec: BoolSpec(defaultValue: false),
      classification: SettingClassification.device,
    ),
    // 减少动态效果：跟随系统，可强制开启/关闭。
    SettingDefinition(
      id: SettingId.set014,
      title: '减少动态效果',
      spec: EnumSpec(
        values: <String>['system', 'on', 'off'],
        defaultValue: 'system',
      ),
      classification: SettingClassification.device,
    ),
    // 阅读统计：开 / 空闲暂停 5 分钟，可设 1–30。
    SettingDefinition(
      id: SettingId.set015,
      title: '阅读统计/空闲暂停时间',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'enabled', spec: BoolSpec(defaultValue: true)),
          SettingField(
            name: 'idlePauseMinutes',
            spec: IntSpec(defaultValue: 5, min: 1, max: 30),
          ),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 专注阅读布局：首发滚动；翻页在后续功能完成前不展示为可用。
    SettingDefinition(
      id: SettingId.set016,
      title: '专注阅读布局',
      spec: EnumSpec(
        values: <String>['scroll', 'paged'],
        defaultValue: 'scroll',
      ),
      classification: SettingClassification.device,
    ),

    // -----------------------------------------------------------------------
    // 6.2 订阅与刷新
    // -----------------------------------------------------------------------

    // 全局自动刷新：开 / 60 分钟；手动、15/30/60/120 分钟。
    SettingDefinition(
      id: SettingId.set020,
      title: '全局自动刷新及间隔',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'enabled', spec: BoolSpec(defaultValue: true)),
          SettingField(
            name: 'intervalMinutes',
            spec: EnumSpec(values: _refreshIntervalValues, defaultValue: '60'),
          ),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // 启动时刷新：开。
    SettingDefinition(
      id: SettingId.set021,
      title: '启动时刷新',
      spec: BoolSpec(defaultValue: true),
      classification: SettingClassification.device,
    ),
    // 单源名称/分组/启用/刷新间隔：源名称、未分类、开、继承全局。
    SettingDefinition(
      id: SettingId.set022,
      title: '单源名称/分组/启用/刷新间隔',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'name', spec: StringSpec()),
          SettingField(
            name: 'group',
            spec: StringSpec(defaultValue: 'group.uncategorized'),
          ),
          SettingField(name: 'enabled', spec: BoolSpec(defaultValue: true)),
          SettingField(
            name: 'refreshInterval',
            spec: EnumSpec(
              values: <String>['inherit', ..._refreshIntervalValues],
              defaultValue: 'inherit',
            ),
          ),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // 单源加精：关，仅显示标识。
    SettingDefinition(
      id: SettingId.set023,
      title: '单源加精',
      spec: BoolSpec(defaultValue: false),
      classification: SettingClassification.common,
    ),
    // 分组名称/排序/置顶：按创建顺序、不置顶；未分类不可删。
    SettingDefinition(
      id: SettingId.set024,
      title: '分组名称/排序/置顶',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'name', spec: StringSpec()),
          SettingField(name: 'sortOrder', spec: IntSpec(defaultValue: 0)),
          SettingField(name: 'pinned', spec: BoolSpec(defaultValue: false)),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // 分组展开/折叠：展开。
    SettingDefinition(
      id: SettingId.set025,
      title: '分组展开/折叠',
      spec: BoolSpec(defaultValue: true),
      classification: SettingClassification.device,
    ),
    // OPML 导入分组策略：默认全部未分类，可选保留文件分组。
    SettingDefinition(
      id: SettingId.set026,
      title: 'OPML 导入分组策略',
      spec: EnumSpec(
        values: <String>['uncategorized', 'keepFileGroups'],
        defaultValue: 'uncategorized',
      ),
      classification: SettingClassification.device,
    ),
    // 私密源凭据/URL 秘密参数：用户输入；秘密与可同步地址分离。
    SettingDefinition(
      id: SettingId.set027,
      title: '私密源凭据/URL 秘密参数',
      spec: StringSpec(),
      classification: SettingClassification.secret,
    ),
    // 订阅抓取并发/单源超时：高级项 4 / 30 秒；范围 1–8 / 10–120 秒。
    SettingDefinition(
      id: SettingId.set028,
      title: '订阅抓取并发/单源超时',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'concurrency',
            spec: IntSpec(defaultValue: 4, min: 1, max: 8),
          ),
          SettingField(
            name: 'timeoutSeconds',
            spec: IntSpec(defaultValue: 30, min: 10, max: 120),
          ),
        ],
      ),
      classification: SettingClassification.device,
    ),

    // -----------------------------------------------------------------------
    // 6.3 AI 与搜索服务
    // -----------------------------------------------------------------------

    // AI 提供商预设/协议/Base URL/别名：无，手动添加。
    SettingDefinition(
      id: SettingId.set030,
      title: 'AI 提供商预设/协议/Base URL/别名',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'preset', spec: StringSpec()),
          SettingField(name: 'protocol', spec: StringSpec()),
          SettingField(name: 'baseUrl', spec: StringSpec()),
          SettingField(name: 'alias', spec: StringSpec()),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // AI API Key/认证秘密：遮盖，可替换/删除/显示；不写日志。
    SettingDefinition(
      id: SettingId.set031,
      title: 'AI API Key/认证秘密',
      spec: StringSpec(),
      classification: SettingClassification.secret,
    ),
    // 模型 ID/启用/排序/删除：列表失败可手填；依排序故障转移。
    SettingDefinition(
      id: SettingId.set032,
      title: '模型 ID/启用/排序/删除',
      spec: StringListSpec(),
      classification: SettingClassification.common,
    ),
    // 模型能力与上下文/输出上限：未知上下文用保守 8192 预算、输出 2048。
    SettingDefinition(
      id: SettingId.set033,
      title: '模型能力与上下文/输出上限',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'contextBudget',
            spec: IntSpec(defaultValue: 8192),
          ),
          SettingField(name: 'outputBudget', spec: IntSpec(defaultValue: 2048)),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // 专用视觉模型：未设置。
    SettingDefinition(
      id: SettingId.set034,
      title: '专用视觉模型',
      spec: StringSpec(),
      classification: SettingClassification.common,
    ),
    // 故障转移及允许目标：开，在已启用/已告知的模型列表内。
    SettingDefinition(
      id: SettingId.set035,
      title: '故障转移及允许目标',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'enabled', spec: BoolSpec(defaultValue: true)),
          SettingField(name: 'allowedModels', spec: StringListSpec()),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // AI 并发/首响应超时/流停滞超时：2 / 45 秒 / 30 秒；范围 1–4 / 10–120 / 10–120。
    SettingDefinition(
      id: SettingId.set036,
      title: 'AI 并发/首响应超时/流停滞超时',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'concurrency',
            spec: IntSpec(defaultValue: 2, min: 1, max: 4),
          ),
          SettingField(
            name: 'firstResponseSeconds',
            spec: IntSpec(defaultValue: 45, min: 10, max: 120),
          ),
          SettingField(
            name: 'streamStallSeconds',
            spec: IntSpec(defaultValue: 30, min: 10, max: 120),
          ),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 缺摘要时自动 AI 摘要：默认关。
    SettingDefinition(
      id: SettingId.set037,
      title: '缺摘要时自动 AI 摘要',
      spec: BoolSpec(defaultValue: false),
      classification: SettingClassification.common,
    ),
    // 搜索服务协议/端点/排序/启用：无，用户配置。
    SettingDefinition(
      id: SettingId.set038,
      title: '搜索服务协议/端点/排序/启用',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'protocol', spec: StringSpec()),
          SettingField(name: 'endpoint', spec: StringSpec()),
          SettingField(name: 'sort', spec: StringSpec()),
          SettingField(name: 'enabled', spec: BoolSpec(defaultValue: false)),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // 搜索 API Key/实例认证：与 AI 凭据分开管理。
    SettingDefinition(
      id: SettingId.set039,
      title: '搜索 API Key/实例认证',
      spec: StringSpec(),
      classification: SettingClassification.secret,
    ),
    // 每次搜索结果数/单次超时：10 / 20 秒；范围 1–20 / 5–60 秒。
    SettingDefinition(
      id: SettingId.set040,
      title: '每次搜索结果数/单次超时',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'maxResults',
            spec: IntSpec(defaultValue: 10, min: 1, max: 20),
          ),
          SettingField(
            name: 'timeoutSeconds',
            spec: IntSpec(defaultValue: 20, min: 5, max: 60),
          ),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // 允许指定内网/HTTP 服务端点：默认无；每端点显式批准。
    SettingDefinition(
      id: SettingId.set041,
      title: '允许指定内网/HTTP 服务端点',
      spec: StringListSpec(),
      classification: SettingClassification.device,
    ),
    // 连通性/最小生成/搜索测试：操作，不是持久设置。
    SettingDefinition(
      id: SettingId.set042,
      title: '连通性/最小生成/搜索测试',
      spec: ActionSpec(),
      classification: SettingClassification.device,
      isPersistent: false,
    ),

    // -----------------------------------------------------------------------
    // 6.4 新闻生成、prompt 与资源预算
    // -----------------------------------------------------------------------

    // RSS 内容总开关/逐源开关：总开/已启用订阅默认开。
    SettingDefinition(
      id: SettingId.set050,
      title: 'RSS 内容总开关/逐源开关',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'globalEnabled',
            spec: BoolSpec(defaultValue: true),
          ),
          SettingField(
            name: 'perFeedEnabled',
            spec: BoolSpec(defaultValue: true),
          ),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // 必访问网站列表：空。
    SettingDefinition(
      id: SettingId.set051,
      title: '必访问网站列表',
      spec: StringListSpec(),
      classification: SettingClassification.common,
    ),
    // 联网搜索关键词列表：空。
    SettingDefinition(
      id: SettingId.set052,
      title: '联网搜索关键词列表',
      spec: StringListSpec(),
      classification: SettingClassification.common,
    ),
    // 禁止发送的查询词/排除内容主题：两个独立列表，默认空。
    SettingDefinition(
      id: SettingId.set053,
      title: '禁止发送的查询词/排除内容主题',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'blockedQueryTerms', spec: StringListSpec()),
          SettingField(name: 'excludedTopics', spec: StringListSpec()),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // 输出规范 prompt/重置：内置带来源的中/英模板；这里存用户覆盖，默认无。
    SettingDefinition(
      id: SettingId.set054,
      title: '输出规范 prompt/重置',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'promptZh', spec: StringSpec()),
          SettingField(name: 'promptEn', spec: StringSpec()),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // 总体任务说明/总 prompt 模式：默认自动组合；高级覆盖需显式切换。
    SettingDefinition(
      id: SettingId.set055,
      title: '总体任务说明/总 prompt 模式',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'mode',
            spec: EnumSpec(
              values: <String>['composed', 'advancedOverride'],
              defaultValue: 'composed',
            ),
          ),
          SettingField(name: 'advancedPrompt', spec: StringSpec()),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // 本设备自动定时总结：默认开；未配置/未完成首次告知时等待。
    SettingDefinition(
      id: SettingId.set056,
      title: '本设备自动定时总结',
      spec: BoolSpec(defaultValue: true),
      classification: SettingClassification.device,
    ),
    // 每日执行时间：20:00，按当前设备时区。
    SettingDefinition(
      id: SettingId.set057,
      title: '每日执行时间',
      spec: StringSpec(
        defaultValue: '20:00',
        pattern: r'^([01]\d|2[0-3]):[0-5]\d$',
        patternHint: '需要 HH:mm 24 小时制时间',
      ),
      classification: SettingClassification.common,
    ),
    // 新闻时区：只读「跟随设备」；每个结果保存任务时区。
    SettingDefinition(
      id: SettingId.set058,
      title: '新闻时区',
      spec: StringSpec(),
      classification: SettingClassification.device,
      isReadOnly: true,
    ),
    // 每任务总时限：10 分钟，允许 1–60。
    SettingDefinition(
      id: SettingId.set059,
      title: '每任务总时限',
      spec: IntSpec(defaultValue: 10, min: 1, max: 60),
      classification: SettingClassification.common,
    ),
    // 每任务最多输入文章/必访站/搜索查询：50 / 10 / 10，可到 200 / 30 / 30。
    // 文档只给上界与默认值，未给下界；用 0 作为「不变量下界」以避免负值，
    // 0 表示该来源不参与本次任务。
    SettingDefinition(
      id: SettingId.set060,
      title: '每任务最多输入文章/必访站/搜索查询',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'maxArticles',
            spec: IntSpec(defaultValue: 50, min: 0, max: 200),
          ),
          SettingField(
            name: 'maxSites',
            spec: IntSpec(defaultValue: 10, min: 0, max: 30),
          ),
          SettingField(
            name: 'maxQueries',
            spec: IntSpec(defaultValue: 10, min: 0, max: 30),
          ),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // 单材料文本预算：默认 8000 字符；长文分块或标截断。
    SettingDefinition(
      id: SettingId.set061,
      title: '单材料文本预算',
      spec: IntSpec(defaultValue: 8000),
      classification: SettingClassification.common,
    ),
    // 工具调用总次数/模型 HTTP 尝试总数：30 / 30。
    SettingDefinition(
      id: SettingId.set062,
      title: '工具调用总次数/模型 HTTP 尝试总数',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'toolCalls', spec: IntSpec(defaultValue: 30)),
          SettingField(name: 'httpAttempts', spec: IntSpec(defaultValue: 30)),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // 每任务累计输入+输出 Token 预算：100000 估算上限。
    SettingDefinition(
      id: SettingId.set063,
      title: '每任务累计输入+输出 Token 预算',
      spec: IntSpec(defaultValue: 100000),
      classification: SettingClassification.common,
    ),
    // 当天自动摘要任务数：50。
    SettingDefinition(
      id: SettingId.set064,
      title: '当天自动摘要任务数',
      spec: IntSpec(defaultValue: 50),
      classification: SettingClassification.common,
    ),
    // 图像分析开关/最多图片/单图上传上限：开 / 6 / 4 MiB。
    SettingDefinition(
      id: SettingId.set065,
      title: '图像分析开关/最多图片/单图上传上限',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'enabled', spec: BoolSpec(defaultValue: true)),
          SettingField(name: 'maxImages', spec: IntSpec(defaultValue: 6)),
          SettingField(name: 'maxImageMiB', spec: IntSpec(defaultValue: 4)),
        ],
      ),
      classification: SettingClassification.common,
    ),
    // 模型单价与费用提醒：默认未知，不展示伪精确金额；用户可填参考价格。
    SettingDefinition(
      id: SettingId.set066,
      title: '模型单价与费用提醒',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'unitPrices', spec: StringListSpec()),
          SettingField(
            name: 'costWarningEnabled',
            spec: BoolSpec(defaultValue: false),
          ),
        ],
      ),
      classification: SettingClassification.common,
    ),

    // -----------------------------------------------------------------------
    // 6.5 同步、备份、存储与关于
    // -----------------------------------------------------------------------

    // WebDAV URL/用户/远端目录/设备名：未配置；远端独立目录 flux-v1。
    SettingDefinition(
      id: SettingId.set070,
      title: 'WebDAV URL/用户/远端目录/设备名',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'url', spec: StringSpec()),
          SettingField(name: 'username', spec: StringSpec()),
          SettingField(
            name: 'remoteDirectory',
            spec: StringSpec(defaultValue: 'flux-v1'),
          ),
          SettingField(name: 'deviceName', spec: StringSpec()),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // WebDAV 密码/Token：安全存储；不得写进同步包或明文备份。
    SettingDefinition(
      id: SettingId.set071,
      title: 'WebDAV 密码/Token',
      spec: StringSpec(),
      classification: SettingClassification.secret,
    ),
    // 同步启用/启动同步/变更后同步：未配置时关；配置成功后启动开、防抖 5 秒开。
    SettingDefinition(
      id: SettingId.set072,
      title: '同步启用/启动同步/变更后同步',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'enabled', spec: BoolSpec(defaultValue: false)),
          SettingField(name: 'syncOnStart', spec: BoolSpec(defaultValue: true)),
          SettingField(
            name: 'syncOnChange',
            spec: BoolSpec(defaultValue: true),
          ),
          SettingField(
            name: 'changeDebounceSeconds',
            spec: IntSpec(defaultValue: 5),
          ),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 自动同步间隔/手动同步：30 分钟，可设 5–1440 或仅手动。
    SettingDefinition(
      id: SettingId.set073,
      title: '自动同步间隔/手动同步',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'intervalMinutes',
            spec: IntSpec(defaultValue: 30, min: 5, max: 1440),
          ),
          SettingField(name: 'manualOnly', spec: BoolSpec(defaultValue: false)),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 共通设置/阅读状态同步范围：默认都开；凭据和设备项永远排除。
    SettingDefinition(
      id: SettingId.set074,
      title: '共通设置/阅读状态同步范围',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'commonSettings',
            spec: BoolSpec(defaultValue: true),
          ),
          SettingField(
            name: 'readingState',
            spec: BoolSpec(defaultValue: true),
          ),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 首次同步/冲突处理：首次预览合并，不默认覆盖；同字段并发人工选版。
    SettingDefinition(
      id: SettingId.set075,
      title: '首次同步/冲突处理',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'firstSyncPreview',
            spec: BoolSpec(defaultValue: true),
          ),
          SettingField(
            name: 'conflictPolicy',
            spec: EnumSpec(
              values: <String>['manual', 'preferLocal', 'preferRemote'],
              defaultValue: 'manual',
            ),
          ),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 导出明文备份/是否含媒体/恢复：默认不含媒体；秘密永不包含。
    SettingDefinition(
      id: SettingId.set076,
      title: '导出明文备份/是否含媒体/恢复',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'includeMedia',
            spec: BoolSpec(defaultValue: false),
          ),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 媒体/文章/总结自动清理开关与天数：默认全关；启用后预填 30/90/365，范围 1–3650。
    SettingDefinition(
      id: SettingId.set077,
      title: '媒体/文章/总结自动清理开关与天数',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'mediaEnabled',
            spec: BoolSpec(defaultValue: false),
          ),
          SettingField(
            name: 'mediaDays',
            spec: IntSpec(defaultValue: 30, min: 1, max: 3650),
          ),
          SettingField(
            name: 'articleEnabled',
            spec: BoolSpec(defaultValue: false),
          ),
          SettingField(
            name: 'articleDays',
            spec: IntSpec(defaultValue: 90, min: 1, max: 3650),
          ),
          SettingField(
            name: 'summaryEnabled',
            spec: BoolSpec(defaultValue: false),
          ),
          SettingField(
            name: 'summaryDays',
            spec: IntSpec(defaultValue: 365, min: 1, max: 3650),
          ),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 自动清理包含收藏/稍后再读：两项默认否。
    SettingDefinition(
      id: SettingId.set078,
      title: '自动清理包含收藏/稍后再读',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'includeFavorite',
            spec: BoolSpec(defaultValue: false),
          ),
          SettingField(
            name: 'includeLater',
            spec: BoolSpec(defaultValue: false),
          ),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 清理预览/一键清缓存/占用刷新：操作，不是持久设置。
    SettingDefinition(
      id: SettingId.set079,
      title: '清理预览/一键清缓存/占用刷新',
      spec: ActionSpec(),
      classification: SettingClassification.device,
      isPersistent: false,
    ),
    // 媒体缓存上限：512 MiB，允许 128–4096。
    SettingDefinition(
      id: SettingId.set080,
      title: '媒体缓存上限',
      spec: IntSpec(defaultValue: 512, min: 128, max: 4096),
      classification: SettingClassification.device,
    ),
    // 删除订阅是否保留收藏：每次询问，默认选保留。
    SettingDefinition(
      id: SettingId.set081,
      title: '删除订阅是否保留收藏',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'policy',
            spec: EnumSpec(
              values: <String>['ask', 'alwaysKeep', 'alwaysDelete'],
              defaultValue: 'ask',
            ),
          ),
          SettingField(
            name: 'defaultChoice',
            spec: EnumSpec(
              values: <String>['keep', 'delete'],
              defaultValue: 'keep',
            ),
          ),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 诊断日志级别/保留天数：error / 7 天、总量上限 10 MiB。
    SettingDefinition(
      id: SettingId.set082,
      title: '诊断日志级别/保留天数',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'level',
            spec: EnumSpec(values: _logLevelValues, defaultValue: 'error'),
          ),
          SettingField(
            name: 'retentionDays',
            spec: IntSpec(defaultValue: 7, min: 1),
          ),
          SettingField(
            name: 'maxTotalMiB',
            spec: IntSpec(defaultValue: 10, min: 1),
          ),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 检查更新/发布通道：GitHub，手动检查；不自动安装。
    SettingDefinition(
      id: SettingId.set083,
      title: '检查更新/发布通道',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(
            name: 'channel',
            spec: EnumSpec(values: <String>['github'], defaultValue: 'github'),
          ),
          SettingField(name: 'autoCheck', spec: BoolSpec(defaultValue: false)),
        ],
      ),
      classification: SettingClassification.device,
    ),
    // 版本/GitHub/Issue/开发者/贡献者/许可：只读发布元数据；不存在 URL 不伪造。
    SettingDefinition(
      id: SettingId.set084,
      title: '版本/GitHub/Issue/开发者/贡献者/许可',
      spec: CompositeSpec(
        fields: <SettingField>[
          SettingField(name: 'version', spec: StringSpec()),
          SettingField(name: 'repositoryUrl', spec: StringSpec()),
          SettingField(name: 'issueUrl', spec: StringSpec()),
          SettingField(name: 'license', spec: StringSpec()),
        ],
      ),
      classification: SettingClassification.device,
      isReadOnly: true,
    ),
  ];

  /// 编号 → 定义。
  static final Map<String, SettingDefinition> _byCode =
      <String, SettingDefinition>{
        for (final SettingDefinition definition in all)
          definition.id.code: definition,
      };

  /// 按编号取定义；未注册时返回 null（调用方决定报错或忽略）。
  static SettingDefinition? find(String code) => _byCode[code];

  /// 按 [id] 取定义；未注册时返回 null。
  static SettingDefinition? findById(SettingId id) => _byCode[id.code];

  /// 该编号是否已注册。
  static bool contains(String code) => _byCode.containsKey(code);

  /// 全部秘密项（S 类）。
  static Iterable<SettingDefinition> get secrets =>
      all.where((SettingDefinition definition) => definition.isSecret);

  /// 按分类筛选，用于同步投影与设置页分组。
  static Iterable<SettingDefinition> withClassification(
    SettingClassification classification,
  ) => all.where(
    (SettingDefinition definition) =>
        definition.classification == classification,
  );

  /// 可持久化的设置项（排除文档明确标为「操作」的编号）。
  static Iterable<SettingDefinition> get persistent =>
      all.where((SettingDefinition definition) => definition.isPersistent);

  /// 可进入**普通**设置存储的项：可持久化且不是秘密。
  ///
  /// 秘密项走 Keychain（见 CredentialStore），不得写进 settings 表；
  /// 这不是「方便性问题」，而是架构第 8 节「数据恢复不能退回明文秘密存储」
  /// 的一部分：明文表会被备份/同步带走。
  static Iterable<SettingDefinition> get storable => all.where(
    (SettingDefinition definition) =>
        definition.isPersistent && !definition.isSecret,
  );
}
