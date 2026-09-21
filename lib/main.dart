// Flux 应用入口（T011）。
//
// 顺序刻意如此：**先装配依赖，再挂 ProviderScope**。
//   - 数据目录/数据库/设置/凭据/诊断都是进程级单例，装配失败也要给出可显示的
//     壳层（见 app_bootstrap.dart 的降级路径），因此装配结果必须先于 widget 树存在；
//   - 若反过来在 widget 内部做异步初始化，会引入「首帧该显示什么」的第二套状态，
//     也让数据库打开失败的提示变成加载动画之后的一次条件跳转。
//
// 本文件保持极薄：装配在 app_bootstrap.dart，注入清单在 app_providers.dart，
// UI 在 lib/app，业务在 lib/features。
library;

// AppExitResponse 由 dart:ui 定义（didRequestAppExit 的返回类型），
// 不随 flutter/widgets 导出，因此显式引用。
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/app_bootstrap.dart';
import 'app/app_providers.dart';

Future<void> main() async {
  // 桌面应用在 runApp 之前需要平台通道就绪（path_provider 要用它取数据目录）。
  WidgetsFlutterBinding.ensureInitialized();

  final AppBootstrapResult bootstrap = await bootstrapApp();

  // 释放归属：数据库句柄由装配结果持有，应用被系统回收时关闭，
  // 避免 WAL 文件在下次启动前留下未完成状态。
  final WidgetsBindingObserver lifecycle = _BootstrapDisposer(bootstrap);
  WidgetsBinding.instance.addObserver(lifecycle);

  runApp(
    ProviderScope(
      overrides: bootstrapOverrides(bootstrap),
      child: const FluxApp(),
    ),
  );
}

/// 在应用结束前释放装配资源。
class _BootstrapDisposer extends WidgetsBindingObserver {
  _BootstrapDisposer(this._bootstrap);

  final AppBootstrapResult _bootstrap;

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    // 先关闭数据库再放行退出：close 是幂等的，正常退出路径上完成后
    // WAL 会被合并，下次启动不需要额外恢复。
    try {
      await _bootstrap.dispose();
    } on Exception {
      // 关闭失败不应阻止退出：drift/SQLite 在进程终止后仍能凭 WAL 恢复，
      // 卡在退出流程反而让用户无法关闭窗口。
    }
    return super.didRequestAppExit();
  }
}
