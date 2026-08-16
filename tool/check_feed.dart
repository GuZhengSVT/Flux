import 'dart:io';

import 'package:flux/services/feed_parser.dart';

Future<void> main() async {
  final xml = await File('/tmp/flux_feed.xml').readAsString();
  final parsed = const FeedParser().parse(
    xml,
    'https://www.guzhengsvt.cn/zh-cn/index.xml',
  );

  stdout.writeln('Feed: ${parsed.title}');
  stdout.writeln('Articles: ${parsed.articles.length}');
  var images = 0;
  var inlineMath = 0;
  var displayMath = 0;
  for (final article in parsed.articles) {
    final content = article.contentHtml ?? '';
    images += RegExp(r'<img\b').allMatches(content).length;
    inlineMath += RegExp(r'(?<!\$)\$(?!\$)[^\$]+\$').allMatches(content).length;
    displayMath += RegExp(
      r'\$\$[^$]+\$\$',
      dotAll: true,
    ).allMatches(content).length;
  }
  stdout.writeln('Total images: $images');
  stdout.writeln('Inline math segments: $inlineMath');
  stdout.writeln('Display math segments: $displayMath');
  final first = parsed.articles.first;
  stdout.writeln('First article: ${first.title}');
  stdout.writeln(
    'First article has content: ${(first.contentHtml ?? '').isNotEmpty}',
  );
  stdout.writeln('First article first image: ${first.imageUrl}');
}
