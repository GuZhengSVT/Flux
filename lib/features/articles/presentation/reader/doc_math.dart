// 正文里的数学排版（T019；架构 4.2「常用 LaTeX 数学」、D-05）。
//
// flutter_math_fork 在**纯 Dart/Flutter 里自绘**：解析 TeX 后在本地完成布局。没有 WebView、
// 没有 KaTeX JavaScript、没有远端渲染服务——因此它符合 D-05 与架构第 8 节对「不引入浏览器
// 运行时」的约束，也不产生任何网络请求。
//
// 不支持的命令必须**显示原式与提示**，不能空白或冒充成功（架构 4.2 明写）。实现上靠
// Math.tex 的 onErrorFallback：解析抛错时它给我们一个渲染替换内容的机会，而这里交出的
// 是 [UnsupportedMathView]——原文 + 原因。
library;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_math_fork/tex.dart';

import 'package:flux/l10n/l10n.dart';

import 'doc_theme.dart';

/// 用打包的 TeX 解析器试解析 [tex]。
///
/// 供测试与「提交前先问一句」的场景使用：界面不靠它决定画什么（那只由 Math.tex 的
/// 失败回调决定），因此这里不会与真实渲染路径产生第二套判定。
({bool ok, String? message}) tryParseTex(String tex) {
  if (tex.trim().isEmpty) {
    return (ok: false, message: 'empty expression');
  }
  try {
    TexParser(tex, const TexParserSettings()).parse();
    return (ok: true, message: null);
  } on ParseException catch (error) {
    return (ok: false, message: error.message.split('\n').first);
  } catch (error) {
    return (ok: false, message: error.toString().split('\n').first);
  }
}

/// 行内公式。
class DocInlineMath extends StatelessWidget {
  /// 构造行内公式。
  const DocInlineMath({super.key, required this.tex, required this.typography});

  /// TeX 正文。
  final String tex;

  /// 排版。
  final DocTypography typography;

  @override
  Widget build(BuildContext context) {
    return Math.tex(
      tex,
      mathStyle: MathStyle.text,
      textStyle: TextStyle(
        fontSize: typography.baseSize,
        color: typography.theme.textPrimary,
      ),
      onErrorFallback: (FlutterMathException error) => UnsupportedMathView(
        tex: tex,
        reason: error.message.split('\n').first,
        typography: typography,
        inline: true,
      ),
    );
  }
}

/// 独占一行的公式。
class DocBlockMath extends StatelessWidget {
  /// 构造块级公式。
  const DocBlockMath({super.key, required this.tex, required this.typography});

  /// TeX 正文。
  final String tex;

  /// 排版。
  final DocTypography typography;

  @override
  Widget build(BuildContext context) {
    // 宽公式在自己的块内横向滚动（架构第 7 节：长公式只做块内横向滚动），
    // 因此一个矩阵或长对齐环境永远撑不破阅读栏。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Math.tex(
        tex,
        mathStyle: MathStyle.display,
        textStyle: TextStyle(
          fontSize: typography.baseSize * 1.1,
          color: typography.theme.textPrimary,
        ),
        onErrorFallback: (FlutterMathException error) => UnsupportedMathView(
          tex: tex,
          reason: error.message.split('\n').first,
          typography: typography,
          inline: false,
        ),
      ),
    );
  }
}

/// 公式渲染失败时的提示：原式 + 原因（绝不空白）。
class UnsupportedMathView extends StatelessWidget {
  /// 构造失败提示。
  const UnsupportedMathView({
    super.key,
    required this.tex,
    required this.reason,
    required this.typography,
    required this.inline,
  });

  /// 原始 TeX。
  final String tex;

  /// 原因。
  final String reason;

  /// 排版。
  final DocTypography typography;

  /// 是否行内（决定内边距与圆角）。
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DocTheme theme = typography.theme;
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          l10n.readingMathUnsupported,
          style: TextStyle(
            fontSize: typography.baseSize * 0.75,
            color: theme.danger,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          r'$' + tex + r'$',
          style: typography.inlineCode.copyWith(color: theme.danger),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.readingMathUnsupportedReason(reason),
          style: TextStyle(
            fontSize: typography.baseSize * 0.7,
            color: theme.textSecondary,
          ),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.warningSurface,
        borderRadius: BorderRadius.circular(inline ? 4 : 8),
        border: Border.all(color: theme.danger.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: inline
            ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
            : const EdgeInsets.all(12),
        child: content,
      ),
    );
  }
}
