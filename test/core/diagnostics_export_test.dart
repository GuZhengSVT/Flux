// T048：诊断导出包的**纯规则**（SET-082、架构第 8 节）。
//
// 这些断言的全部意义是：**包里不可能出现原文、prompt 与凭据**。它们是逐字段可枚举的封闭集合
// 加上两层脱敏，因此可以对着「白名单之外的东西进不去」与「秘密形状被抹掉」逐条验证。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

void main() {
  const DiagnosticsReportBuilder builder = DiagnosticsReportBuilder();

  DiagnosticsSection section(String title, Map<String, String> fields) =>
      DiagnosticsSection(
        title: title,
        fields: <DiagnosticsField>[
          for (final MapEntry<String, String> e in fields.entries)
            DiagnosticsField(name: e.key, value: e.value),
        ],
      );

  String build({
    Map<String, String> system = const <String, String>{
      'appVersion': '0.2.0+1',
    },
    Map<String, String> storage = const <String, String>{},
    Map<String, String> sync = const <String, String>{},
    Map<String, String> log = const <String, String>{},
  }) => builder.build(
    system: section('system', system),
    storage: section('storage', storage),
    sync: section('sync', sync),
    log: section('log', log),
  );

  group('白名单：包里只能有列举的字段', () {
    test('白名单之外的字段被丢掉（不是报错、也不是写进去）', () {
      final String report = build(
        system: <String, String>{
          'appVersion': '0.2.0+1',
          // 这些都不在白名单里：它们是「顺手加一个字段」最可能的样子。
          'articleBody': '这是文章的原文正文',
          'promptText': '你是一个新闻编辑',
          'webdavUrl': 'https://dav.example/remote.php',
        },
      );
      expect(report, contains('appVersion=0.2.0+1'));
      expect(report, isNot(contains('articleBody')));
      expect(report, isNot(contains('promptText')));
      expect(report, isNot(contains('webdavUrl')));
      expect(report, isNot(contains('原文正文')));
      expect(report, isNot(contains('新闻编辑')));
      expect(report, isNot(contains('dav.example')));
    });

    test('同步小节不接受地址与用户名（只需要协议行为）', () {
      final String report = build(
        sync: <String, String>{
          'capability': 'conditionalWrite',
          'serverUrl': 'https://dav.example/remote.php/dav',
          'username': 'someone@example.com',
        },
      );
      expect(report, contains('capability=conditionalWrite'));
      expect(report, isNot(contains('serverUrl')));
      expect(report, isNot(contains('username')));
      expect(report, isNot(contains('dav.example')));
      expect(
        report,
        isNot(contains('someone@example.com')),
        reason: '用户名足以说明是谁在用哪个服务',
      );
    });

    test('四节的小节名固定可解析（不是本地化文案）', () {
      final String report = build(
        storage: <String, String>{'articleCount': '3'},
      );
      for (final String title in <String>['system', 'storage', 'sync', 'log']) {
        expect(report, contains('[$title]'));
      }
      expect(report, startsWith('flux-diagnostics v1'));
    });
  });

  group('脱敏：两层都生效', () {
    test('sk- 密钥、Bearer、URL query 秘密、userinfo 都被抹掉', () {
      final String report = build(
        system: <String, String>{
          'osName': 'macos with sk-abcdefghijklmnop1234 leaked',
          'osVersion': 'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig',
          'dartVersion': 'see https://api.example/v1?api_key=SECRETVALUE&x=1',
          'cpuArchitecture': 'fetch https://user:hunter2@example.com/feed.xml',
        },
      );
      expect(report, isNot(contains('sk-abcdefghijklmnop1234')));
      expect(report, contains(SecretRedaction.masked));
      expect(report, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(report, isNot(contains('SECRETVALUE')));
      expect(report, isNot(contains('hunter2')));
    });

    test('值里的换行被单行化（一个字段不能伪造出多行）', () {
      final String report = build(
        log: <String, String>{
          'logText': 'line1\n[system]\nfake=injected\nmore',
        },
      );
      final List<String> lines = report
          .split('\n')
          .where((String l) => l.startsWith('logText='))
          .toList();
      expect(lines.length, 1, reason: '一个字段只占一行');
      expect(lines.single, contains('line1'));
      expect(lines.single, contains('fake=injected'));
    });

    test('整篇再跑一遍脱敏：**只有拼装后**才形成的 `名字=值` 形状也被抹掉', () {
      // 这条覆盖「只信写入时脱敏」会漏掉的那种情形：一个**值本身**不含任何秘密形状的字段
      // （`s3cr3tValue` 单看只是普通字符串），只有它被拼进一行之后才形成 `password=<值>`。
      //
      // 这里用小节标题承载它（字段名会被白名单过滤掉，因此用字段验不出这一层）：标题在报告里
      // 被写成 `[<title>]`，拼装后正是 `[password=s3cr3tValue]` 这样一个可识别的秘密形状。
      // 逐值脱敏对标题无能为力——抹掉它的只能是最后一次整篇重扫。
      final String report = builder.build(
        system: section('password=s3cr3tValue', <String, String>{
          'appVersion': 'x',
        }),
        storage: section('storage', <String, String>{}),
        sync: section('sync', <String, String>{}),
        log: section('log', <String, String>{}),
      );
      expect(
        report,
        isNot(contains('s3cr3tValue')),
        reason: '拼装后的整体重扫必须覆盖标题这类不经过逐值脱敏的位置',
      );
    });
  });

  group('白名单自身的一致性', () {
    test('四节字段名互不重复（同一名字出现在两节会让读者分不清是哪一个）', () {
      final List<String> all = DiagnosticsAllowlist.all;
      expect(all.toSet().length, all.length);
    });

    test('每个字段名都是「量」而不是「内容」：秘密词只在带测量后缀时出现', () {
      // 「不出现 body/prompt 字样」这种粗暴检查会误伤 `newsSummaryBytes`（那是**字节数**，
      // 不是总结内容），而放过一个真正的 `summaryText`。因此这里判的是**形状**：名字里含
      // 内容类词（body/summary/title/prompt/content/text）时，必须带一个测量或状态后缀
      // （Bytes / Count / Entries / Present / Entries / Text 例外见下）。
      const List<String> contentWords = <String>[
        'body',
        'summary',
        'title',
        'prompt',
        'content',
        'text',
      ];
      const List<String> measurementSuffixes = <String>[
        'Bytes',
        'Count',
        'Entries',
        'Present',
        'At',
        'Mode',
        'Locale',
      ];
      for (final String name in DiagnosticsAllowlist.all) {
        final String lower = name.toLowerCase();
        final bool looksLikeContent = contentWords.any(lower.contains);
        if (!looksLikeContent) {
          continue;
        }
        // `logText` 是唯一刻意允许的整段文本：它是**已经脱敏**的日志行，而不是用户内容
        // （日志的写入与导出各自跑过一遍脱敏，见 diagnostics.dart）。
        if (name == 'logText') {
          continue;
        }
        expect(
          measurementSuffixes.any(name.endsWith),
          isTrue,
          reason: '$name 含有内容类词却不带测量后缀——它看起来会承载用户内容',
        );
      }
    });

    test('白名单里没有任何凭据类字段名', () {
      for (final String name in DiagnosticsAllowlist.all) {
        final String lower = name.toLowerCase();
        for (final String banned in <String>[
          'token',
          'secret',
          'password',
          'credential',
          'apikey',
          'api_key',
        ]) {
          expect(lower.contains(banned), isFalse, reason: '$name 看起来像凭据字段');
        }
      }
    });

    test('系统小节不允许出现完整路径（路径里有用户名）', () {
      expect(
        DiagnosticsAllowlist.system,
        contains('dataDirectoryPresent'),
        reason: '只报存在性',
      );
      expect(
        DiagnosticsAllowlist.system.any((String n) => n.contains('Path')),
        isFalse,
      );
    });
  });
}
