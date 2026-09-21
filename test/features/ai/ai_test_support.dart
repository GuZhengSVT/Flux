// T025 测试用的小工具：设置端口替身与模型构造快捷方式。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/model_manager.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/model_capability.dart';

/// 一个按键返回固定值的设置读取端口。
final class FakeSettingsReader implements SettingsReader {
  /// 以固定值表构造。
  FakeSettingsReader({this.values = const <String, Object?>{}});

  /// 编号 → 值。
  final Map<String, Object?> values;

  /// 被读取过的编号（用于断言「确实检查了引用」）。
  final List<String> readIds = <String>[];

  @override
  Future<Result<Object?>> readSetting(SettingId id) async {
    readIds.add(id.code);
    return Ok<Object?>(values[id.code]);
  }
}

/// 一个读取必然失败的设置端口（验证「读不到 ≠ 没有引用」）。
final class FailingSettingsReader implements SettingsReader {
  @override
  Future<Result<Object?>> readSetting(SettingId id) async =>
      Err<Object?>(StorageError(operation: 'test.readSetting', detail: 'boom'));
}

/// 构造一条测试用模型记录。
AiModel testModel({
  String alias = 'deepseek',
  String baseUrl = 'https://api.deepseek.com',
  String modelId = 'deepseek-chat',
  AiProtocol protocol = AiProtocol.openAiChatCompletions,
  bool enabled = true,
  ModelCapability capability = const ModelCapability(),
}) => AiModel(
  alias: alias,
  protocol: protocol,
  baseUrl: baseUrl,
  modelId: modelId,
  enabled: enabled,
  capability: capability,
);
