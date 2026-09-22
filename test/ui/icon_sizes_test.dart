// 图标小尺寸辨识验证与应用图标资源测试（T051；架构第 7 节「应用图标先做小尺寸
// 辨识验证，资源纳入 MIT/第三方声明」）。
//
// 为什么需要一个**可断言**的辨识度检查，而不是「看一眼截图」：
//   图标集在 20/24 逻辑尺寸下设计，但工具栏、列表行与 macOS 的 Dock 会把它渲染到
//   16px。16px 下最典型的失效不是「变模糊」而是**结构消失**——两段弧糊成一条、
//   对勾的折角被抗锯齿抹平、状态三兄弟看起来是同一团灰。这类问题不会让任何现有
//   测试失败，只能靠像素级检查抓。因此这里把 20 档图标渲染成 16×16 位图，对每个
//   图标断言一组「结构仍然成立」的事实（墨水覆盖率区间、关键区域有墨、成对可分）。
//
// 为什么不只用 golden：golden 钉住的是**当前**像素。真实改动（把对勾缩短、把实心
// 点缩小）会让 diff 里一片红，但看不出「对勾消失了」这个意图层面的结论。这里的断言
// 写出来的是意图，失败时给的是可读原因而不是「像素不匹配」。
//
// 为什么不挂 widget 树、而是**直接**解码 SVG 再光栅化：
//   走 FluxSvgIcon + RepaintBoundary 的路线要在测试里驱动 vector_graphics 的异步
//   解码（vg.waitForPendingDecodes），而它在同一个用例里解码第二个图标时会**挂死**
//   ——第一个图标正常，之后等待点再也不返回（实测卡在第一个 testWidgets 上不动）。
//   这里改用 vg.loadPicture 直接拿解码结果，画进 16×16 画布再取 alpha：没有 widget
//   生命周期、没有帧调度，22 个图标几秒内跑完，结果只取决于 SVG 本身。
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/ui/ui.dart';

/// 被验证的小尺寸（架构第 7 节的最小档，也是 macOS Dock 的实际像素尺寸）。
const double kSmallRenderSize = 16;

/// 把一个图标渲染成 [size]×[size] 的 alpha 矩阵（取值 0..1）。
///
/// 缩放是**在画布上做**的（canvas.scale），因此 16px 的输出是真矢量渲染的结果，
/// 不是「先画 20px 再抽稀」。
Future<List<List<double>>> renderAlpha(String assetPath, double size) async {
  final PictureInfo info = await vg.loadPicture(
    SvgAssetLoader(
      assetPath,
      theme: const SvgTheme(currentColor: Color(0xFF000000)),
    ),
    null,
  );
  final int sourceWidth = info.size.width.round();
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.scale(size / sourceWidth);
  canvas.drawPicture(info.picture);
  final ui.Picture scaled = recorder.endRecording();
  final ui.Image image = scaled.toImageSync(size.toInt(), size.toInt());
  expect(image.width, size.toInt(), reason: '位图宽度不是目标尺寸，断言尺度就不对了');
  final ByteData? data = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  expect(data, isNotNull, reason: '位图读取失败，无法做辨识度断言');
  final Uint8List bytes = data!.buffer.asUint8List();
  final int width = image.width;
  final int height = image.height;
  final List<List<double>> alpha = <List<double>>[
    for (int y = 0; y < height; y++)
      <double>[
        for (int x = 0; x < width; x++) bytes[(y * width + x) * 4 + 3] / 255.0,
      ],
  ];
  image.dispose();
  scaled.dispose();
  info.picture.dispose();
  return alpha;
}

/// 墨水覆盖率（0..1）：alpha 的平均值。
double inkCoverage(List<List<double>> alpha) {
  double sum = 0;
  for (final List<double> row in alpha) {
    for (final double value in row) {
      sum += value;
    }
  }
  return sum / (alpha.length * alpha.first.length);
}

/// [left, top, right, bottom] 归一化矩形内是否有墨（任意像素 alpha ≥ threshold）。
///
/// 用「区域内有/无墨」而不是平均灰度：前者对「结构还在不在」更敏感，后者会被
/// 周围的抗锯齿灰阶稀释，导致「笔画已经断了」仍被平均成非零。
bool hasInkIn(
  List<List<double>> alpha,
  double left,
  double top,
  double right,
  double bottom, {
  double threshold = 0.35,
}) {
  final int h = alpha.length;
  final int w = alpha.first.length;
  for (int y = (top * h).floor(); y < (bottom * h).ceil(); y++) {
    for (int x = (left * w).floor(); x < (right * w).ceil(); x++) {
      if (y < 0 || y >= h || x < 0 || x >= w) {
        continue;
      }
      if (alpha[y][x] >= threshold) {
        return true;
      }
    }
  }
  return false;
}

