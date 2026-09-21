// 网络状况探测（T016；SET-013 计费网络守卫、SET-028）。
//
// 本文件只做一件事：如实回答「当前是否计费网络 / 是否确定无网络」，**回答不出来
// 就说不确定**（false）。它不缓存结果、不替调度做判断，也不读取任何用户数据。
//
// 桌面（macOS）的边界，写清楚以免被读成「已实现计费判定」：
//   - 没有公开 API 能回答「当前连接是否计费」。CoreWifi 的
//     isExpensive 是 iOS-only，AppKit 侧没有等价接口。因此
//     DesktopNetworkConditions.isMetered **始终返回 false**，并在注释与手册里
//     如实记录为「桌面端未实现计费判定」，而不是返回 true 假装遵守 SET-013
//     （那会让 macOS 上的定时刷新被静默停住，用户完全无法理解）。
//   - 「是否确定无网络」可以用一个不联网的本地查询回答：是否存在**非回环**的
//     网络接口且已启用。这比 ping 或 DNS 查询更合适——探测本身不能产生流量，
//     也不能因为目标站点故障就报「离线」（那会把源的失败说成网络的问题）。
//
// 真正的计费判定能力（Android 的 ConnectivityManager 计费网络标志）在 Android
// 阶段实现同一个端口，调度层无需改动。
library;

import 'dart:io';

import 'package:flux/core/core.dart';

/// 桌面（macOS）网络状况探测。
final class DesktopNetworkConditions implements NetworkConditionPort {
  /// 构造探测。
  const DesktopNetworkConditions();

  @override
  Future<bool> isMetered() async {
    // macOS 没有公开的计费网络 API：这里如实返回「没有证据表明是计费网络」。
    // 返回 false 的后果是可解释的（SET-013 在桌面上不退化成「默认禁止刷新」），
    // 而返回 true 的后果是刷新被静默停住且用户无法理解。
    return false;
  }

  @override
  Future<bool> isOffline() async {
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        // 只关心接口是否存在与启用，不限定地址族：IPv6-only 与 IPv4 都算在线。
        type: InternetAddressType.any,
      );
      for (final NetworkInterface interface in interfaces) {
        if (interface.addresses.isNotEmpty) {
          return false;
        }
      }
      return true;
    } on Exception {
      // 探测失败（权限、平台限制）时回答「不确定在线与否」= false（不拦）：
      // 宁可让请求发出去并在连接层失败留痕，也不要因为探测不到就把刷新停住。
      return false;
    }
  }
}
