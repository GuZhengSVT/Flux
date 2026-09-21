// 应用壳的组件冒烟测试（T007）。
//
// 只验证“骨架能挂起来并渲染首屏”，不把任何业务断言写在这里：
// M0 阶段没有可验收的页面行为，业务断言从 T011 起按页面补充。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/app/app.dart';

void main() {
  testWidgets('骨架应用可挂载并显示 Flux 标题', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: FluxApp()));
    await tester.pumpAndSettle();

    // AppBar 标题与实际项目同名，避免误把它当成模板残留。
    expect(find.text('Flux'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Flutter Demo'), findsNothing);
  });

  testWidgets('骨架首屏明确标注为 M0 占位，不做功能宣称', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: FluxApp()));
    await tester.pumpAndSettle();

    expect(find.textContaining('T007'), findsOneWidget);
  });
}
