// 定时总结的费用告知确认记录（T040；架构 4.4「首次费用告知未确认时任务为 waitingConfiguration」）。
//
// 用 settings 窄表的 `device.` 命名空间存（与引导标记、视觉发送告知同一做法）：确认记录是
// **本机运行授权状态**，不是可同步的偏好。架构 4.4 明确「执行开关是本机项」——把这条记录
// 同步到另一台设备，等于让那台设备因为一条从别处来的记录而自动开跑并自己付费。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/news/application/daily_news_scheduler.dart'
    show NewsCostNoticeStore;

import 'device_state_repository.dart';

/// 由本机状态仓储支撑的费用告知记录。
final class DeviceStateNewsCostNotice implements NewsCostNoticeStore {
  /// 绑定本机状态仓储。
  const DeviceStateNewsCostNotice(this._repository);

  final DeviceStateRepository _repository;

  @override
  Future<bool> isAcknowledged() async {
    final Result<bool> read = await _repository.readBool(
      DeviceStateKey.newsCostNoticeAcknowledged,
    );
    // 读失败按**未确认**处理（fail-closed）：放行会让一次后台付费运行在用户没被告知的
    // 情况下发生，而那个方向的错误没有任何补救余地（钱已经花了）。
    return read.getOrElse(false);
  }

  @override
  Future<Result<void>> acknowledge() =>
      _repository.writeBool(DeviceStateKey.newsCostNoticeAcknowledged, true);
}

/// 数据库不可用时的费用告知记录。
///
/// 与「读作已确认」相反：这里**读作未确认**（于是任务显示等待配置、不发请求），写明确失败
/// （不假装记住了）。数据库不可用是暂时的，而一次未经告知的付费运行是永久的。
final class DegradedNewsCostNotice implements NewsCostNoticeStore {
  /// 构造降级实现。
  const DegradedNewsCostNotice();

  @override
  Future<bool> isAcknowledged() async => false;

  @override
  Future<Result<void>> acknowledge() async => Err<void>(
    StorageError(operation: 'newsCostNotice.acknowledge', detail: '本次运行数据库不可用'),
  );
}
