// 国际化测试（T011，架构第 2.1 节「类型化设置 + zh-CN/en 资源」）。
//
// 断言三件事：
//   1) ARB 与生成物一致：中文原文的每个 key 都有英文译文，且占位符集合相同
//      （缺译文会让 gen_l10n 报错，但「占了位却漏了一步」只有直接比对才能发现）；
//   2) SET-001 的三种取值解析正确，且 system 必须解析为 null（交给系统），
//      不能被预解析成某个固定语言；
//   3) 「界面语言变化不重写历史 AI 输出」在本期的落点是：语言切换只影响
//      Localizations，不触碰任何存储写入路径（见 settings_page_test 的断言）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/l10n/l10n.dart';

/// 中文原文资源路径（相对包根）。
const String zhArbPath = 'lib/l10n/app_zh.arb';

/// 英文译文资源路径。
const String enArbPath = 'lib/l10n/app_en.arb';

/// 读取一个 ARB 文件。
Map<String, Object?> _readArb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

/// 消息键（去掉 @@locale 与 @元数据条目）。
Set<String> _messageKeys(Map<String, Object?> arb) =>
    arb.keys.where((String key) => !key.startsWith('@')).toSet();

/// 提取一个消息里的占位符名集合。
Set<String> _placeholders(Object? value) {
  final Iterable<RegExpMatch> matches = RegExp(r'\{(\w+)\}')
      .allMatches(value is String ? value : '');
  return matches.map((RegExpMatch match) => match.group(1)!).toSet();
}

