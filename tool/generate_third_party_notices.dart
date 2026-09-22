// 生成 docs/THIRD-PARTY-NOTICES.md（T051；架构第 7 节「资源纳入 MIT/第三方声明」）。
//
// 为什么是**生成**而不是手写一份：
//   手写清单只能保证「写的那一刻是对的」。依赖一升级（pubspec.lock 里 version 变了）
//   或新增一个包，清单就会静默过期，而对外发布物里缺一条许可证是实质问题，不是文档
//   瑕疵。生成 + 测试断言（test/app/third_party_notices_test.dart）让「清单与锁文件
//   不一致」变成一次失败的测试。
//
// 数据来源是**已提交的 pubspec.lock**，不是 pubspec.yaml 的约束范围：清单要对应实际
// 会被构建进包里的那一个版本，而不是「>=x.y.z 的某个版本」。
//
// 为什么自己按行解析 lock 而不用 package:yaml：
//   yaml 只是传递依赖（经 flutter_lints/build_runner 引入）。为一个只在开发期跑的脚本
//   把一个传递依赖提升为直接依赖，会让依赖面变大，收益却只是少写三十行解析；而 lock
//   的格式由 pub 自己写死、字段顺序稳定，按行扫描足够。
//
// 用法：dart run tool/generate_third_party_notices.dart
// 校验：flutter test test/app/third_party_notices_test.dart
library;

import 'dart:io';

/// 输出路径。
const String outputPath = 'docs/THIRD-PARTY-NOTICES.md';

/// 反引号字符。用转义写法而不是字面量：本文件由补丁写入，源码里出现反引号
/// 字面量会与补丁的边界标记混淆。
const String bt = '\u0060';

/// 把文本包成 Markdown 行内代码跨度。
///
/// 抽成函数而不是到处写字符串拼接：少了「变量名紧跟文本」这类错误（Dart 会把
/// 标识符连着读下去，必须加花括号），并且「这里需要行内代码」这个意图在调用点
/// 一眼可见。
String code(String text) => bt + text + bt;

/// 超长文本截断（过长的版权行会撑坏 Markdown 表格的排版）。
String clip(String text, {int max = 120}) {
  if (text.length <= max) {
    return text;
  }
  return '${text.substring(0, max - 3)}...';
}

/// 一条锁定依赖。
final class LockedPackage {
  /// 构造记录。
  const LockedPackage({
    required this.name,
    required this.version,
    required this.dependency,
    required this.source,
  });

  /// 包名。
  final String name;

  /// 锁定版本（SDK 来源时为 0.0.0）。
  final String version;

  /// 依赖类型：direct main / direct dev / transitive。
  final String dependency;

  /// 来源：hosted / sdk。
  final String source;
}

/// 解析 pubspec.lock 的 packages 段。
///
/// 只取四行信息；description 里的 sha256/url 与清单无关，跳过。
List<LockedPackage> parseLock(String content) {
  final List<LockedPackage> packages = <LockedPackage>[];
  String? name;
  String? dependency;
  String? source;
  String? version;

  void flush() {
    if (name != null && dependency != null && source != null) {
      packages.add(
        LockedPackage(
          name: name!,
          version: version ?? '',
          dependency: dependency!,
          source: source!,
        ),
      );
    }
    name = null;
    dependency = null;
    source = null;
    version = null;
  }

  bool inPackages = false;
  for (final String line in content.split('\n')) {
    if (line.startsWith('packages:')) {
      inPackages = true;
      continue;
    }
    // sdks: 段标志 packages 段结束。
    if (inPackages && line.startsWith('sdks:')) {
      flush();
      inPackages = false;
      continue;
    }
    if (!inPackages) {
      continue;
    }
    // 顶层包名：两个空格缩进、以冒号结尾。
    final RegExpMatch? pkg = RegExp(r'^  ([A-Za-z0-9_]+):$').firstMatch(line);
    if (pkg != null) {
      flush();
      name = pkg.group(1);
      continue;
    }
    final String trimmed = line.trim();
    if (trimmed.startsWith('dependency:')) {
      dependency = trimmed
          .substring('dependency:'.length)
          .trim()
          .replaceAll('"', '');
    } else if (trimmed.startsWith('source:')) {
      source = trimmed.substring('source:'.length).trim();
    } else if (trimmed.startsWith('version:') && version == null) {
      version = trimmed.substring('version:'.length).trim().replaceAll('"', '');
    }
  }
  flush();
  return packages;
}

