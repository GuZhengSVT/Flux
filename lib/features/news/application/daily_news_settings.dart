// 定时总结的设置读取与就绪判定（T040；SET-056/057/050、D-08）。
//
// 「就绪」与「到点」是两件不同的事，因此分在两个文件里：时间规则是纯函数
// （core/domain/news_schedule.dart），而「能不能真的跑」需要读模型列表、凭据、搜索服务与
// 费用告知记录——这些都带 IO，且每一项的缺失都对应一句**不同的**界面说明（缺模型 vs
// 缺 Key vs 没配搜索 vs 没确认费用）。把它们合成一个 bool 会让用户看到「等待配置」却
// 不知道该去配什么。
library;

import 'package:flux/core/core.dart';

import 'package:flux/features/ai/application/model_manager.dart';
import 'package:flux/features/ai/domain/ai_credential_store.dart';
import 'package:flux/features/ai/domain/ai_model.dart';

import 'daily_news_scheduler.dart';
import 'news_run_service.dart';

/// 定时策略的读取端口（SET-056/057 + 当前设备时区）。
///
/// 做成端口而不是直接读设置：策略要「读两个编号 + 取一次设备时区」三件事一起完成，而
/// 每项都可能失败。让调度器拿到一个 `Result<DailyNewsPolicy>`，比让它在三个读操作之间
/// 自己拼错误语义更不容易漂移。
final class NewsDailySettings {
  /// 构造读取器。
  const NewsDailySettings({required this.reader, required this.zone});

  /// 只读设置端口。
  final SettingsReader reader;

  /// 当前设备时区（**每次读取时取一次**，因此用户换时区后下一次评估就按新时区算）。
  final SessionLocalZone zone;

  /// 读取策略。
  ///
  /// 读不到的项回退注册表默认值（SET-056 默认开、SET-057 默认 20:00）：定时是一个
  /// **默认开启**的产品行为，因为「一次设置读失败就让定时彻底不跑」会让用户完全无从理解
  /// （他不会知道有个读操作失败了）。回退默认值的方向是可解释的：按文档默认值继续。
  Future<Result<DailyNewsPolicy>> load() async {
    final Result<Object?> enabledRead = await reader.readSetting(
      SettingId.set056,
    );
    final Result<Object?> timeRead = await reader.readSetting(SettingId.set057);
    final Object? enabledRaw = enabledRead.isOk
        ? enabledRead.valueOrNull
        : null;
    final Object? timeRaw = timeRead.isOk ? timeRead.valueOrNull : null;
    return Ok<DailyNewsPolicy>(
      DailyNewsPolicy(
        enabled: readDailyNewsEnabled(enabledRaw),
        timeOfDayMinutes: readDailyNewsTime(timeRaw),
        zone: zone,
      ),
    );
  }
}

/// SET-056 的取值解析（非布尔或读不到 → 注册表默认，即**开**）。
bool readDailyNewsEnabled(Object? raw) {
  if (raw is bool) {
    return raw;
  }
  // SET-056 的注册表默认值是布尔；读不到或类型不符时按「默认开」处理（与注册表一致）。
  return _registryDefault(SettingId.set056) != false;
}

/// SET-057 的取值解析（非法或读不到 → 注册表默认，即 20:00）。
int readDailyNewsTime(Object? raw) {
  final int? parsed = parseTimeOfDayMinutes(raw is String ? raw : null);
  if (parsed != null) {
    return parsed;
  }
  final Object? fallback = _registryDefault(SettingId.set057);
  return parseTimeOfDayMinutes(fallback is String ? fallback : null) ??
      parseTimeOfDayMinutes(kNewsDefaultDailyTime)!;
}

Object? _registryDefault(SettingId id) =>
    SettingRegistry.findById(id)?.defaultValue;

/// 判定定时任务是否具备运行条件。
///
/// 判定顺序对应四种**不同的**用户动作，因此顺序不是随意安排的：
///
///   1) **没有启用的模型** → 去「AI 服务」添加并启用一个；
///   2) **模型没有 Key** → 去补 Key（有模型但没凭据时任务会在第一次调用就认证失败，
///      而那会在 20:00 变成一个「运行了但失败」的记录，不如提前说成「等待配置」）；
///   3) **没有启用的搜索服务** → 去「搜索服务」配置（缺搜索不是硬阻塞：RSS 与必访站仍能
///      产出内容，但核验会降级为「未联网核验」。因此这一条**不**让任务等待，只作为提示）；
///   4) **费用告知未确认** → 这是唯一一条**必须**先确认才能跑的条件：定时任务没有任何
///      对话框，没有这条记录就等于未经告知地付费运行。
///
/// 返回的原因标识是稳定的英文类别名，界面按语言映射文案（不在这一层拼中文）。
Future<DailyNewsReadiness> loadDailyNewsReadiness({
  required Future<Result<List<AiModel>>> Function() loadModels,
  required AiCredentialStore credentials,
  required NewsCostNoticeStore costNotice,
}) async {
  final Result<List<AiModel>> models = await loadModels();
  if (models.isErr) {
    return const DailyNewsReadiness(ready: false, reason: 'modelReadFailed');
  }
  final List<AiModel> enabled = models.valueOrNull!;
  if (enabled.isEmpty) {
    return const DailyNewsReadiness(ready: false, reason: 'noEnabledModel');
  }
  // 只要**有一个**启用模型配好 Key 就够：任务本身支持跨模型故障转移（T029）。
  bool anyCredential = false;
  for (final AiModel model in enabled) {
    final Result<bool> exists = await credentials.exists(model.alias);
    if (exists.isOk && exists.valueOrNull!) {
      anyCredential = true;
      break;
    }
  }
  if (!anyCredential) {
    return const DailyNewsReadiness(ready: false, reason: 'noModelCredential');
  }
  final bool acknowledged = await costNotice.isAcknowledged();
  if (!acknowledged) {
    return const DailyNewsReadiness(ready: false, reason: 'costNotice');
  }
  return DailyNewsReadiness.ok;
}

/// 从「今日页的搜索可用性端口」派生「有没有启用的搜索服务」（设置页的提示文案用它）。
///
/// 缺搜索**不**让定时任务等待：RSS 与必访站的材料足以产出一份标注「未联网核验」的总结。
/// 因此它只影响提示，不影响 [loadDailyNewsReadiness] 的结论。
Future<bool> hasEnabledSearchService(
  NewsSearchAvailability availability,
) async {
  final Result<bool> result = await availability.hasEnabledService();
  return result.isOk && result.valueOrNull!;
}
