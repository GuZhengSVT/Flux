// AI 失败类别的用户文案（T025）。
//
// 放在 presentation 而不是 controller：它只做「对哪种情况说哪句话」的映射，用的是
// l10n 资源，因此属于展示层（与 refresh_outcome_text.dart 同一分层）。
//
// 两条原则：
//   1) **不显示底层错误消息原文**。AppError.message 里已经过脱敏，但它仍可能包含
//      Base URL 的路径段或服务商错误码；对用户来说「认证失败：Key 可能不正确」比
//      「authentication (HTTP 401)」更能指向下一步动作。
//   2) **不把可重试与不可重试混为一谈**：限流说「稍后再试」，认证失败说「去检查 Key」，
//      内容拒绝说「换服务商也不能规避」。写错一句就会让用户朝错误的方向浪费时间。
library;

import 'package:flux/l10n/l10n.dart';

import '../application/model_manager_controller.dart';
import '../domain/ai_model_references.dart';

/// 把失败类别翻译成一句用户能据此行动的话。
String describeAiFailure(
  AppLocalizations l10n,
  AiFailureReason reason, {
  String? detail,
}) => switch (reason) {
  AiFailureReason.validation => l10n.aiFailureValidation(detail ?? ''),
  AiFailureReason.authentication => l10n.aiFailureAuth,
  AiFailureReason.rateLimited => l10n.aiFailureRateLimited,
  AiFailureReason.contentFiltered => l10n.aiFailureContentFiltered,
  AiFailureReason.network => l10n.aiFailureNetwork(detail ?? ''),
  AiFailureReason.timeout => l10n.aiFailureTimeout,
  AiFailureReason.cancelled => l10n.aiFailureCancelled,
  AiFailureReason.adapterMissing => l10n.aiFailureAdapterMissing,
  AiFailureReason.credentialMissing => l10n.aiFailureCredentialMissing,
  AiFailureReason.disabled => l10n.aiFailureDisabled,
  AiFailureReason.storage => l10n.aiFailureStorage,
  AiFailureReason.unknown => l10n.aiFailureUnknown(detail ?? ''),
};

/// 把一条模型引用翻译成用户可见的名称。
String describeModelReference(
  AppLocalizations l10n,
  ModelReference reference,
) => switch (reference.kind) {
  ModelReferenceKind.defaultForTasks => l10n.aiReferenceDefaultForTasks,
  ModelReferenceKind.visionModel => l10n.aiReferenceVisionModel,
  ModelReferenceKind.failoverAllowList => l10n.aiReferenceFailover,
};
