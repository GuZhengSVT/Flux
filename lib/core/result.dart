// Flux 结果类型（T007）。
//
// 用途：在“可预期失败”的边界（解析、网络、存储、AI 调用）统一返回成功值或
// 类型化 [AppError]，避免把错误语义塞进 `null`、空字符串或 bool 返回值。
//
// 约定：
// - 编程错误仍抛异常；[Result] 只承载调用方需要分支处理的失败；
// - `None`/`null` 表示“成功但没有值”，与 `Err` 语义不同；
// - 不隐藏错误：需要抛出时用 `Err.unwrap()` 或显式 `switch`。
library;

import 'error/app_error.dart';

/// 成功值或错误的封闭结果。
sealed class Result<T> {
  const Result();

  /// 直接构造成功结果。
  static Result<T> ok<T>(T value) => Ok<T>(value);

  /// 直接构造错误结果。
  static Result<T> err<T>(AppError error) => Err<T>(error);

  /// 是否成功。
  bool get isOk;

  /// 是否失败。
  bool get isErr => !isOk;

  /// 成功值；失败时为 null。
  T? get valueOrNull;

  /// 错误；成功时为 null。
  AppError? get errorOrNull;

  /// 把成功值映射为另一种类型，保持错误分支不变。
  Result<R> map<R>(R Function(T value) transform);

  /// 扁平映射，用于串接多个可能失败的步骤。
  Result<R> flatMap<R>(Result<R> Function(T value) transform);

  /// 在失败时提供替换结果。
  Result<T> recover(Result<T> Function(AppError error) recoverWith);

  /// 取成功值；失败时抛出所携带的 [AppError]。
  T unwrap() {
    final Result<T> self = this;
    if (self is Ok<T>) {
      return self.value;
    }
    throw (self as Err<T>).error;
  }

  /// 取成功值，失败时返回 [fallback]。
  T getOrElse(T fallback) => valueOrNull ?? fallback;
}

/// 成功分支。
final class Ok<T> extends Result<T> {
  const Ok(this.value);

  /// 成功值。基类只声明 [valueOrNull]；这里用非空字段承载实际值。
  final T value;

  @override
  bool get isOk => true;

  @override
  T? get valueOrNull => value;

  @override
  AppError? get errorOrNull => null;

  @override
  Result<R> map<R>(R Function(T value) transform) => Ok<R>(transform(value));

  @override
  Result<R> flatMap<R>(Result<R> Function(T value) transform) =>
      transform(value);

  @override
  Result<T> recover(Result<T> Function(AppError error) recoverWith) => this;

  @override
  String toString() => 'Ok($value)';
}

/// 失败分支。
final class Err<T> extends Result<T> {
  const Err(this.error);

  /// 失败原因。基类只声明 [errorOrNull]；这里用非空字段承载实际错误。
  final AppError error;

  @override
  bool get isOk => false;

  @override
  T? get valueOrNull => null;

  @override
  AppError? get errorOrNull => error;

  @override
  Result<R> map<R>(R Function(T value) transform) => Err<R>(error);

  @override
  Result<R> flatMap<R>(Result<R> Function(T value) transform) => Err<R>(error);

  @override
  Result<T> recover(Result<T> Function(AppError error) recoverWith) =>
      recoverWith(error);

  @override
  String toString() => 'Err(${error.toLogString()})';
}

/// 无成功值的成功结果（例如“删除完成”）。
typedef Unit = Result<void>;

/// 构造无值的成功结果。
Result<void> okUnit() => const Ok<void>(null);

/// 构造无值的失败结果。
Result<void> errUnit(AppError error) => Err<void>(error);
