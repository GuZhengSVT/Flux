// 设置项定义（T010，架构第 6 节）。
//
// 本文件把架构说明书的 SET 表**逐条**翻译成可执行的定义：类型、默认值、取值
// 范围（min/max 或枚举值域）与 C/D/S 分类。它是设置读写的唯一事实来源：
//   - 设置页（T011）按它生成入口，不自己写一份默认值；
//   - 存储层按它决定能否持久化（secret 不进普通存储）；
//   - 测试按它断言文档口径，文档改动必须同步这里，而不是让代码悄悄漂移。
//
// 范围口径：文档给了数值区间的就照抄；文档没给区间的（例如颜色、字体名）
// min/max 留空，不臆造一个看起来合理的上限——凭空限值会让用户配置被无故拒绝。
library;

import 'package:flux/core/error/app_error.dart';
import 'package:flux/core/result.dart';

import 'setting_id.dart';

/// 设置的 C/D/S 分类（架构第 6 节表头定义）。
///
/// - [common]（C）：共通项，可随 WebDAV 同步；
/// - [device]（D）：设备专属，不自动同步；
/// - [secret]（S）：秘密，仅本机安全存储，不同步、不备份、不进普通设置表。
enum SettingClassification { common, device, secret }

/// 设置值的类型与取值域。
sealed class SettingValueSpec {
  const SettingValueSpec();

  /// 该类型的默认值（解码后的 JSON 形态：bool/int/double/String/List/Map）。
  Object? get defaultValue;

  /// 校验一个**已解码**的值是否属于该取值域。
  ///
  /// [field] 只用于错误信息与测试断言，必须是设置 ID 或组件名，不含秘密内容。
  Result<void> validate(String field, Object? value);
}

/// 布尔开关。
final class BoolSpec extends SettingValueSpec {
  const BoolSpec({this.defaultValue = false});

  @override
  final bool defaultValue;

  @override
  Result<void> validate(String field, Object? value) {
    if (value is bool) {
      return okUnit();
    }
    return Err<void>(
      ValidationError(
        field: field,
        reason: '需要布尔值（true/false）',
        value: value?.runtimeType.toString(),
      ),
    );
  }
}

/// 整数，可带闭区间 [min, max]（null 表示该侧不限）。
final class IntSpec extends SettingValueSpec {
  const IntSpec({this.defaultValue, this.min, this.max});

  @override
  final int? defaultValue;

  /// 允许的最小值；null 表示文档未规定下限。
  final int? min;

  /// 允许的最大值；null 表示文档未规定上限。
  final int? max;

  @override
  Result<void> validate(String field, Object? value) {
    // JSON 解码后整数是 int；接受整数值的 double（例如 2.0）会让范围判断与
    // 展示都不稳定，因此这里严格要求 int，不做宽容转换。
    if (value is! int) {
      return Err<void>(
        ValidationError(
          field: field,
          reason: '需要整数',
          value: value?.runtimeType.toString(),
        ),
      );
    }
    if (min != null && value < min!) {
      return Err<void>(
        ValidationError(field: field, reason: '不能小于 $min', value: '$value'),
      );
    }
    if (max != null && value > max!) {
      return Err<void>(
        ValidationError(field: field, reason: '不能大于 $max', value: '$value'),
      );
    }
    return okUnit();
  }
}

/// 小数，可带闭区间 [min, max]。
final class DoubleSpec extends SettingValueSpec {
  const DoubleSpec({this.defaultValue, this.min, this.max});

  @override
  final double? defaultValue;

  /// 允许的最小值；null 表示文档未规定下限。
  final double? min;

  /// 允许的最大值；null 表示文档未规定上限。
  final double? max;

  @override
  Result<void> validate(String field, Object? value) {
    if (value is! num) {
      return Err<void>(
        ValidationError(
          field: field,
          reason: '需要数值',
          value: value?.runtimeType.toString(),
        ),
      );
    }
    final double numeric = value.toDouble();
    if (min != null && numeric < min!) {
      return Err<void>(
        ValidationError(field: field, reason: '不能小于 $min', value: '$value'),
      );
    }
    if (max != null && numeric > max!) {
      return Err<void>(
        ValidationError(field: field, reason: '不能大于 $max', value: '$value'),
      );
    }
    return okUnit();
  }
}