void main() {
  group('ARB 资源', () {
    final Map<String, Object?> zh = _readArb(zhArbPath);
    final Map<String, Object?> en = _readArb(enArbPath);

    test('中英 key 集合完全一致，且 T011 覆盖的条目都在', () {
      final Set<String> zhKeys = _messageKeys(zh);
      final Set<String> enKeys = _messageKeys(en);
      expect(enKeys.difference(zhKeys), isEmpty, reason: '英文多出的 key');
      expect(zhKeys.difference(enKeys), isEmpty, reason: '英文缺少的 key');

      // T011 要求覆盖的类别逐项点名，避免「文件非空就算过」。
      for (final String key in <String>[
        'appName',
        'navToday',
        'navReading',
        'navMine',
        'onboardingWelcomeTitle',
        'onboardingFeedsTitle',
        'onboardingAiTitle',
        'settingsLanguageLabel',
        'settingsThemeLabel',
        'settingsOptionFollowSystem',
        'emptyNoFeedsTitle',
        'emptyAllReadTitle',
        'emptyNoResultsTitle',
      ]) {
        expect(zhKeys, contains(key), reason: '中文缺少 $key');
        expect(enKeys, contains(key), reason: '英文缺少 $key');
      }
    });

    test('同一 key 的占位符集合一致（漏传参数只会在运行时炸）', () {
      for (final String key in _messageKeys(zh)) {
        expect(
          _placeholders(en[key]),
          _placeholders(zh[key]),
          reason: 'key=$key 的占位符不一致',
        );
      }
    });

    test('SET-003–016 的界面文案齐备（T011 要求基础设置页文案）', () {
      final Set<String> zhKeys = _messageKeys(zh);
      for (int index = 3; index <= 16; index++) {
        final String suffix = index.toString().padLeft(3, '0');
        expect(
          zhKeys,
          contains('settingsItemSet$suffix'),
          reason: '缺少 SET-$suffix 的中文标题',
        );
      }
      // SET-001/002 有专门的 label/id/hint 条目。
      for (final String key in <String>[
        'settingsLanguageLabel',
        'settingsLanguageId',
        'settingsLanguageHint',
        'settingsThemeLabel',
        'settingsThemeId',
        'settingsThemeHint',
      ]) {
        expect(zhKeys, contains(key));
      }
    });

    test('空态、关于与首启文案齐备（占位页文案已随占位页删除）', () {
      final Set<String> zhKeys = _messageKeys(zh);
      for (final String key in <String>[
        'emptyNoFeedsTitle',
        'emptyNoFeedsBody',
        'emptyAllReadTitle',
        'emptyAllReadBody',
        'emptyNoResultsTitle',
        'emptyNoResultsBody',
        'todayNoVersionTitle',
        'todayNoVersionBody',
        'onboardingStepIndicator',
        'onboardingSkip',
        'onboardingNext',
        'onboardingStart',
        'aboutVersionLabel',
        'aboutLicenseLabel',
        'aboutRepositoryLabel',
        'aboutNotConfigured',
      ]) {
        expect(zhKeys, contains(key), reason: '缺少 $key');
      }
    });

    test('条目数量与生成类一致（生成物来自当前 ARB）', () {
      expect(
        AppLocalizations.supportedLocales.map(
          (Locale locale) => locale.languageCode,
        ),
        containsAll(<String>['zh', 'en']),
      );
      // 105 条消息（T011 交付 90 条，T012 新增 15 条共享控件文案）；
      // 数量变化必须显式改这里，避免 ARB 被误删条目而无人察觉。
      // T014 新增 82 条订阅管理文案（添加/预览/分组/刷新策略/排序可达性/保留组名）。
      // T015 新增 39 条 OPML 导入/导出文案（选文件/预览/策略/结果/重试/导出/秘密提示）。
      // T016 新增 14 条刷新结果文案（四类结果、离线与计费网络说明、失败）；
      // T017 新增 28 条阅读文案（筛选四项、来源筛选、空态、分页、批量范围与操作、
      // 详情占位说明、操作失败与列表读取失败）。
      // T018 新增 19 条删除文案（影响预览三行、保留收藏选项、两种回执、分组影响、
      // 已脱离订阅标注）；T019 新增 35 条正文阅读文案（完整性四态与仅摘要说明、目录、
      // 上下篇与边界、页内查找、代码块复制与折叠、公式回退、图片占位、外链与范围说明、
      // 未解析块提示、作者行、返回按钮）。
      // T019+ 新增 2 条列表分批加载文案（已加载计数、加载更多）。
      // T020 新增 25 条选区/复制全文/链接面板/图片查看与保存/系统分享文案。
      // T021 新增 3 条图片缓存文案（重试、内网地址被拦、超过单图上限），并把
      // T019 的图片占位说明改为「按需加载并缓存」的当前口径。
      // T022 新增 15 条检索文案（搜索框、范围、三种空态、失败与重试、命中计数）。
      // T023 新增 35 条统计文案（页面标题、热力图与图例、工具提示、七日柱状图、
      // 星期与日期标签、清空确认与回执、开关与空闲暂停、空态与估计值说明）＋ T024
      // 新增 13 条原站静态全文文案（入口、加载、成功、失败、原文/提取切换、付费墙与
      // JS 站提示、外开、无地址、无脚本说明）——两者同轮交付，因此一起计入。
      // T025 新增 75 条 AI 服务文案（入口、页面、模型表单四项 SET、能力五项、
      // 预算说明、Key 遮盖与状态、费用确认、12 类失败文案、删除与引用确认）。
      // T028 新增 13 条预设文案（预设下拉与自定义项、端点预览、三档状态徽章与
      // 各自说明、验证矩阵标题与「不夸大状态」提示、无实测提示）。
      // T030 新增 24 条 AI 任务记录文案（页面标题与设置入口、空态与读取失败、
      // 重新开始按钮与其两条边界（活跃态禁用、成功回执）、命中缓存标注、任务元信息，
      // 以及九态与五种任务类型的展示名）。
      // T033 新增 17 条视觉文案（图片分析入口、首次发送告知标题/正文/确认/取消、
      // 分析结果面板标题与进行中、降采样说明、数据去向、无视觉模型/开关关闭/图片
      // 拿不到/失败四种说明、关闭按钮、取消分析与回执）。
      // T031 新增 43 条搜索服务文案（页面标题与设置入口、列表小节与排序说明、
      // 空态与读取失败、默认徽章与开关、预算说明与内网已批准标注、缺凭据提示与
      // 测试禁用原因、费用与数据发送确认框四句、成功回执、删除确认四句与失败、
      // 服务表单字段与提示（服务名/协议/端点/凭据三种状态/结果数/超时/内网批准）、
      // 以及未实现部分的说明）。
      // T035 新增 23 条翻译文案（入口与面板标题、进度与完成/部分成功回执、取消与
      // 重试失败段、失败段说明、原文/译文切换与「原文始终保留」、截断与过期说明、
      // 仅摘要/无正文/无模型/无可翻译块四种跳过，以及译文来源标注与目标语言）。
      // T036 新增 59 条新闻来源文案（设置入口与页面标题、读取失败、总开关、逐源三态、
      // 必访站编辑器、三个列表编辑器、prompt 模式两态与两段说明、任务/规范/高级三块、
      // 固定协议标题、恢复默认、保存版本与版本列表、差异两条、生效查询与预览，以及
      // 未实现说明）。
      // T038 新增 53 条今日页文案（日期切换与前一天/后一天、生成与再生成与取消、
      // 六个阶段名、空态两条、材料数与退回条数、必访站四种状态、四个证据标签与
      // 标签说明、引用三种获取方式与本机/外开/缺字段/未知引用五条、版本列表与
      // 切换四句、初稿/核验后两个标记、模型与核验方法两条、费用确认四句、
      // 生成失败与成功两条、缺输入与总开关关闭两条，以及底部说明），
      // 并删除 11 条随「壳层占位页」一起消失的文案（milestoneShellNotice /
      // placeholderBadge / layoutShellNote / 三个栏位名 / 三个断点名 /
      // todayEmptyTitle / todayEmptyBody）：701 - 11 + 53 = 743。
      // T039 新增 31 条今日页产品化文案（近 7 天与日历入口、今天标记、历史日期
      // 归属说明、生成中的逐站进度三条、取消中、九态状态说明八条与中止阶段一句、
      // 无可用结果一句、版本条目（含时间与模型/模型未记录）与删除六句、删除回执
      // 两条、引用已清理三条）：743 + 31 = 774。
      // T040 新增 25 条定时文案（小节标题、SET-056 开关与说明、SET-057 时间与说明与保存
      // 回执与选择器标题、下次运行/今日已完成/正在运行/已关闭四条状态、等待配置的标题与
      // 五种原因、费用告知正文与确认与回执与失败、缺搜索提示、上次运行失败、中断说明）：
      // 774 + 25 = 799。
      // T044 新增 78 条同步文案（设置入口、服务器四项 SET-070/071、四种地址校验说明、
      // 只读探测说明与三种结论、触发四种（SET-072/073）、范围（SET-074）四条清单说明、
      // 状态七条、同步结论五种、降级提示、首次合并六条、冲突五条、远端删除两条、
      // 保存失败）：799 + 78 = 877。
      // T045 新增 9 条跨设备删除文案（远端删除确认按钮、保留收藏选项、影响范围
      // （文章/收藏/其余/later 四个数字）、无文章说明、不可应用说明与原因、应用回执、
      // 预览失败，以及占位行的「正文尚未同步」详情说明与徽标）：877 + 9 = 886。
      // T046 新增 18 条备份与恢复文案（小节标题、明文风险告知、含媒体开关、导出/恢复
      // 两个按钮、导出回执、导出前风险确认标题与按钮与取消、恢复预检标题与信息行、
      // 含/不含媒体两种说明、二次确认正文与按钮、恢复完成回执、失败回执与保存路径）：
      // 886 + 18 = 904。
      expect(_messageKeys(zh).length, 904);
      expect(_messageKeys(en).length, 904);
    });

    test('T012 共享控件文案齐备（三态、收藏、加精、控件状态）', () {
      final Set<String> zhKeys = _messageKeys(zh);
      for (final String key in <String>[
        'readingStateLabel',
        'readingStateUnread',
        'readingStateRead',
        'readingStateLater',
        'readingStateControlHint',
        'readingStateSwitched',
        'favoriteToggleLabel',
        'favoriteAddLabel',
        'favoriteRemoveLabel',
        'favoriteToggleHint',
        'featuredBadgeLabel',
        'controlLoadingLabel',
        'controlSuccessLabel',
        'controlErrorLabel',
        'controlDisabledLabelSuffix',
      ]) {
        expect(zhKeys, contains(key), reason: '缺少 $key');
        expect(_messageKeys(en), contains(key), reason: '英文缺少 $key');
      }
    });
    test('T014 订阅管理文案齐备（添加/预览/分组/排序/刷新策略）', () {
      final Set<String> zhKeys = _messageKeys(zh);
      for (final String key in <String>[
        'subscriptionManagerTitle',
        'subscriptionAddFeedTitle',
        'subscriptionFeedUrlLabel',
        'subscriptionPreviewTitle',
        'subscriptionPreviewDuplicateTitle',
        'subscriptionConfirmAdd',
        'subscriptionSave',
        'subscriptionNewGroupTitle',
        'subscriptionGroupRename',
        'subscriptionGroupDelete',
        'subscriptionGroupDeleteMoveOption',
        'subscriptionGroupDeleteFeedsOption',
        'subscriptionGroupDeleteFeedsHint',
        'subscriptionReservedGroupNote',
        'subscriptionReservedGroupName',
        'subscriptionFeedEnable',
        'subscriptionFeedDisable',
        'subscriptionFeedFavorite',
        'subscriptionGlobalRefreshLabel',
        'subscriptionStartupRefreshLabel',
        'subscriptionReorderHint',
        'subscriptionDragHandleLabel',
      ]) {
        expect(zhKeys, contains(key), reason: '缺少 $key');
        expect(_messageKeys(en), contains(key), reason: '英文缺少 $key');
      }
    });
  });

  group('SET-001 语言解析', () {
    test('三种取值：system → null（交给系统）、zh-Hans → zh、en → en', () {
      expect(AppLanguageSetting.resolveLocale('system'), isNull);
      expect(AppLanguageSetting.resolveLocale('zh-Hans'), const Locale('zh'));
      expect(AppLanguageSetting.resolveLocale('en'), const Locale('en'));
    });

    test('未知取值按跟随系统处理，不锁定到某个使用者没选过的语言', () {
      expect(AppLanguageSetting.resolveLocale('fr'), isNull);
      expect(AppLanguageSetting.resolveLocale(''), isNull);
      expect(AppLanguageSetting.resolveLocale('ZH-hans'), isNull);
    });

    test('取值清单与 SET-001 注册表口径一致', () {
      expect(AppLanguageSetting.values, <String>['system', 'zh-Hans', 'en']);
    });

    test('无匹配语言回退英文（SET-001）', () {
      expect(fallbackLocale, const Locale('en'));
    });

    test('describe 输出稳定标签，便于诊断日志（不含用户内容）', () {
      expect(AppLanguageSetting.describe('system'), 'system');
      expect(AppLanguageSetting.describe('zh-Hans'), 'zh');
      expect(AppLanguageSetting.describe('en'), 'en');
    });
  });
}
