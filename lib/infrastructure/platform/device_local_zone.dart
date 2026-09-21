// 会话时区的平台实现（T023）。
//
// 为什么需要它，而不是让 core 自己读设备时区：core 不依赖 dart:io 之外的平台能力，
// 而「当前时区」在本项目里必须能**注入**（测试要验证跨午夜拆分，但不该改动进程时区）。
//
// 实现只用 dart:io 的 DateTime.now().timeZoneOffset：它是进程时区的偏移，且在 macOS /
// 其它桌面平台上可用，不引入时区数据库依赖（架构 2.1 的依赖白名单）。
//
// **已知边界（如实记录，不假装已解决）**：固定偏移实现在**夏令时切换日**不会自动
// 把当天偏移换掉——它按读取时刻的当前偏移计算当地读数。对无夏令时地区（中国大陆、
// 新加坡等）这与真实行为完全一致；对有夏令时的地区，切换当天的归属可能差一小时。
// 彻底解决需要系统时区数据库（tzdata）或平台 API，属后续任务范围；本任务不用它冒充
// 「已支持全球所有时区」。
library;

import 'package:flux/core/core.dart';

/// 设备当前时区（按当前偏移的固定偏移实现）。
final class DeviceLocalZone implements SessionLocalZone {
  /// 用给定偏移与名称构造（测试可直接构造）。
  const DeviceLocalZone(this._offset, this.ianaName);

  /// 读取设备当前时区。
  factory DeviceLocalZone.current() {
    final DateTime now = DateTime.now();
    final String name = now.timeZoneName;
    return DeviceLocalZone(now.timeZoneOffset, name);
  }

  final Duration _offset;

  @override
  final String ianaName;

  @override
  DateTime toLocal(DateTime utc) => wallClockOf(utc.toUtc().add(_offset));

  @override
  DateTime toUtc(DateTime wallClock) => wallClock.subtract(_offset);
}
