// Flux 应用入口（T007 骨架版）。
//
// 职责：只做依赖组装的起点。按架构第 2.2 节，app 层负责“启动、导航、主题、
// 国际化、依赖组装”，因此这里挂 Riverpod 的 ProviderScope，把具体实现
// （数据库、网络适配器）留给 T009 之后的组合根注入。
//
// 本文件刻意保持极薄：UI 在 lib/app，业务在 lib/features。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  // ProviderScope 是 Riverpod 的根容器：T009 起在此 override 注入
  // 数据库、时钟与各 Provider 适配器的具体实现。
  runApp(const ProviderScope(child: FluxApp()));
}