/// 最里层「实心核心」的像素数：归一化 0.375–0.625 窗口内 alpha ≥ 0.85 的像素数。
///
/// 为什么用**接近全不透明**的核心计数，而不是中心区的平均灰度：
///   三态控件并排显示时，未读是「实心点」，已读/稍后是「描边图形」。两者的差别
///   只在最中心那几个像素上；平均灰度会把外环边缘的灰阶一起算进来，三个图标都
///   得到约 1/3，等于没区分（第一版就是这样，断言以 0.333 == 0.333 失败）。取
///   alpha ≥ 0.85 之后，未读的核心是约 3×3 的实心块，而已读与稍后只有笔画恰好
///   穿过中心的一两个像素。
int denseCore(List<List<double>> alpha) {
  int hits = 0;
  final int h = alpha.length;
  final int w = alpha.first.length;
  for (int y = (0.375 * h).round(); y < (0.625 * h).round(); y++) {
    for (int x = (0.375 * w).round(); x < (0.625 * w).round(); x++) {
      if (alpha[y][x] >= 0.85) {
        hits += 1;
      }
    }
  }
  return hits;
}

/// 两张同尺寸位图里差异明显的像素数。
int differingPixels(List<List<double>> a, List<List<double>> b) {
  int count = 0;
  for (int y = 0; y < a.length; y++) {
    for (int x = 0; x < a.first.length; x++) {
      if ((a[y][x] - b[y][x]).abs() > 0.35) {
        count += 1;
      }
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('16px 下的辨识度（20 档图标）', () {
    test('每个图标都渲染出可见内容，且不是一团实心块', () async {
      for (final FluxIcon icon in FluxIcon.values) {
        final List<List<double>> alpha = await renderAlpha(
          icon.assetPath(FluxIconSize.small),
          kSmallRenderSize,
        );
        // 覆盖率区间来自本轮**实测**：全集最低是 mark-check（细勾）约 0.07，
        // 最高是 today（本子 + 太阳）约 0.30。下界防「笔画细到消失」，
        // 上界防「糊成一团实心块」——两种都是失效，方向相反。
        final double coverage = inkCoverage(alpha);
        expect(
          coverage,
          inInclusiveRange(0.04, 0.45),
          reason:
              '${icon.name} 在 16px 下的墨水覆盖率 '
              '${coverage.toStringAsFixed(3)} 越界：过低说明笔画细到看不见，'
              '过高说明图形糊成了实心块',
        );
      }
    });

    test('状态三兄弟在 16px 下仍可互相区分', () async {
      // 这一组最容易被忽略：三个状态控件**并排**出现在每一行文章上，
      // 若它们在 16px 下趋同，用户看到的「已读/未读/稍后」就是三块一样的灰。
      Future<List<List<double>>> small(FluxIcon icon) =>
          renderAlpha(icon.assetPath(FluxIconSize.small), kSmallRenderSize);
      final List<List<double>> unread = await small(FluxIcon.stateUnread);
      final List<List<double>> read = await small(FluxIcon.stateRead);
      final List<List<double>> later = await small(FluxIcon.stateLater);

      // 外环在三个里都应存在（共有的「状态控件」外形）。
      final Map<String, List<List<double>>> byName =
          <String, List<List<double>>>{'未读': unread, '已读': read, '稍后': later};
      for (final MapEntry<String, List<List<double>>> entry in byName.entries) {
        expect(
          hasInkIn(entry.value, 0, 0.3, 0.28, 0.7),
          isTrue,
          reason: '${entry.key} 在 16px 下丢了外环左侧',
        );
        expect(
          hasInkIn(entry.value, 0.72, 0.3, 1.0, 0.7),
          isTrue,
          reason: '${entry.key} 在 16px 下丢了外环右侧',
        );
      }

      // 中心区分：unread 是实心点，read 是勾，later 是钟针（后两者都是描边）。
      final int unreadCore = denseCore(unread);
      final int readCore = denseCore(read);
      final int laterCore = denseCore(later);
      expect(
        unreadCore,
        greaterThanOrEqualTo(4),
        reason:
            '未读的实心点在中心只有 $unreadCore 个实心像素（期望 ≥4）：'
            '点被改小后「实心 vs 描边」的区分会消失',
      );
      expect(
        readCore,
        lessThan(unreadCore),
        reason:
            '已读的对勾在中心有 $readCore 个实心像素，应少于未读的实心点 '
            '（$unreadCore）——否则「实心点」与「描边勾」在 16px 下不再可分',
      );
      expect(
        laterCore,
        lessThan(unreadCore),
        reason:
            '稍后的钟针在中心有 $laterCore 个实心像素，应少于未读的实心点 '
            '（$unreadCore）',
      );
      final int readVsLater = differingPixels(read, later);
      expect(
        readVsLater,
        greaterThanOrEqualTo(6),
        reason:
            '已读（勾）与稍后（钟）在 16px 下只有 $readVsLater 个像素不同，'
            '并排显示时会难以区分',
      );
    });

    test('导航三图标（今日/RSS/设置）的墨水分布互不相同', () async {
      // 侧栏与底栏把这三个并排放置，形状差异必须保留。
      final Map<FluxIcon, List<List<double>>> rendered =
          <FluxIcon, List<List<double>>>{};
      for (final FluxIcon icon in <FluxIcon>[
        FluxIcon.today,
        FluxIcon.rss,
        FluxIcon.sliders,
      ]) {
        rendered[icon] = await renderAlpha(
          icon.assetPath(FluxIconSize.small),
          kSmallRenderSize,
        );
      }
      final List<FluxIcon> keys = rendered.keys.toList();
      for (int i = 0; i < keys.length; i++) {
        for (int j = i + 1; j < keys.length; j++) {
          final int differing = differingPixels(
            rendered[keys[i]]!,
            rendered[keys[j]]!,
          );
          expect(
            differing,
            greaterThanOrEqualTo(8),
            reason:
                '${keys[i].name} 与 ${keys[j].name} 在 16px 下仅 $differing '
                '个像素不同，同排显示时会分不清',
          );
        }
      }
    });
  });

  group('资源与许可清单（T051 收尾核对）', () {
    test('每个图标 SVG 顶部都有 MIT 原创声明', () {
      for (final FluxIcon icon in FluxIcon.values) {
        for (final String path in icon.allAssetPaths) {
          final File file = File(path);
          expect(file.existsSync(), isTrue, reason: '缺少资源 $path');
          expect(
            file.readAsLinesSync().take(2).join('\n'),
            contains('Original artwork for Flux, MIT License'),
            reason: '$path 顶部缺少原创与 MIT 声明',
          );
        }
      }
    });

    test('应用图标设计源存在、带 MIT 声明，且不作为运行期资源打包', () {
      const String source = 'assets/branding/flux-app-icon.svg';
      final File file = File(source);
      expect(file.existsSync(), isTrue, reason: '缺少应用图标设计源 $source');
      expect(
        file.readAsLinesSync().take(2).join('\n'),
        contains('Original artwork for Flux, MIT License'),
        reason: '$source 顶部缺少原创与 MIT 声明',
      );
      // 设计源是**构建期输入**：按 tool/generate_app_icon.sh 派生 PNG 后交给
      // Xcode 的 asset catalog。把它加进 pubspec 的 assets 只会白占包体积。
      expect(
        File('pubspec.yaml').readAsStringSync(),
        isNot(contains('assets/branding')),
        reason: '应用图标设计源不应声明为运行期资源',
      );
    });

    test('macOS AppIcon 的七个尺寸齐全，且与 Contents.json 一一对应', () {
      const String dir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
      final String manifest = File('$dir/Contents.json').readAsStringSync();
      for (final int size in <int>[16, 32, 64, 128, 256, 512, 1024]) {
        expect(
          File('$dir/app_icon_$size.png').existsSync(),
          isTrue,
          reason: '缺少 app_icon_$size.png',
        );
        expect(
          manifest,
          contains('app_icon_$size.png'),
          reason: 'Contents.json 未引用 app_icon_$size.png',
        );
      }
    });

    test('第三方声明文件存在，且列出了全部直接运行时依赖', () {
      final File notices = File('docs/THIRD-PARTY-NOTICES.md');
      expect(notices.existsSync(), isTrue, reason: '缺少第三方声明文件');
      final String text = notices.readAsStringSync();
      // 断言「清单里有这些包」，而不是「清单逐字符合某个模板」：后者会让每次
      // 依赖升级都要改测试。完整性由生成器保证（它直接读 pubspec.lock），
      // 这里防的是「文件被手改成一份残缺的清单」。
      for (final String package in <String>[
        'drift',
        'flutter_riverpod',
        'flutter_svg',
        'markdown',
        'flutter_math_fork',
        'xml',
        'file_selector',
        'url_launcher',
        'sqlite3',
        'http',
        'path_provider',
        'intl',
        'cupertino_icons',
      ]) {
        expect(
          text,
          contains('| $package |'),
          reason: '第三方声明缺少直接运行时依赖 $package',
        );
      }
      expect(text, contains('MIT'), reason: '声明里应写明本仓库自身的许可证');
    });
  });
}
