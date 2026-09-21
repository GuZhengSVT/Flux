// 视觉发送告知（T033；架构第 8 节「首次数据发送与付费告知的确认记录保存在本机，并绑定
// 提供商、目标端点和允许能力。同步来的配置不自动授予另一设备发送权限；端点或接收者发生
// 实质变化时重新告知」、SET-065）。
//
// 为什么这件事需要**类型**而不是一个 bool 参数：
//   - 告知必须绑定「发给谁」（端点）与「发什么」（能力=vision）。把一张图发给一个用户从没
//     同意过的端点，与把文字发给它，是两次不同的数据出境；用一个全局布尔「已同意 AI」会
//     让用户对第二条毫不知情；
//   - 确认记录是本机运行授权状态（架构第 8 节明确它不作为普通偏好同步），因此它的落库
//     形态与「设置项」不同：键里带端点摘要，另一台设备同步过去也匹配不上。
//
// [VisionSendConfirmation] 与 T025 的 CostConfirmation / T031 的 SearchSendConfirmation 同一
// 口径：调用方无法「顺手」构造一个 true 来表达「用户已经确认过了」——只有真正弹过对话框的
// 那条代码路径能构造它。
library;

import 'package:flux/core/core.dart';

/// 一条视觉发送告知的确认记录。
final class VisionSendAcknowledgement {
  /// 构造记录。
  const VisionSendAcknowledgement({
    required this.endpoint,
    required this.providerAlias,
    required this.acknowledgedAtUtc,
  });

  /// 接收端点（模型 Base URL；用户看到的就是它）。
  final String endpoint;

  /// 提供商标识别名（记录「当时用的是哪个别名」，便于用户核对）。
  final String providerAlias;

  /// 用户确认的时刻（UTC）。
  final DateTime acknowledgedAtUtc;

  /// 本机存储键：**端点摘要**而不是端点原文。
  ///
  /// 用摘要有两个作用：键长度可控（端点可能带长查询串），以及键不把端点写进设置表的
  /// 人眼可读位置（设置表会被明文备份带走，端点是网络目的地而非秘密，但没有理由复制）。
  static String storageKeyFor(String endpoint) =>
      'device.visionSendAck.${sha256HexOfString(endpoint.trim())}';

  @override
  String toString() =>
      'VisionSendAcknowledgement($endpoint, alias=$providerAlias)';
}

/// 一次视觉发送告知的授权凭据（只应由「用户点了确认」的代码路径创建）。
final class VisionSendConfirmation {
  /// 构造已确认的凭据。
  const VisionSendConfirmation({required this.acknowledgedAtUtc});

  /// 用户确认的时刻（UTC），写进诊断便于核对「这次调用经过了知情确认」。
  final DateTime acknowledgedAtUtc;
}

/// 视觉发送告知的读写端口。
///
/// 实现必须把记录存在**本机**（不进同步投影）：架构第 8 节明确「同步来的配置不自动授予
/// 另一设备发送权限」。读不到记录时返回 Ok(null)（=需要告知），而不是失败——那正是
/// 「这台设备还没同意过」这个事实。
abstract interface class VisionConsentStore {
  /// 查询某个端点的告知记录；没有记录时返回 Ok(null)。
  Future<Result<VisionSendAcknowledgement?>> find(String endpoint);

  /// 记录一次告知（幂等：同一端点重复确认覆盖时刻与别名）。
  Future<Result<void>> save(VisionSendAcknowledgement acknowledgement);
}
