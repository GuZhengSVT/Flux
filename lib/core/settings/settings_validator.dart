// 设置校验与编解码（T010）。
//
// 两件事分开：
//   - [SettingsValidator] 只回答「这个值是否属于该编号的取值域」，不接触 I/O；
//   - [SettingValueCodec] 负责 JSON 往返。存储层、同步层、设置页都用同一份，
//     避免「UI 允许但存储拒绝」这类只在特定入口出现的分歧。
//
// 为什么值统一走 JSON：settings 表只有 (key, value) 两列，值类型由注册表决定。
// 用 JSON 编码可以让 int/bool/String/列表/复合对象共用一条存取路径，并且读回后
// 仍能用注册表校验，不需要为每种类型各写一套列。
library;

import 'dart:convert';

import 'package:flux/core/error/app_error.dart';
import 'package:flux/core/result.dart';

import 'setting_definition.dart';
import 'setting_id.dart';
import 'settings_registry.dart';

/// 设置值校验入口。
abstract final class SettingsValidator {
  /// 校验 [value] 是否属于 [id] 的取值域。
  ///
  /// - 未注册编号：返回 [ValidationError]（而不是静默通过——静默通过会让拼错的
  ///   编号变成一个永远读不到的幽灵配置）；
  /// - 未注册但**形态合法**的复合分量、枚举等都由注册表自身的 spec 判定。
  static Result<void> validate(SettingId id, Object? value) {
    final SettingDefinition? definition = SettingRegistry.findById(id);
    if (definition == null) {
      return Err<void>(unknownSettingId(id));
    }
    return definition.validateValue(value);
  }

  /// 校验该编号是否**允许**进入普通设置存储。
  ///
  /// 拒绝两类：秘密项（S 类，必须走安全存储）与操作类（文档写明不是持久设置）。
  static Result<void> validateStorable(SettingId id) {
    final SettingDefinition? definition = SettingRegistry.findById(id);
    if (definition == null) {
      return Err<void>(unknownSettingId(id));
    }
    if (definition.isSecret) {
      return Err<void>(
        ValidationError(field: id.code, reason: '秘密项不得写入普通设置存储，必须使用安全存储'),
      );
    }
    if (!definition.isPersistent) {
      return Err<void>(ValidationError(field: id.code, reason: '操作类设置不可持久化'));
    }
    return okUnit();
  }

  /// 校验并解码一个 JSON 文本值。
  ///
  /// 分两步返回，是为了让「JSON 坏了」与「值超出了范围」在错误上可区分：
  /// 前者是数据损坏，后者是配置非法，处理方式不同。
  static Result<Object?> decode(SettingId id, String? rawJson) {
    if (rawJson == null) {
      return const Ok<Object?>(null);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (error, stackTrace) {
      return Err<Object?>(
        ParseError(
          source: 'settings:${id.code}',
          detail: '值不是合法 JSON',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    final Result<void> valid = validate(id, decoded);
    if (valid.isErr) {
      return Err<Object?>(valid.errorOrNull!);
    }
    return Ok<Object?>(decoded);
  }
}

/// 设置值的 JSON 编解码。
abstract final class SettingValueCodec {
  /// 把值编码为存储/同步用的 JSON 文本。
  ///
  /// 不做校验：调用方应先用 [SettingsValidator.validate] 判定，编码只负责形态。
  static String encode(Object? value) => jsonEncode(value);

  /// 解码 JSON 文本；失败返回 null（调用方决定如何处理），不抛异常。
  ///
  /// 这里单独提供「宽松解码」是为了让仓储在读到损坏行时能带着编号上报，
  /// 而不是在深处抛出一个没有上下文的 FormatException。
  static Object? decodeOrNull(String rawJson) {
    try {
      return jsonDecode(rawJson);
    } on FormatException {
      return null;
    }
  }
}

/// 便捷函数：按编号校验值，等价于 [SettingsValidator.validate]。
Result<void> validateSetting(String code, Object? value) {
  return SettingsValidator.validate(SettingId(code), value);
}