/// 文本，可用正则约束形态（例如 `HH:mm` 时间）。
final class StringSpec extends SettingValueSpec {
  const StringSpec({this.defaultValue, this.pattern, this.patternHint});

  @override
  final String? defaultValue;

  /// 允许的形态（正则源码）；null 表示任意文本。
  ///
  /// 存字符串而不是 [RegExp]：注册表是 const 列表，而 [RegExp] 无法在常量
  /// 上下文中构造。编译结果按源码缓存，避免每次校验都重新编译。
  final String? pattern;

  /// [pattern] 的说明，用于错误文案与设置页提示。
  final String? patternHint;

  @override
  Result<void> validate(String field, Object? value) {
    if (value is! String) {
      return Err<void>(
        ValidationError(
          field: field,
          reason: '需要字符串',
          value: value?.runtimeType.toString(),
        ),
      );
    }
    final String? source = pattern;
    if (source != null && !_compile(source).hasMatch(value)) {
      return Err<void>(
        ValidationError(
          field: field,
          reason: patternHint ?? '格式不匹配',
          value: value,
        ),
      );
    }
    return okUnit();
  }

  /// 按正则源码取编译结果，带缓存。
  static RegExp _compile(String source) =>
      _compiledPatterns.putIfAbsent(source, () => RegExp(source));

  /// 已编译的形态正则缓存，键为正则源码。
  static final Map<String, RegExp> _compiledPatterns = <String, RegExp>{};
}

/// 枚举：取值只能是 [values] 之一（大小写敏感，存稳定字符串名）。
///
/// [defaultValue] 为 null 表示文档口径是「未设置/无」（例如 SET-030 手动添加、
/// SET-034 专用视觉模型未设置），而不是缺少默认值。
final class EnumSpec extends SettingValueSpec {
  const EnumSpec({required this.values, this.defaultValue});

  /// 允许取值（稳定字符串，落库与同步都用它，不能用序号）。
  final List<String> values;

  @override
  final String? defaultValue;

  @override
  Result<void> validate(String field, Object? value) {
    if (value is! String) {
      return Err<void>(
        ValidationError(
          field: field,
          reason: '需要字符串枚举值',
          value: value?.runtimeType.toString(),
        ),
      );
    }
    if (!values.contains(value)) {
      return Err<void>(
        ValidationError(
          field: field,
          reason: '必须是 ${values.join('/')} 之一',
          value: value,
        ),
      );
    }
    return okUnit();
  }
}

/// 字符串列表（有序，去重由使用方按业务决定）。
final class StringListSpec extends SettingValueSpec {
  const StringListSpec({this.defaultValue = const <String>[]});

  @override
  final List<String> defaultValue;

  @override
  Result<void> validate(String field, Object? value) {
    if (value is! List<Object?>) {
      return Err<void>(
        ValidationError(
          field: field,
          reason: '需要字符串数组',
          value: value?.runtimeType.toString(),
        ),
      );
    }
    for (final Object? item in value) {
      if (item is! String) {
        return Err<void>(
          ValidationError(
            field: field,
            reason: '数组元素必须是字符串',
            value: item?.runtimeType.toString(),
          ),
        );
      }
    }
    return okUnit();
  }
}

/// 动作类设置：文档明确写成「操作，不是持久设置」的编号（SET-042 连通性/最小
/// 生成/搜索测试，SET-079 清理预览/一键清缓存/占用刷新）。
///
/// 它们没有默认值，也不应被写进设置表——把一次按钮点击当成长期偏好保存，会让
/// 「设置」与「操作记录」混淆，并在同步时把无意义的动作状态带到其他设备。
/// [validate] 只接受 null（即「没有值可存」），任何实际值都被拒绝。
final class ActionSpec extends SettingValueSpec {
  const ActionSpec();

  @override
  Object? get defaultValue => null;

  @override
  Result<void> validate(String field, Object? value) {
    if (value == null) {
      return okUnit();
    }
    return Err<void>(
      ValidationError(
        field: field,
        reason: '操作类设置不接受持久值',
        value: value.runtimeType.toString(),
      ),
    );
  }
}

/// 复合设置：文档里一个编号承载多个数值/开关（例如 SET-004 的不透明度+模糊+
/// 亮度）。每个分量有独立默认值与范围，落库为一个 JSON 对象。
final class CompositeSpec extends SettingValueSpec {
  const CompositeSpec({required this.fields});

