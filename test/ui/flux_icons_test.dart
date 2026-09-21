// 原创图标资源测试（T012）。
//
// 这些断言针对的是**资源文件本身**，不是渲染结果。理由：
//   - SVG 是手写的几何图形，最容易出的错是「线宽越界」「忘了 currentColor」
//     「漏了许可证注释」「只做了 24 没做 20」。这些在 golden 里都不明显
//     （1.4 与 1.5 的线宽差在截图上几乎看不出来），但在设计规范里是硬约束；
//   - 资源清单与 pubspec 声明必须一一对应：多声明一个不存在的目录/文件会让
//     flutter build 失败，少声明会让运行期图标变空白。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/ui/ui.dart';

/// 图标资源目录。
const String _iconDir = 'assets/icons';

/// 每个 SVG 必须有的许可证声明（架构：项目代码及原创素材选择 MIT，SVG 由模型绘制）。
const String _licenseLine =
    'Original artwork for Flux, MIT License (c) 2025 GuZhengSVT';

void main() {
  group('资源清单', () {
    test('每个图标都有 20 与 24 两套逻辑尺寸，且文件真实存在', () {
      for (final FluxIcon icon in FluxIcon.values) {
        expect(
          icon.allAssetPaths,
          hasLength(2),
          reason: '$icon.fileBaseName 必须同时有 20 与 24 两套尺寸',
        );
        for (final String path in icon.allAssetPaths) {
          expect(File(path).existsSync(), isTrue, reason: '缺少图标资源 $path');
        }
      }
    });

    test('磁盘上没有未被枚举登记的 SVG（防止新增素材忘记接入）', () {
      final Set<String> onDisk = Directory(_iconDir)
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.svg'))
          .map((File f) => f.path.split('/').last)
          .toSet();
      final Set<String> declared = <String>{
        for (final FluxIcon icon in FluxIcon.values)
          ...icon.allAssetPaths.map((String p) => p.split('/').last),
      };
      expect(
        onDisk.difference(declared),
        isEmpty,
        reason: '这些 SVG 未在 FluxIcon 中登记，界面无法引用',
      );
      expect(
        declared.difference(onDisk),
        isEmpty,
        reason: '这些登记的资源在磁盘上不存在，运行期会渲染空白',
      );
    });

    test('pubspec.yaml 声明了 assets/icons/ 目录', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/icons/'), reason: '未声明资源目录时图标不会被打进包');
    });
  });

  group('资源内容符合美术标准（架构第 7 节）', () {
    test('每个 SVG 顶部都有 MIT 原创声明', () {
      for (final FluxIcon icon in FluxIcon.values) {
        for (final String path in icon.allAssetPaths) {
          final String content = File(path).readAsStringSync();
          expect(content, contains(_licenseLine), reason: '$path 缺少原创与许可声明');
          // 声明必须在文件顶部（注释形式），而不是被塞在末尾。
          expect(
            content.indexOf(_licenseLine),
            lessThan(200),
            reason: '$path 的许可声明不在文件顶部',
          );
        }
      }
    });

    test('线宽落在 1.5–2 之间，且与枚举声明的值一致', () {
      final RegExp stroke = RegExp(r'stroke-width="([0-9.]+)"');
      for (final FluxIcon icon in FluxIcon.values) {
        for (final FluxIconSize size in FluxIconSize.values) {
          final String path = icon.assetPath(size);
          final RegExpMatch? match = stroke.firstMatch(
            File(path).readAsStringSync(),
          );
          expect(match, isNotNull, reason: '$path 未声明 stroke-width');
          final double width = double.parse(match!.group(1)!);
          expect(
            width,
            inInclusiveRange(
              FluxIconTokens.strokeMin,
              FluxIconTokens.strokeMax,
            ),
            reason: '$path 线宽 $width 超出架构第 7 节的 1.5–2',
          );
          expect(width, icon.strokeWidthFor(size), reason: '$path 的线宽与枚举声明不一致');
        }
      }
    });

    test('素材用 currentColor 而非固定颜色（保证跟随主题与控件状态）', () {
      // 固定颜色只允许出现在 fill/stroke 之外的场合；实心图形也必须用
      // currentColor，否则深色主题下会留下一个黑色实心块。
      final RegExp hardCoded = RegExp(
        r'(?:fill|stroke)="(#[0-9A-Fa-f]{3,8}|black|white|red|blue|gray|grey)"',
      );
      for (final FluxIcon icon in FluxIcon.values) {
        for (final String path in icon.allAssetPaths) {
          final String content = File(path).readAsStringSync();
          expect(
            hardCoded.firstMatch(content),
            isNull,
            reason: '$path 含有固定颜色，图标将无法跟随主题',
          );
          expect(
            content,
            contains('currentColor'),
            reason: '$path 未使用 currentColor',
          );
        }
      }
    });

    test('viewBox 与声明的逻辑尺寸一致（20 与 24 不是同一张图缩放而来）', () {
      for (final FluxIcon icon in FluxIcon.values) {
        for (final FluxIconSize size in FluxIconSize.values) {
          final String path = icon.assetPath(size);
          final String content = File(path).readAsStringSync();
          // 20 尺寸的文件用 20 的坐标系：若用 0 0 24 24 再缩小，线宽会被视觉
          // 缩放成 1.75*20/24≈1.46（低于下界），设计规范就失去了意义。
          final String viewBox = size == FluxIconSize.small
              ? 'viewBox="0 0 20 20"'
              : 'viewBox="0 0 24 24"';
          expect(content, contains(viewBox), reason: '$path 的坐标系不正确');
          // 用整数字面量断言：SVG 里写的是 20/24，而 logicalSize 是 double
          // （20.0/24.0），直接插值会得到 "20.0" 这种资源里不存在的写法。
          final String sizeLiteral = size.logicalSize.toInt().toString();
          expect(
            content,
            contains('width="$sizeLiteral"'),
            reason: '$path 的 width 与逻辑尺寸不符',
          );
          expect(
            content,
            contains('height="$sizeLiteral"'),
            reason: '$path 的 height 与逻辑尺寸不符',
          );
        }
      }
    });

    test('素材不含脚本、外链与事件处理（架构第 8 节：不可信资源也要在边界校验）', () {
      for (final FluxIcon icon in FluxIcon.values) {
        for (final String path in icon.allAssetPaths) {
          final String content = File(path).readAsStringSync();
          for (final String forbidden in <String>[
            '<script',
            'onload',
            'onclick',
            'xlink:href',
            '<image',
            'href="http',
          ]) {
            expect(
              content.contains(forbidden),
              isFalse,
              reason: '$path 含有不允许的内容：$forbidden',
            );
          }
        }
      }
    });
  });
}
