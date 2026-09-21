// 发布元数据测试（T011，SET-084）。
//
// 为什么值得单独写一个测试文件：
//   T011 不引入 package_info_plus（依赖白名单只允许 flutter_localizations），
//   版本号因此是 lib/app/app_metadata.dart 里的常量。常量最大的风险是「忘记随
//   pubspec.yaml 升版本」，而关于页显示的版本号是用户唯一能看到的版本信息，
//   错了会直接影响问题排查。这里直接读 pubspec.yaml 比对，让漂移必失败。
//
// 同时钉住 SET-084 的口径：不存在 URL 时不伪造。因此断言的是「要么是空串，
// 要么是一个看起来真实、且与仓库一致的地址」，而不是死写某个字符串。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/app_metadata.dart';

/// 从 pubspec.yaml 顶层读 version（避免引入 yaml 依赖：只有一行需要解析）。
String _pubspecVersion() {
  for (final String line in File('pubspec.yaml').readAsLinesSync()) {
    if (line.startsWith('version:')) {
      return line.substring('version:'.length).trim();
    }
  }
  fail('pubspec.yaml 里找不到 version');
}

void main() {
  test('版本常量与 pubspec.yaml 一致（不引入 package_info 的代价由测试兜住）', () {
    expect(fluxAppVersion, _pubspecVersion());
    expect(fluxVersionSource, 'pubspec.yaml');
  });

  test('许可为 MIT（仓库根 LICENSE 已存在且为 MIT）', () {
    expect(fluxLicenseName, 'MIT License');
    final String license = File('LICENSE').readAsStringSync();
    expect(license, startsWith('MIT License'));
  });

  test('仓库与 Issue 地址：要么未配置（空串），要么是合理的 HTTPS 地址', () {
    for (final String url in <String>[fluxRepositoryUrl, fluxIssueUrl]) {
      if (url.isEmpty) {
        continue; // 未配置是允许的状态，界面显示「未配置」。
      }
      expect(url, startsWith('https://'), reason: '只允许 https 外链');
      expect(Uri.parse(url).host, 'github.com');
    }
  });

  test('Issue 地址位于仓库之下（两者同源，防止拼错到别的仓库）', () {
    if (fluxRepositoryUrl.isEmpty || fluxIssueUrl.isEmpty) {
      return;
    }
    expect(fluxIssueUrl, startsWith(fluxRepositoryUrl));
  });

  test('开发者名与核实日期非空（关于页会展示，空串会是明显的漏填）', () {
    expect(fluxDeveloperName, isNotEmpty);
    expect(fluxMetadataVerifiedOn, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });
}
