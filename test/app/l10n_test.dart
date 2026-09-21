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
        'milestoneShellNotice',
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

    test('占位页、空态、关于与首启文案齐备', () {
      final Set<String> zhKeys = _messageKeys(zh);
      for (final String key in <String>[
        'placeholderBadge',
        'placeholderPageBody',
        'emptyNoFeedsTitle',
        'emptyNoFeedsBody',
        'emptyAllReadTitle',
        'emptyAllReadBody',
        'emptyNoResultsTitle',
        'emptyNoResultsBody',
        'todayEmptyTitle',
        'todayEmptyBody',
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
      expect(_messageKeys(zh).length, 335);
      expect(_messageKeys(en).length, 335);
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