/// 从 LICENSE 正文推断许可证标识。
///
/// 用正文匹配而不是维护一张「包名 → 许可证」的表：表会随依赖变化过期，而 LICENSE
/// 正文是官方发布物的一部分。识别不出来时返回「见正文」，并在清单里保留版权首行
/// ——宁可标「见正文」，也不猜一个可能错误的 SPDX 标识。
String licenseNameFor(String text) {
  final String lower = text.toLowerCase();
  if (lower.contains('apache license') && lower.contains('version 2.0')) {
    return 'Apache-2.0';
  }
  if (lower.contains('mozilla public license') && lower.contains('2.0')) {
    return 'MPL-2.0';
  }
  if (lower.contains('bsd 3-clause') ||
      (lower.contains('redistribution and use') &&
          lower.contains('neither the name'))) {
    return 'BSD-3-Clause';
  }
  if (lower.contains('bsd 2-clause')) {
    return 'BSD-2-Clause';
  }
  if (lower.contains('mit license') ||
      (lower.contains('permission is hereby granted, free of charge') &&
          !lower.contains('apache'))) {
    return 'MIT';
  }
  return '见正文';
}

/// 版权行正则。
///
/// 四个条件同时成立才算归属声明：
///   1) 行首（允许 Portions 之类的前缀）就是 Copyright / ©，或行内含 (c)；
///   2) 该行带**年份**（19xx / 20xx）—— 真正的版权声明几乎总带年份；
/// 只写 contains('copyright') 会把 Apache-2.0 的术语正文抄进清单：那份 LICENSE 里
/// 「"Licensor" shall mean the copyright owner…」与「copyright notice that is
/// included in or attached to the work」这类句子都含 copyright，却与归属无关。
/// 加年份约束后这两类都被排除，而 "Copyright (c) 2016 Vladimir Kharlampidi" 这类
/// 真声明仍然命中。
final RegExp _copyrightPattern = RegExp(
  r'^(portions?[[:space:]]+)?(copyright|©)|\(c\)',
  caseSensitive: false,
);

/// 年份正则（版权行必须带年份，见 [_copyrightPattern] 的说明）。
final RegExp _yearPattern = RegExp(r'(19|20)[0-9]{2}');

/// 取 LICENSE 的版权行；没有可识别的版权行时返回空串（调用点据此写「未单独署名」）。
///
/// 刻意**不**做「都没有时退回首个非空行」的兜底：Apache-2.0 这类正文的首个非空行是
/// 许可证标题或版本号，兜底会把「Version 2.0, January 2004」当成版权人写进对外声明。
/// 宁可如实说「该包的 LICENSE 正文里没有单独的版权行」，也不填一条错的信息。
String copyrightLineFor(String text) {
  for (final String raw in text.split('\n')) {
    final String line = raw.trim();
    if (line.isEmpty) {
      continue;
    }
    if (_copyrightPattern.hasMatch(line) && _yearPattern.hasMatch(line)) {
      return clip(line);
    }
  }
  return '';
}

/// pub 缓存的 hosted 目录。
Directory pubCacheHosted() {
  final Map<String, String> env = Platform.environment;
  final String? cache = env['PUB_CACHE'];
  if (cache != null && cache.isNotEmpty) {
    return Directory('$cache/hosted/pub.dev');
  }
  final String home = env['HOME'] ?? '';
  return Directory('$home/.pub-cache/hosted/pub.dev');
}

/// 读某个锁定版本的 LICENSE 文本；找不到时返回 null。
String? readLicense(Directory hosted, LockedPackage pkg) {
  final Directory dir = Directory('${hosted.path}/${pkg.name}-${pkg.version}');
  if (!dir.existsSync()) {
    return null;
  }
  for (final String candidate in <String>[
    'LICENSE',
    'LICENSE.md',
    'LICENSE.txt',
    'License',
    'license',
    'COPYING',
  ]) {
    final File file = File('${dir.path}/$candidate');
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }
  return null;
}

/// 应用版本（读 pubspec.yaml 的 version 行）。
String appVersion() {
  for (final String line in File('pubspec.yaml').readAsLinesSync()) {
    if (line.startsWith('version:')) {
      return line.substring('version:'.length).trim();
    }
  }
  return '未标注';
}

