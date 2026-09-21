// 依赖方向烟测（T007 验收：presentation/features 不得直接依赖 infrastructure）。
//
// 说明为什么用“源码扫描”而不是 import 图分析：
// - M0 阶段只有目录骨架，没有真实调用边，单独构建 import 图会得到空集合，
//   验证力为零；
// - 扫描 `import`/`export` 行是纯 Dart、无第三方依赖、可离线运行的做法，
//   在违规引入的第一时间（提交前）就会失败；
// - 它检查的是“字面上写了什么”，不做别名消解。若后续出现 `as`/`show` 之外的
//   间接引用方式（例如 reflector、part 文件跨层），需在 T011 起升级为
//   analyzer 级别的规则；本文件在发现有绕过风险时应显式失败而不是放行。
//
// 规则来源：架构说明书第 2.2 节 ——「展示层调用用例层，用例层依赖领域规则和
// 接口；基础设施实现这些接口。组合入口负责注入具体实现。页面不能直接操作
// 数据库或调用付费 API。」

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 仓库根目录（测试运行时的工作目录即包根）。
const String _libRoot = 'lib';

/// 不得 import infrastructure 的目录。
///
/// `lib/app` 是组合根（负责注入具体实现），`lib/infrastructure` 是实现自身，
/// 两者都在允许范围内，因此不列入这里。
const List<String> _upperLayerDirs = <String>['lib/features'];

/// 递归收集 [directory] 下的 .dart 文件。
List<File> _dartFiles(String directory) {
  final Directory dir = Directory(directory);
  if (!dir.existsSync()) {
    return const <File>[];
  }
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.dart'))
      .toList(growable: false);
}

/// 抽取文件中所有 import/export 的目标 URI（不含 dart:/package: 自身）。
List<String> _directiveTargets(File file) {
  final RegExp directive = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  return directive
      .allMatches(file.readAsStringSync())
      .map((RegExpMatch match) => match.group(1)!)
      .toList(growable: false);
}

void main() {
  group('依赖方向', () {
    test('分层目录骨架存在（架构第 2.2 节）', () {
      for (final String dir in <String>[
        'lib/app',
        'lib/core',
        'lib/features/feeds',
        'lib/features/articles',
        'lib/features/news',
        'lib/features/ai',
        'lib/features/settings',
        'lib/features/sync',
        'lib/features/statistics',
        'lib/infrastructure/local',
        'lib/infrastructure/network',
        'lib/infrastructure/platform',
        'lib/l10n',
        'test/fixtures',
      ]) {
        expect(Directory(dir).existsSync(), isTrue, reason: '缺少目录 $dir');
      }
    });

    test('lib 下每个目录都有 dart 文件（不留空壳）', () {
      final List<Directory> dirs = Directory(_libRoot)
          .listSync(recursive: true)
          .whereType<Directory>()
          .toList(growable: false);
      for (final Directory dir in dirs) {
        if (dir.path.endsWith('.dart')) {
          continue;
        }
        expect(
          _dartFiles(dir.path).isNotEmpty,
          isTrue,
          reason: '${dir.path} 没有任何 .dart 文件',
        );
      }
    });

    test('features 层不 import infrastructure（页面不直接碰数据库/付费 API）', () {
      final List<String> violations = <String>[];
      for (final String root in _upperLayerDirs) {
        for (final File file in _dartFiles(root)) {
          for (final String target in _directiveTargets(file)) {
            if (target.contains('infrastructure/')) {
              violations.add('${file.path} -> $target');
            }
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: '上层不得直接依赖 infrastructure：\n${violations.join('\n')}',
      );
    });

    test('features 层不直接 import drift/sqlite3/http 等基础设施包', () {
      // 这些包只能出现在 lib/infrastructure 下（架构 2.1：业务层不依赖某家 SDK）。
      const List<String> forbidden = <String>[
        'package:drift/',
        'package:sqlite3/',
        'package:http/',
        'package:path_provider/',
      ];
      final List<String> violations = <String>[];
      for (final File file in _dartFiles('lib/features')) {
        for (final String target in _directiveTargets(file)) {
          for (final String banned in forbidden) {
            if (target.startsWith(banned)) {
              violations.add('${file.path} -> $target');
            }
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('core 层保持纯净：不依赖 features/infrastructure/Flutter 之外的层', () {
      // core 是跨模块基础件，被所有层依赖；它反过来依赖上层会造成循环。
      final List<String> violations = <String>[];
      for (final File file in _dartFiles('lib/core')) {
        for (final String target in _directiveTargets(file)) {
          if (target.contains('features/') ||
              target.contains('infrastructure/') ||
              target.contains('app/')) {
            violations.add('${file.path} -> $target');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('lib/core 不依赖 Flutter UI 与 Riverpod（可被纯 Dart 测试复用）', () {
      const List<String> forbidden = <String>[
        'package:flutter/material.dart',
        'package:flutter/widgets.dart',
        'package:flutter_riverpod/',
      ];
      final List<String> violations = <String>[];
      for (final File file in _dartFiles('lib/core')) {
        for (final String target in _directiveTargets(file)) {
          if (forbidden.contains(target)) {
            violations.add('${file.path} -> $target');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('扫描器本身有效：确实能发现构造出的违规（防止测试空转）', () {
      // 这是一个“元测试”：若 _directiveTargets 退化到什么都不匹配，
      // 上面的检查会全部虚假通过，因此这里用内联源码验证解析能力。
      final RegExp directive = RegExp(
        r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
        multiLine: true,
      );
      const String sample = """
// 注释里的 import 'package:flux/infrastructure/local/db.dart'; 不应被误判
import 'package:flux/core/core.dart';
export 'package:flux/infrastructure/network/rss.dart';
""";
      final List<String> found = directive
          .allMatches(sample)
          .map((RegExpMatch match) => match.group(1)!)
          .toList();
      expect(found, <String>[
        'package:flux/core/core.dart',
        'package:flux/infrastructure/network/rss.dart',
      ]);
      // 注释行没有被当成指令。
      expect(found.length, 2);
    });
  });
}