  /// 分量定义，顺序即展示顺序。
  final List<SettingField> fields;

  @override
  Map<String, Object?> get defaultValue => <String, Object?>{
    for (final SettingField field in fields)
      field.name: field.spec.defaultValue,
  };

  /// 按分量名取分量；不存在时返回 null（调用方自行决定如何处理）。
  SettingField? field(String name) {
    for (final SettingField field in fields) {
      if (field.name == name) {
        return field;
      }
    }
    return null;
  }

  @override
  Result<void> validate(String field, Object? value) {
    if (value is! Map<Object?, Object?>) {
      return Err<void>(
        ValidationError(
          field: field,
          reason: '需要对象（各分量键值）',
          value: value?.runtimeType.toString(),
        ),
      );
    }
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final Object? key = entry.key;
      if (key is! String) {
        return Err<void>(ValidationError(field: field, reason: '分量名必须是字符串'));
      }
      final SettingField? component = this.field(key);
      if (component == null) {
        // 未知分量直接拒绝：多半是拼错键名，静默保留会变成一个永远读不到的
        // 幽灵配置，也让「文档与实现一致」无法验证。
        return Err<void>(ValidationError(field: field, reason: '未知分量 $key'));
      }
      final Result<void> result = component.spec.validate(
        '$field.$key',
        entry.value,
      );
      if (result.isErr) {
        return Err<void>(result.errorOrNull!);
      }
    }
    return okUnit();
  }
}

/// 复合设置的一个分量。
final class SettingField {
  const SettingField({required this.name, required this.spec});

  /// 分量名（落库 JSON 的键，稳定不改）。
  final String name;

  /// 分量的类型与取值域。
  final SettingValueSpec spec;

  /// 该分量的默认值。
  Object? get defaultValue => spec.defaultValue;
}

/// 一个设置项的完整注册信息。
final class SettingDefinition {
  const SettingDefinition({
    required this.id,
    required this.title,
    required this.spec,
    required this.classification,
    this.isPersistent = true,
    this.isReadOnly = false,
  });

  /// 设置编号（SET-xxx）。
  final SettingId id;

  /// 文档口径的简短标题，用于设置页分组与测试断言，不作为最终 UI 文案
  /// （最终文案走 l10n 资源，见 T011）。
  final String title;

  /// 类型与取值域。
  final SettingValueSpec spec;

  /// C/D/S 分类。
  final SettingClassification classification;

  /// 是否为持久设置项。
  ///
  /// 文档把 SET-042/SET-079 明确写成「操作，不是持久设置」，因此这里标记为
  /// false；存储层拒绝把它们写进设置表，避免把一次按钮点击当成用户偏好长期保留。
  final bool isPersistent;

  /// 是否为只读项。
  ///
  /// SET-058（新闻时区，只读「跟随设备」）与 SET-084（版本等发布元数据）由系统
  /// 提供而非用户填写，设置页只展示不可编辑。
  final bool isReadOnly;

  /// 默认值（解码后的 JSON 形态）。
  Object? get defaultValue => spec.defaultValue;

  /// 是否为秘密项（S 类）。
  bool get isSecret => classification == SettingClassification.secret;

  /// 校验一个值是否属于本项的取值域。
  Result<void> validateValue(Object? value) => spec.validate(id.code, value);
}

/// 校验一个**已解码**的设置值；供注册表与仓储共用。
Result<void> validateSettingValue(SettingDefinition definition, Object? value) {
  return definition.validateValue(value);
}

/// 构造一个「未知设置编号」的类型化错误。
AppError unknownSettingId(SettingId id) =>
    ValidationError(field: id.code, reason: '未注册的设置编号');

/// 值是否与 [spec] 的默认值相等（用于「是否偏离默认」判断）。
bool matchesDefault(SettingValueSpec spec, Object? value) {
  final Object? expected = spec.defaultValue;
  if (expected is Map<String, Object?> && value is Map<Object?, Object?>) {
    if (expected.length != value.length) {
      return false;
    }
    for (final MapEntry<String, Object?> entry in expected.entries) {
      if (!value.containsKey(entry.key) || value[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
  if (expected is List<Object?> && value is List<Object?>) {
    if (expected.length != value.length) {
      return false;
    }
    for (int i = 0; i < expected.length; i++) {
      if (expected[i] != value[i]) {
        return false;
      }
    }
    return true;
  }
  return expected == value;
}
