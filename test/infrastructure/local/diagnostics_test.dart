// T010：脱敏诊断日志。
//
// 三组证据（对应手册 6.3 的「日志/导出无秘密」）：
//   1. **脱敏**：含假 API key 的输入，输出与导出都不含完整 key；
//   2. **级别过滤**：低于当前级别的记录被丢弃且计数可见；
//   3. **裁剪**：按字节上限删最旧、按保留天数删超期，超限条数可见。
//
// 全部使用假值（`sk-test-` 前缀 + 随机后缀），不涉及任何真实凭据。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';

/// 一个足够长、形态像真 key 但明确是假的测试值。
const String _fakeApiKey = 'sk-test00FAKEkey1234567890abcdef';

/// 另一个形态的假凭据（GitHub 风格）。
const String _fakeGithubToken = 'ghp_testFAKEtoken1234567890abcdefgh';

void main() {
  group('兜底脱敏（第 2 层）', () {
    test('含假 API key 的消息被遮住，不留完整 key', () {
      final String sanitized = DiagnosticRedaction.sanitize(
        'request failed with key $_fakeApiKey',
      );
      expect(sanitized, isNot(contains(_fakeApiKey)));
      expect(sanitized, contains(DiagnosticRedaction.masked));
    });

    test('Bearer token 被遮住（大小写不敏感）', () {
      final String sanitized = DiagnosticRedaction.sanitize(
        'Authorization: Bearer abcdefghijklmnop123456',
      );
      expect(sanitized, isNot(contains('abcdefghijklmnop123456')));

      final String upper = DiagnosticRedaction.sanitize(
        'authorization: BEARER zzzzlongtokenvalue1234567890',
      );
      expect(upper, isNot(contains('zzzzlongtokenvalue1234567890')));
    });

    test('URL query 里的 token/key/password 参数被遮住', () {
      for (final String param in <String>[
        'token=abc123secretvalue',
        'key=abc123secretvalue',
        'password=abc123secretvalue',
        'api_key=abc123secretvalue',
      ]) {
        final String sanitized = DiagnosticRedaction.sanitize(
          'GET https://api.example.com/v1?$param&page=2',
        );
        expect(
          sanitized,
          isNot(contains('abc123secretvalue')),
          reason: '$param 未被遮住',
        );
        // 非秘密参数保留，便于排查。
        expect(sanitized, contains('page=2'));
      }
    });

    test('复用 core 策略：URL userinfo 与普通敏感参数名也被处理', () {
      final String sanitized = DiagnosticRedaction.sanitize(
        'fetch https://user:pass@example.com/feed.xml?auth=topsecret',
      );
      expect(sanitized, isNot(contains('pass@')));
      expect(sanitized, isNot(contains('topsecret')));
    });
  });

  group('日志记录与脱敏', () {
    test('记录含假 key 的错误 → 内存条目与导出都不含完整 key', () {
      final DiagnosticLog log = DiagnosticLog(clock: FakeClock());
      log.error('failed: $_fakeApiKey', tag: 'provider');

      expect(log.entries, hasLength(1));
      expect(log.entries.single.message, isNot(contains(_fakeApiKey)));

      final String exported = log.export();
      expect(exported, isNot(contains(_fakeApiKey)));
      expect(exported, contains('***'));
    });

    test('多种假凭据混在一行里都被遮住', () {
      final DiagnosticLog log = DiagnosticLog(clock: FakeClock());
      log.error(
        'key=$_fakeApiKey token=$_fakeGithubToken '
        'url=https://x.example.com/?password=hunter2secret',
      );
      final String exported = log.export();
      expect(exported, isNot(contains(_fakeApiKey)));
      expect(exported, isNot(contains(_fakeGithubToken)));
      expect(exported, isNot(contains('hunter2secret')));
    });

    test('导出内容经过二次脱敏：即使条目被外部拼接也仍安全', () {
      final DiagnosticLog log = DiagnosticLog(clock: FakeClock());
      // 直接构造一个「疑似已写入但含原文」的场景：record 已脱敏，因此这里改用
      // 一个内部已脱敏的值再验证 export 的幂等性。
      log.error('token $_fakeApiKey');
      final String first = log.export();
      final String second = log.export();
      expect(first, second, reason: '导出应当幂等（二次脱敏不改变结果）');
      expect(second, isNot(contains(_fakeApiKey)));
    });

    test('标签也脱敏（标签可能拼进端点或标识）', () {
      final DiagnosticLog log = DiagnosticLog(clock: FakeClock());
      log.error('boom', tag: 'provider:$_fakeApiKey');
      expect(log.entries.single.tag, isNot(contains(_fakeApiKey)));
      expect(log.export(), isNot(contains(_fakeApiKey)));
    });

    test('日志行内不出现换行（防止一条日志伪造多行）', () {
      final DiagnosticLog log = DiagnosticLog(clock: FakeClock());
      log.error('first line\nsecond line\r\nthird');
      expect(log.entries.single.toLine(), isNot(contains('\n')));
      expect(log.export().trim().split('\n'), hasLength(1));
    });
  });

  group('级别过滤', () {
    test('默认级别为 error：warning/info 被丢弃且计数可见', () {
      final DiagnosticLog log = DiagnosticLog(clock: FakeClock());
      expect(log.level, DiagnosticLevel.error);

      expect(log.error('e'), isTrue);
      expect(log.warning('w'), isFalse);
      expect(log.info('i'), isFalse);
      expect(log.entries, hasLength(1));
      expect(log.suppressedByLevel, 2);
    });

    test('提到 warning 后 warning 记录、info 仍被丢弃', () {
      final DiagnosticLog log = DiagnosticLog(
        level: DiagnosticLevel.warning,
        clock: FakeClock(),
      );
      expect(log.warning('w'), isTrue);
      expect(log.info('i'), isFalse);
      expect(log.entriesAt(DiagnosticLevel.warning), hasLength(1));
      expect(log.suppressedByLevel, 1);
    });

    test('提到 info 后三级都记录，级别可分别筛出', () {
      final DiagnosticLog log = DiagnosticLog(
        level: DiagnosticLevel.info,
        clock: FakeClock(),
      );
      log.error('e');
      log.warning('w');
      log.info('i');
      expect(log.entries, hasLength(3));
      expect(log.suppressedByLevel, 0);
      expect(log.entriesAt(DiagnosticLevel.error), hasLength(1));
      expect(log.entriesAt(DiagnosticLevel.info), hasLength(1));
    });

    test('allows 与级别枚举顺序一致（error 最严格）', () {
      final DiagnosticLog log = DiagnosticLog(level: DiagnosticLevel.error);
      expect(log.allows(DiagnosticLevel.error), isTrue);
      expect(log.allows(DiagnosticLevel.warning), isFalse);
      expect(log.allows(DiagnosticLevel.info), isFalse);
    });
  });

  group('保留策略与裁剪', () {
    test('超过条数上限时删最旧，保留最新', () {
      final DiagnosticLog log = DiagnosticLog(
        maxEntries: 3,
        clock: FakeClock(),
      );
      for (int i = 0; i < 5; i++) {
        log.error('entry-$i');
      }
      expect(log.entries, hasLength(3));
      expect(log.entries.first.message, 'entry-2');
      expect(log.entries.last.message, 'entry-4');
      expect(log.trimmedCount, 2);
    });

    test('超过字节上限时删最旧（SET-082 的 10 MiB 同机制，测试用小阈值）', () {
      // 每条约 20 字节；上限 100 字节 → 只留最新几条。
      final DiagnosticLog log = DiagnosticLog(
        maxTotalBytes: 100,
        clock: FakeClock(),
      );
      for (int i = 0; i < 20; i++) {
        log.error('message-number-$i-padding');
      }
      expect(log.currentBytes, lessThanOrEqualTo(100));
      expect(log.trimmedCount, greaterThan(0));
      expect(log.entries.last.message, 'message-number-19-padding');
    });

    test('超过保留天数的记录在裁剪时被删除', () {
      final FakeClock clock = FakeClock(start: DateTime.utc(2026, 9, 1));
      final DiagnosticLog log = DiagnosticLog(retentionDays: 7, clock: clock);
      log.error('old-entry');
      // 前进 10 天，超出 7 天保留期。
      clock.advance(const Duration(days: 10));
      // 触发裁剪（record 内部会调用 _enforceLimits）。
      log.error('new-entry');

      expect(log.entries, hasLength(1));
      expect(log.entries.single.message, 'new-entry');
      expect(log.trimmedCount, greaterThan(0));
    });

    test('保留期内的记录不被删除', () {
      final FakeClock clock = FakeClock(start: DateTime.utc(2026, 9, 1));
      final DiagnosticLog log = DiagnosticLog(retentionDays: 7, clock: clock);
      log.error('first');
      clock.advance(const Duration(days: 6));
      log.error('second');
      expect(log.entries, hasLength(2));
    });

    test('clear 清空内存记录', () {
      final DiagnosticLog log = DiagnosticLog(clock: FakeClock());
      log.error('a');
      log.error('b');
      log.clear();
      expect(log.entries, isEmpty);
      expect(log.export(), isEmpty);
    });
  });

  group('文件 sink 的长期保留', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('flux_diag_');
      file = File('${dir.path}/diagnostics.log');
    });

    tearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    test('写入文件并读回，内容已脱敏', () {
      // sink 与 log 必须共用同一时钟：否则 sink 会按“真实现在”判断条目是否超期，
      // 而条目时间戳来自假时钟，看起来像一条来自很久以前、应该被裁掉的日志。
      final FakeClock clock = FakeClock();
      final FileDiagnosticSink sink = FileDiagnosticSink(
        file: file,
        clock: clock,
      );
      final DiagnosticLog log = DiagnosticLog(clock: clock, fileSink: sink);
      log.error('failed with $_fakeApiKey');

      final List<String> lines = sink.readLines();
      expect(lines, hasLength(1));
      expect(lines.single, isNot(contains(_fakeApiKey)));
      expect(file.readAsStringSync(), isNot(contains(_fakeApiKey)));
    });

    test('文件超过字节上限时从最旧开始淘汰', () {
      final FakeClock clock = FakeClock();
      final FileDiagnosticSink sink = FileDiagnosticSink(
        file: file,
        maxTotalBytes: 120,
        clock: clock,
      );
      final DiagnosticLog log = DiagnosticLog(clock: clock, fileSink: sink);
      for (int i = 0; i < 20; i++) {
        log.error('file-entry-$i-padding');
      }
      final List<String> lines = sink.readLines();
      expect(lines.length, lessThan(20));
      expect(lines.last, contains('file-entry-19-padding'));
      expect(file.lengthSync(), lessThanOrEqualTo(120));
    });

    test('文件按保留天数裁剪超期行', () {
      final FakeClock clock = FakeClock(start: DateTime.utc(2026, 9, 1));
      final FileDiagnosticSink sink = FileDiagnosticSink(
        file: file,
        retentionDays: 7,
        clock: clock,
      );
      final DiagnosticLog log = DiagnosticLog(clock: clock, fileSink: sink);
      log.error('old');
      clock.advance(const Duration(days: 10));
      log.error('new');

      final List<String> lines = sink.readLines();
      expect(lines, hasLength(1));
      expect(lines.single, contains('new'));
      expect(lines.single, isNot(contains('old')));
    });
  });
}