/// 生成清单正文。
String buildNotices(List<LockedPackage> packages, Directory hosted) {
  final List<LockedPackage> hostedPackages =
      packages.where((LockedPackage p) => p.source == 'hosted').toList()
        ..sort((LockedPackage a, LockedPackage b) => a.name.compareTo(b.name));

  final String ref0 = code('dart run tool/generate_third_party_notices.dart');
  final String ref1 = code('pubspec.lock');
  final String ref2 = code('test/app/third_party_notices_test.dart');
  final String ref3 = code('LICENSE');
  final String ref4 = code('assets/icons/');
  final String ref5 = code('assets/branding/flux-app-icon.svg');
  final String ref6 = code('sqlite3');
  final String ref7 = code('packages');
  final StringBuffer out = StringBuffer();
  out.writeln('# 第三方软件与原创素材声明');
  out.writeln();
  out.writeln('> 本文件由 $ref0生成，请勿手改。');
  out.writeln(
    '> 版本号取自已提交的 $ref1（本应用提交 lock，'
    '因此清单对应实际构建的版本）。',
  );
  out.writeln('> $ref2会断言本文件与 lock 一致。');
  out.writeln();
  out.writeln('## Flux 自身');
  out.writeln();
  out.writeln('| 项目 | 版本 | 许可证 | 版权 |');
  out.writeln('| --- | --- | --- | --- |');
  out.writeln(
    '| Flux（本仓库） | ${appVersion()} | MIT | Copyright (c) 2025 GuZhengSVT |',
  );
  out.writeln();
  out.writeln('仓库根 $ref3为 MIT。原创素材（$ref4下的 28 个 SVG、');
  out.writeln(
    '$ref5应用图标设计源）由本项目绘制，'
    '同样按 MIT 授权；每个素材文件顶部都有各自的授权注释。',
  );
  out.writeln();
  out.writeln('## 运行时依赖（会进入发布包）');
  out.writeln();
  out.writeln('| 包 | 版本 | 许可证 | 版权声明（LICENSE 中的版权行） |');
  out.writeln('| --- | --- | --- | --- |');

  final List<String> missing = <String>[];
  int directMain = 0;
  for (final LockedPackage pkg in hostedPackages) {
    if (pkg.dependency != 'direct main') {
      continue;
    }
    final String? text = readLicense(hosted, pkg);
    if (text == null) {
      missing.add(pkg.name);
      continue;
    }
    directMain += 1;
    final String copyright = copyrightLineFor(text);
    out.writeln(
      '| ${pkg.name} | ${pkg.version} | ${licenseNameFor(text)} | '
      '${copyright.isEmpty ? '未单独署名（见包内 LICENSE 正文）' : copyright} |',
    );
  }
  out.writeln();
  out.writeln('### Flutter / Dart SDK');
  out.writeln();
  out.writeln(
    'Flutter 与 Dart SDK 按 BSD-3-Clause 授权'
    '（Copyright 2014 The Flutter Authors. All rights reserved.），随工具链分发，'
    '不逐版本抄录正文。',
  );
  out.writeln();
  out.writeln('### 静态链接的原生库');
  out.writeln();
  out.writeln('SQLite（经 $ref6包的 native assets 机制带入）为 Public Domain。');
  out.writeln();

  final List<LockedPackage> dev = hostedPackages
      .where((LockedPackage p) => p.dependency == 'direct dev')
      .toList();
  final int transitive = hostedPackages
      .where((LockedPackage p) => p.dependency == 'transitive')
      .length;

  out.writeln('## 开发期依赖（不进入发布包）');
  out.writeln();
  out.writeln('以下包只在开发/测试期使用，不随应用分发：');
  out.writeln();
  for (final LockedPackage pkg in dev) {
    final String? text = readLicense(hosted, pkg);
    final String suffix = text == null ? '' : '（${licenseNameFor(text)}）';
    out.writeln('- ${pkg.name} ${pkg.version}$suffix');
  }
  out.writeln();
  out.writeln(
    '另有 $transitive 个传递依赖（由上述包引入），许可证随各自发布的包分发；'
    '完整列表见 $ref1的 $ref7段。'
    '本应用不直接引用它们的 API。',
  );
  out.writeln();
  out.writeln('## 与许可证相关的已知取舍');
  out.writeln();
  out.writeln(
    '- **不使用 WebView 或网页运行时**（架构第 8 节）：数学排版走 flutter_math_fork '
    '纯自绘，Markdown 只调用解析器，因此不存在内嵌浏览器内核的许可证与安全面。',
  );
  out.writeln('- **不引入在线字体或图标库**：图标为自制 SVG，字体只用系统字体。');
  out.writeln(
    '- 无法辨认许可证正文的包不会被写成某一种许可证（清单里标「见正文」），'
    '避免在发布物里给出错误的 SPDX 标识。',
  );
  out.writeln();
  if (missing.isNotEmpty) {
    out.writeln('### 未在本地 pub 缓存找到 LICENSE 的运行时依赖');
    out.writeln();
    for (final String name in missing) {
      out.writeln('- $name');
    }
    out.writeln();
  }
  if (directMain == 0) {
    out.writeln('（未解析到任何直接运行时依赖：检查 pub 缓存是否可用。）');
    out.writeln();
  }
  return out.toString();
}

void main() {
  final File lock = File('pubspec.lock');
  if (!lock.existsSync()) {
    stderr.writeln('找不到 pubspec.lock，请在仓库根运行');
    exitCode = 1;
    return;
  }
  final List<LockedPackage> packages = parseLock(lock.readAsStringSync());
  final String notices = buildNotices(packages, pubCacheHosted());
  File(outputPath).writeAsStringSync(notices);
  stdout.writeln('已写入 $outputPath（${packages.length} 个锁定包）');
}
