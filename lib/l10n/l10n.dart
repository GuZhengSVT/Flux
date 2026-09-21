// l10n：中英文界面资源（架构第 2.1、7 节）。
//
// T011 落地官方 gen_l10n 方案：
//   - 原文与译文在 app_zh.arb / app_en.arb，配置在仓库根 l10n.yaml；
//   - 生成物在 lib/l10n/generated/（由 flutter pub get / build / test 自动运行，
//     ARB 与生成物不会不同步）；
//   - 本文件只做一件事：把生成类与「应用 locale 解析规则」收成一个稳定入口，
//     让 app 层与测试不需要各自记生成物的路径。
//
// 界面语言（SET-001）的三种取值与解析规则：
//   system  → 交给 MaterialApp.locale = null，由 Flutter 按系统语言解析；
//   zh-Hans → 固定 Locale('zh')；
//   en      → 固定 Locale('en')。
// 「没有匹配回退英文」由 supportedLocales 的顺序保证（见 supportedLocales）。
//
// 注意：界面语言变化不重写历史 AI 输出。本文件只负责 UI 文案的解析，不参与
// 任何 AI 结果的存储或翻译（那属于 T035，且必须保留原文）。
library;

import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

/// 应用名（不含本地化，用于窗口标题与调试日志的稳定标识）。
const String fluxAppName = 'Flux';

/// 界面语言设置（SET-001）的稳定取值。
abstract final class AppLanguageSetting {
  /// 跟随系统。
  static const String system = 'system';

  /// 简体中文。
  static const String chinese = 'zh-Hans';

  /// 英文。
  static const String english = 'en';

  /// 全部取值，顺序即设置页展示顺序。
  static const List<String> values = <String>[system, chinese, english];

  /// 把设置值解析为 MaterialApp 的 locale。
  ///
  /// 返回 null 表示「交给系统解析」——这不是「没有值」，而是 SET-001 中
  /// system 的明确语义：各设备自行解析，因此不能在这里预解析成某个固定语言。
  static Locale? resolveLocale(String setting) {
    switch (setting) {
      case chinese:
        return const Locale('zh');
      case english:
        return const Locale('en');
      case system:
      default:
        // 未知取值按「跟随系统」处理，与 SET-001 默认值一致，避免一个损坏的
        // 设置值让界面停在某个使用者没选过的语言上。
        return null;
    }
  }

  /// 解析后的语言标签（用于诊断日志；不写入任何用户内容）。
  static String describe(String setting) =>
      resolveLocale(setting)?.languageCode ?? 'system';
}

/// 应用支持的 locale 列表。
///
/// 顺序有意义：中文在前时，zh-Hant/zh-HK 等「同语言但未精确支持」的系统语言
/// 会被 Flutter 匹配到 zh；而任何完全无法匹配的语言（例如 fr）会回退到列表
/// **第一个**条目。SET-001 明确要求「无匹配回退英文」，因此列表顺序不能用来
/// 表达偏好，回退语言单独由 [fallbackLocale] 指定。
List<Locale> get supportedLocales => AppLocalizations.supportedLocales;

/// 无匹配语言时的回退 locale（SET-001：无匹配回退英文）。
///
/// 注意：这里有意**不**从系统语言推断。用户若把界面语言设为简体中文，即使
/// 系统是法语也必须显示中文——那是显式选择，不属于「无匹配回退」。
const Locale fallbackLocale = Locale('en');
