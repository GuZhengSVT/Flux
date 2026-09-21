// T010：设置注册表与文档口径一致性。
//
// 这份测试的价值在于「把架构第 6 节钉在代码上」：它独立于实现再写一遍编号、
// 分类与关键默认值/范围，因此任何一侧漂移都会失败——包括有人为了好写而「补齐」
// 不存在的编号，或把某个 D 类项误标成 C 类（那会把设备专属设置带进同步）。
//
// 为什么断言里再抄一遍数字而不是直接引用注册表：直接从注册表取期望值等于让
// 实现给自己打分。文档是权威，这里手工转录。
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

/// 架构第 6 节的权威编号清单（手工转录，按文档顺序）。
const List<String> _documentedCodes = <String>[
  // 6.1 通用、外观与阅读（16 项）
  'SET-001', 'SET-002', 'SET-003', 'SET-004', 'SET-005', 'SET-006',
  'SET-007', 'SET-008', 'SET-009', 'SET-010', 'SET-011', 'SET-012',
  'SET-013', 'SET-014', 'SET-015', 'SET-016',
  // 6.2 订阅与刷新（9 项）
  'SET-020', 'SET-021', 'SET-022', 'SET-023', 'SET-024', 'SET-025',
  'SET-026', 'SET-027', 'SET-028',
  // 6.3 AI 与搜索服务（13 项）
  'SET-030', 'SET-031', 'SET-032', 'SET-033', 'SET-034', 'SET-035',
  'SET-036', 'SET-037', 'SET-038', 'SET-039', 'SET-040', 'SET-041',
  'SET-042',
  // 6.4 新闻生成、prompt 与资源预算（17 项）
  'SET-050', 'SET-051', 'SET-052', 'SET-053', 'SET-054', 'SET-055',
  'SET-056', 'SET-057', 'SET-058', 'SET-059', 'SET-060', 'SET-061',
  'SET-062', 'SET-063', 'SET-064', 'SET-065', 'SET-066',
  // 6.5 同步、备份、存储与关于（15 项）
  'SET-070', 'SET-071', 'SET-072', 'SET-073', 'SET-074', 'SET-075',
  'SET-076', 'SET-077', 'SET-078', 'SET-079', 'SET-080', 'SET-081',
  'SET-082', 'SET-083', 'SET-084',
];

/// 架构第 6 节第 4 列的 C/D/S 分类（手工转录，仅列非 D 项以突出差异）。
const Map<String, SettingClassification> _documentedClassification =
    <String, SettingClassification>{
      // C 类：共通、可 WebDAV 同步。
      'SET-001': SettingClassification.common,
      'SET-002': SettingClassification.common,
      'SET-010': SettingClassification.common,
      'SET-011': SettingClassification.common,
      'SET-020': SettingClassification.common,
      'SET-022': SettingClassification.common,
      'SET-023': SettingClassification.common,
      'SET-024': SettingClassification.common,
      'SET-030': SettingClassification.common,
      'SET-032': SettingClassification.common,
      'SET-033': SettingClassification.common,
      'SET-034': SettingClassification.common,
      'SET-035': SettingClassification.common,
      'SET-037': SettingClassification.common,
      'SET-038': SettingClassification.common,
      'SET-040': SettingClassification.common,
      'SET-050': SettingClassification.common,
      'SET-051': SettingClassification.common,
      'SET-052': SettingClassification.common,
      'SET-053': SettingClassification.common,
      'SET-054': SettingClassification.common,
      'SET-055': SettingClassification.common,
      'SET-057': SettingClassification.common,
      'SET-059': SettingClassification.common,
      'SET-060': SettingClassification.common,
      'SET-061': SettingClassification.common,
      'SET-062': SettingClassification.common,
      'SET-063': SettingClassification.common,
      'SET-064': SettingClassification.common,
      'SET-065': SettingClassification.common,
      'SET-066': SettingClassification.common,
      // S 类：秘密，仅本机安全存储。
      'SET-027': SettingClassification.secret,
      'SET-031': SettingClassification.secret,
      'SET-039': SettingClassification.secret,
      'SET-071': SettingClassification.secret,
    };

/// 取一个设置项定义，取不到时让测试失败并给出清晰原因。
SettingDefinition _definition(String code) {
  final SettingDefinition? found = SettingRegistry.find(code);
  expect(found, isNotNull, reason: '$code 未注册');
  return found!;
}

/// 取复合分量的 spec，要求该分量存在。
SettingValueSpec _component(String code, String name) {
  final SettingValueSpec spec = _definition(code).spec;
  expect(spec, isA<CompositeSpec>(), reason: '$code 应当是复合设置');
  final SettingField? field = (spec as CompositeSpec).field(name);
  expect(field, isNotNull, reason: '$code 缺少分量 $name');
  return field!.spec;
}

void main() {
  group('编号清单与文档一致', () {
    test('注册表编号集合与架构第 6 节完全相同（不造号、不漏号）', () {
      final List<String> actual = SettingRegistry.all
          .map((SettingDefinition d) => d.id.code)
          .toList();
      expect(actual, _documentedCodes);
    });

    test('编号数量与分段计数符合文档', () {
      expect(SettingRegistry.all, hasLength(70));
      expect(_documentedCodes, hasLength(70));
    });

    test('编号唯一且升序', () {
      final List<String> codes = SettingRegistry.all
          .map((SettingDefinition d) => d.id.code)
          .toList();
      expect(codes.toSet(), hasLength(codes.length), reason: '不得有重复编号');
      final List<String> sorted = List<String>.of(codes)..sort();
      expect(codes, sorted, reason: '注册表按编号升序');
    });

    test('未注册编号的查询与校验都明确失败（不静默通过）', () {
      expect(SettingRegistry.find('SET-017'), isNull);
      expect(SettingRegistry.contains('SET-017'), isFalse);
      // 文档里确实不存在这些编号（001..016 之后直接跳到 020）。
      expect(SettingRegistry.contains('SET-017'), isFalse);
      expect(SettingRegistry.contains('SET-029'), isFalse);
      expect(SettingRegistry.contains('SET-043'), isFalse);
      expect(SettingRegistry.contains('SET-067'), isFalse);
      expect(SettingRegistry.contains('SET-085'), isFalse);

      final Result<void> result = SettingsValidator.validate(
        const SettingId('SET-017'),
        true,
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
    });
  });

  group('C/D/S 分类与文档一致', () {
    test('每个非 D 项的分类与文档表格逐一相符', () {
      for (final MapEntry<String, SettingClassification> entry
          in _documentedClassification.entries) {
        expect(
          _definition(entry.key).classification,
          entry.value,
          reason: '${entry.key} 分类与文档不符',
        );
      }
    });

    test('文档未在非 D 表里列出的编号必须都是设备项（D）', () {
      for (final SettingDefinition definition in SettingRegistry.all) {
        if (_documentedClassification.containsKey(definition.id.code)) {
          continue;
        }
        expect(
          definition.classification,
          SettingClassification.device,
          reason: '${definition.id.code} 未在文档非 D 项里出现，应为设备项',
        );
      }
    });

    test('分类计数符合文档（C 31 / D 35 / S 4）', () {
      int count(SettingClassification c) => SettingRegistry.all
          .where((SettingDefinition d) => d.classification == c)
          .length;
      expect(count(SettingClassification.common), 31);
      expect(count(SettingClassification.device), 35);
      expect(count(SettingClassification.secret), 4);
      expect(
        count(SettingClassification.common) +
            count(SettingClassification.device) +
            count(SettingClassification.secret),
        70,
      );
    });

    test('秘密项恰好是文档标记为 S 的四个编号', () {
      final Set<String> secrets = SettingRegistry.secrets
          .map((SettingDefinition d) => d.id.code)
          .toSet();
      expect(secrets, <String>{'SET-027', 'SET-031', 'SET-039', 'SET-071'});
    });

    test('C 类项全部可持久化（同步投影的前提）', () {
      for (final SettingDefinition definition
          in SettingRegistry.withClassification(SettingClassification.common)) {
        expect(
          definition.isPersistent,
          isTrue,
          reason: '${definition.id.code} 是 C 类但不是持久设置，无法同步',
        );
        expect(definition.isSecret, isFalse);
      }
    });
  });

  group('默认值与范围逐条核对文档', () {
    test('SET-004 背景不透明度 20% / 模糊 8 / 亮度 100%，范围 0–40 / 0–24 / 50–150', () {
      final IntSpec opacity =
          _component('SET-004', 'opacityPercent') as IntSpec;
      expect(opacity.defaultValue, 20);
      expect(opacity.min, 0);
      expect(opacity.max, 40);

      final IntSpec blur = _component('SET-004', 'blur') as IntSpec;
      expect(blur.defaultValue, 8);
      expect(blur.min, 0);
      expect(blur.max, 24);

      final IntSpec brightness =
          _component('SET-004', 'brightnessPercent') as IntSpec;
      expect(brightness.defaultValue, 100);
      expect(brightness.min, 50);
      expect(brightness.max, 150);
    });

    test('SET-006 字号：桌面 UI 14 / 手机 16 / 正文与新闻 18；UI 12–24、正文 14–28', () {
      final IntSpec uiDesktop = _component('SET-006', 'uiDesktop') as IntSpec;
      expect(uiDesktop.defaultValue, 14);
      expect(uiDesktop.min, 12);
      expect(uiDesktop.max, 24);

      final IntSpec uiMobile = _component('SET-006', 'uiMobile') as IntSpec;
      expect(uiMobile.defaultValue, 16);
      expect(uiMobile.min, 12);
      expect(uiMobile.max, 24);

      final IntSpec article = _component('SET-006', 'article') as IntSpec;
      expect(article.defaultValue, 18);
      expect(article.min, 14);
      expect(article.max, 28);

      final IntSpec news = _component('SET-006', 'news') as IntSpec;
      expect(news.defaultValue, 18);
      expect(news.min, 14);
      expect(news.max, 28);
    });

    test('SET-015 阅读统计：开 / 空闲 5 分钟，范围 1–30', () {
      final BoolSpec enabled = _component('SET-015', 'enabled') as BoolSpec;
      expect(enabled.defaultValue, isTrue);

      final IntSpec idle = _component('SET-015', 'idlePauseMinutes') as IntSpec;
      expect(idle.defaultValue, 5);
      expect(idle.min, 1);
      expect(idle.max, 30);
    });

    test('SET-028 抓取并发 4 / 超时 30 秒；范围 1–8 / 10–120', () {
      final IntSpec concurrency =
          _component('SET-028', 'concurrency') as IntSpec;
      expect(concurrency.defaultValue, 4);
      expect(concurrency.min, 1);
      expect(concurrency.max, 8);

      final IntSpec timeout =
          _component('SET-028', 'timeoutSeconds') as IntSpec;
      expect(timeout.defaultValue, 30);
      expect(timeout.min, 10);
      expect(timeout.max, 120);
    });

    test('SET-036 AI 并发 2 / 首响应 45 / 流停滞 30；范围 1–4 / 10–120 / 10–120', () {
      final IntSpec concurrency =
          _component('SET-036', 'concurrency') as IntSpec;
      expect(concurrency.defaultValue, 2);
      expect(concurrency.min, 1);
      expect(concurrency.max, 4);

      final IntSpec first =
          _component('SET-036', 'firstResponseSeconds') as IntSpec;
      expect(first.defaultValue, 45);
      expect(first.min, 10);
      expect(first.max, 120);

      final IntSpec stall =
          _component('SET-036', 'streamStallSeconds') as IntSpec;
      expect(stall.defaultValue, 30);
      expect(stall.min, 10);
      expect(stall.max, 120);
    });

    test('SET-040 搜索结果数 10 / 超时 20 秒；范围 1–20 / 5–60', () {
      final IntSpec maxResults = _component('SET-040', 'maxResults') as IntSpec;
      expect(maxResults.defaultValue, 10);
      expect(maxResults.min, 1);
      expect(maxResults.max, 20);

      final IntSpec timeout =
          _component('SET-040', 'timeoutSeconds') as IntSpec;
      expect(timeout.defaultValue, 20);
      expect(timeout.min, 5);
      expect(timeout.max, 60);
    });

    test('SET-057 每日执行时间默认 20:00，且拒绝非法时间', () {
      final StringSpec spec = _definition('SET-057').spec as StringSpec;
      expect(spec.defaultValue, '20:00');
      expect(
        SettingRegistry.find('SET-057')!.validateValue('20:00').isOk,
        isTrue,
      );
      expect(
        SettingRegistry.find('SET-057')!.validateValue('23:59').isOk,
        isTrue,
      );
      expect(
        SettingRegistry.find('SET-057')!.validateValue('24:00').isErr,
        isTrue,
      );
      expect(
        SettingRegistry.find('SET-057')!.validateValue('8:00').isErr,
        isTrue,
      );
      expect(
        SettingRegistry.find('SET-057')!.validateValue('20:0').isErr,
        isTrue,
      );
    });

    test('SET-059 每任务总时限默认 10 分钟，范围 1–60', () {
      final IntSpec spec = _definition('SET-059').spec as IntSpec;
      expect(spec.defaultValue, 10);
      expect(spec.min, 1);
      expect(spec.max, 60);
    });

    test('SET-060 默认 50/10/10，可提高到 200/30/30', () {
      final IntSpec articles = _component('SET-060', 'maxArticles') as IntSpec;
      expect(articles.defaultValue, 50);
      expect(articles.max, 200);

      final IntSpec sites = _component('SET-060', 'maxSites') as IntSpec;
      expect(sites.defaultValue, 10);
      expect(sites.max, 30);

      final IntSpec queries = _component('SET-060', 'maxQueries') as IntSpec;
      expect(queries.defaultValue, 10);
      expect(queries.max, 30);
    });

    test('SET-061 单材料文本预算默认 8000', () {
      expect((_definition('SET-061').spec as IntSpec).defaultValue, 8000);
    });

    test('SET-062 工具调用 30 / HTTP 尝试 30', () {
      expect((_component('SET-062', 'toolCalls') as IntSpec).defaultValue, 30);
      expect(
        (_component('SET-062', 'httpAttempts') as IntSpec).defaultValue,
        30,
      );
    });

    test('SET-063 Token 预算默认 100000', () {
      expect((_definition('SET-063').spec as IntSpec).defaultValue, 100000);
    });

    test('SET-064 当天自动摘要任务数默认 50', () {
      expect((_definition('SET-064').spec as IntSpec).defaultValue, 50);
    });

    test('SET-065 图像分析开 / 最多 6 张 / 单图 4 MiB', () {
      expect(
        (_component('SET-065', 'enabled') as BoolSpec).defaultValue,
        isTrue,
      );
      expect((_component('SET-065', 'maxImages') as IntSpec).defaultValue, 6);
      expect((_component('SET-065', 'maxImageMiB') as IntSpec).defaultValue, 4);
    });

    test('SET-073 自动同步默认 30 分钟，范围 5–1440', () {
      final IntSpec interval =
          _component('SET-073', 'intervalMinutes') as IntSpec;
      expect(interval.defaultValue, 30);
      expect(interval.min, 5);
      expect(interval.max, 1440);
    });

    test('SET-076 备份默认不含媒体', () {
      expect(
        (_component('SET-076', 'includeMedia') as BoolSpec).defaultValue,
        isFalse,
      );
    });

    test('SET-077 自动清理默认全关；启用后的预填 30/90/365，范围 1–3650', () {
      expect(
        (_component('SET-077', 'mediaEnabled') as BoolSpec).defaultValue,
        isFalse,
      );
      expect(
        (_component('SET-077', 'articleEnabled') as BoolSpec).defaultValue,
        isFalse,
      );
      expect(
        (_component('SET-077', 'summaryEnabled') as BoolSpec).defaultValue,
        isFalse,
      );

      final IntSpec mediaDays = _component('SET-077', 'mediaDays') as IntSpec;
      expect(mediaDays.defaultValue, 30);
      expect(mediaDays.min, 1);
      expect(mediaDays.max, 3650);

      final IntSpec articleDays =
          _component('SET-077', 'articleDays') as IntSpec;
      expect(articleDays.defaultValue, 90);
      expect(articleDays.min, 1);
      expect(articleDays.max, 3650);

      final IntSpec summaryDays =
          _component('SET-077', 'summaryDays') as IntSpec;
      expect(summaryDays.defaultValue, 365);
      expect(summaryDays.min, 1);
      expect(summaryDays.max, 3650);
    });

    test('SET-078 清理默认不含收藏与稍后再读', () {
      expect(
        (_component('SET-078', 'includeFavorite') as BoolSpec).defaultValue,
        isFalse,
      );
      expect(
        (_component('SET-078', 'includeLater') as BoolSpec).defaultValue,
        isFalse,
      );
    });

    test('SET-080 媒体缓存上限 512 MiB，范围 128–4096', () {
      final IntSpec spec = _definition('SET-080').spec as IntSpec;
      expect(spec.defaultValue, 512);
      expect(spec.min, 128);
      expect(spec.max, 4096);
    });

    test('SET-081 删除订阅默认每次询问、默认选保留', () {
      final EnumSpec policy = _component('SET-081', 'policy') as EnumSpec;
      expect(policy.defaultValue, 'ask');
      final EnumSpec choice =
          _component('SET-081', 'defaultChoice') as EnumSpec;
      expect(choice.defaultValue, 'keep');
    });

    test('SET-082 日志级别默认 error、保留 7 天、上限 10 MiB', () {
      final EnumSpec level = _component('SET-082', 'level') as EnumSpec;
      expect(level.defaultValue, 'error');
      expect(level.values, <String>['error', 'warning', 'info']);

      final IntSpec days = _component('SET-082', 'retentionDays') as IntSpec;
      expect(days.defaultValue, 7);

      final IntSpec total = _component('SET-082', 'maxTotalMiB') as IntSpec;
      expect(total.defaultValue, 10);
    });

    test('SET-083 更新通道 GitHub、不自动安装', () {
      final EnumSpec channel = _component('SET-083', 'channel') as EnumSpec;
      expect(channel.defaultValue, 'github');
      expect(
        (_component('SET-083', 'autoCheck') as BoolSpec).defaultValue,
        isFalse,
      );
    });

    test('SET-001 语言 / SET-002 主题默认跟随系统', () {
      final EnumSpec language = _definition('SET-001').spec as EnumSpec;
      expect(language.defaultValue, 'system');
      expect(language.values, <String>['system', 'zh-Hans', 'en']);

      final EnumSpec theme = _definition('SET-002').spec as EnumSpec;
      expect(theme.defaultValue, 'system');
      expect(theme.values, <String>['system', 'light', 'dark']);
    });

    test('SET-010 自动标已读默认开；SET-037 自动摘要默认关', () {
      expect((_definition('SET-010').spec as BoolSpec).defaultValue, isTrue);
      expect((_definition('SET-037').spec as BoolSpec).defaultValue, isFalse);
    });

    test('SET-020 全局刷新默认开 / 60 分钟，含手动与 15/30/60/120', () {
      expect(
        (_component('SET-020', 'enabled') as BoolSpec).defaultValue,
        isTrue,
      );
      final EnumSpec interval =
          _component('SET-020', 'intervalMinutes') as EnumSpec;
      expect(interval.defaultValue, '60');
      expect(interval.values, <String>['manual', '15', '30', '60', '120']);
    });

    test('SET-013 计费网络默认关；SET-012 自动加载远程图片默认开', () {
      expect((_definition('SET-013').spec as BoolSpec).defaultValue, isFalse);
      expect((_definition('SET-012').spec as BoolSpec).defaultValue, isTrue);
    });

    test('SET-056 定时总结默认开；SET-072 同步未配置时关', () {
      expect((_definition('SET-056').spec as BoolSpec).defaultValue, isTrue);
      expect(
        (_component('SET-072', 'enabled') as BoolSpec).defaultValue,
        isFalse,
      );
    });

    test('SET-041/051/052/053 默认空列表', () {
      expect(
        (_definition('SET-041').spec as StringListSpec).defaultValue,
        isEmpty,
      );
      expect(
        (_definition('SET-051').spec as StringListSpec).defaultValue,
        isEmpty,
      );
      expect(
        (_definition('SET-052').spec as StringListSpec).defaultValue,
        isEmpty,
      );
      expect(
        (_component(
          'SET-053',
          'blockedQueryTerms',
        ) as StringListSpec).defaultValue,
        isEmpty,
      );
      expect(
        (_component(
          'SET-053',
          'excludedTopics',
        ) as StringListSpec).defaultValue,
        isEmpty,
      );
    });

    test('SET-070 远端目录默认 flux-v1；凭据未配置', () {
      final StringSpec remote =
          _component('SET-070', 'remoteDirectory') as StringSpec;
      expect(remote.defaultValue, 'flux-v1');
      expect((_component('SET-070', 'url') as StringSpec).defaultValue, isNull);
    });

    test('SET-058 新闻时区为只读项；SET-084 版本元数据为只读项', () {
      expect(_definition('SET-058').isReadOnly, isTrue);
      expect(_definition('SET-084').isReadOnly, isTrue);
    });

    test('SET-042/079 是文档写明的「操作，不是持久设置」', () {
      expect(_definition('SET-042').isPersistent, isFalse);
      expect(_definition('SET-042').spec, isA<ActionSpec>());
      expect(_definition('SET-079').isPersistent, isFalse);
      expect(_definition('SET-079').spec, isA<ActionSpec>());
    });

    test('只有 SET-042/079 不是持久设置，其余 68 项都可持久化', () {
      final List<String> nonPersistent = SettingRegistry.all
          .where((SettingDefinition d) => !d.isPersistent)
          .map((SettingDefinition d) => d.id.code)
          .toList();
      expect(nonPersistent, <String>['SET-042', 'SET-079']);
      expect(SettingRegistry.persistent, hasLength(68));
    });

    test('每个编号都有非空标题（设置页分组与断言使用）', () {
      for (final SettingDefinition definition in SettingRegistry.all) {
        expect(
          definition.title.trim(),
          isNotEmpty,
          reason: '${definition.id.code} 缺少标题',
        );
      }
    });
  });

  group('取值域校验 API', () {
    test('整数范围：边界内通过，越界与类型错误被拒', () {
      const SettingId id = SettingId.set059; // 1–60
      expect(SettingsValidator.validate(id, 1).isOk, isTrue);
      expect(SettingsValidator.validate(id, 60).isOk, isTrue);
      expect(SettingsValidator.validate(id, 0).isErr, isTrue);
      expect(SettingsValidator.validate(id, 61).isErr, isTrue);
      expect(SettingsValidator.validate(id, '30').isErr, isTrue);
      expect(SettingsValidator.validate(id, 30.5).isErr, isTrue);
    });

    test('范围错误的文案包含具体上限，便于设置页直接显示', () {
      final Result<void> result = SettingsValidator.validate(
        const SettingId('SET-080'),
        4097,
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
      final ValidationError error = result.errorOrNull! as ValidationError;
      expect(error.field, 'SET-080');
      expect(error.reason, contains('4096'));
    });

    test('枚举只接受文档列出的取值', () {
      const SettingId id = SettingId.set082; // level 复合项
      final CompositeSpec spec = _definition('SET-082').spec as CompositeSpec;
      expect(
        spec.validate('SET-082', <String, Object?>{'level': 'warning'}).isOk,
        isTrue,
      );
      expect(
        spec.validate('SET-082', <String, Object?>{'level': 'verbose'}).isErr,
        isTrue,
      );
      // 未注册分量被拒绝：多半是拼错键名，静默保留会变成读不到的幽灵配置。
      expect(
        spec.validate('SET-082', <String, Object?>{'levle': 'error'}).isErr,
        isTrue,
      );
      expect(SettingsValidator.validate(id, 'error').isErr, isTrue);
    });

    test('字符串列表要求元素都是字符串', () {
      const SettingId id = SettingId.set051;
      expect(
        SettingsValidator.validate(id, <String>['https://a.example.com']).isOk,
        isTrue,
      );
      expect(SettingsValidator.validate(id, <Object>[1, 2]).isErr, isTrue);
      expect(SettingsValidator.validate(id, 'single').isErr, isTrue);
    });

    test('操作类设置不接受任何持久值', () {
      expect(SettingsValidator.validate(SettingId.set042, null).isOk, isTrue);
      expect(SettingsValidator.validate(SettingId.set042, true).isErr, isTrue);
    });

    test('秘密项不允许进入普通设置存储（存储层拒绝）', () {
      for (final String code in <String>[
        'SET-027',
        'SET-031',
        'SET-039',
        'SET-071',
      ]) {
        final Result<void> result = SettingsValidator.validateStorable(
          SettingId(code),
        );
        expect(result.isErr, isTrue, reason: '$code 必须被拒绝');
        final ValidationError error = result.errorOrNull! as ValidationError;
        expect(error.field, code);
      }
    });

    test('非秘密可持久项允许进入普通存储', () {
      expect(SettingsValidator.validateStorable(SettingId.set004).isOk, isTrue);
      expect(SettingsValidator.validateStorable(SettingId.set001).isOk, isTrue);
    });

    test('操作类设置也不允许进入普通存储', () {
      expect(
        SettingsValidator.validateStorable(SettingId.set079).isErr,
        isTrue,
      );
    });

    test('未注册编号的可存储性校验失败', () {
      expect(
        SettingsValidator.validateStorable(const SettingId('SET-017')).isErr,
        isTrue,
      );
    });
  });

  group('JSON 编解码', () {
    test('合法 JSON 解码后通过校验', () {
      final Result<Object?> decoded = SettingsValidator.decode(
        SettingId.set059,
        '10',
      );
      expect(decoded.isOk, isTrue);
      expect(decoded.valueOrNull, 10);
    });

    test('损坏的 JSON 报解析错误，与「值越界」可区分', () {
      final Result<Object?> decoded = SettingsValidator.decode(
        SettingId.set059,
        '{not json',
      );
      expect(decoded.isErr, isTrue);
      expect(decoded.errorOrNull, isA<ParseError>());
    });

    test('合法 JSON 但值越界时报校验错误（而不是解析错误）', () {
      final Result<Object?> decoded = SettingsValidator.decode(
        SettingId.set059,
        '999',
      );
      expect(decoded.isErr, isTrue);
      expect(decoded.errorOrNull, isA<ValidationError>());
    });

    test('编码与解码往返保持复合结构', () {
      const Map<String, Object?> value = <String, Object?>{
        'opacityPercent': 30,
        'blur': 10,
        'brightnessPercent': 120,
      };
      final String encoded = SettingValueCodec.encode(value);
      final Result<Object?> decoded = SettingsValidator.decode(
        SettingId.set004,
        encoded,
      );
      expect(decoded.isOk, isTrue);
      final Map<Object?, Object?> roundTripped =
          decoded.valueOrNull! as Map<Object?, Object?>;
      expect(roundTripped['opacityPercent'], 30);
      expect(roundTripped['blur'], 10);
      expect(roundTripped['brightnessPercent'], 120);
    });

    test('matchesDefault 正确判断是否偏离默认值', () {
      final SettingValueSpec spec = _definition('SET-004').spec;
      expect(matchesDefault(spec, spec.defaultValue), isTrue);
      expect(
        matchesDefault(spec, <String, Object?>{
          'opacityPercent': 21,
          'blur': 8,
          'brightnessPercent': 100,
        }),
        isFalse,
      );
    });
  });

  group('SettingId 值语义', () {
    test('相等性基于编号文本，可安全用作 Map 键', () {
      expect(const SettingId('SET-001'), SettingId.set001);
      expect(const SettingId('SET-001').hashCode, SettingId.set001.hashCode);
      final Map<SettingId, String> map = <SettingId, String>{
        SettingId.set001: 'a',
      };
      expect(map[const SettingId('SET-001')], 'a');
    });

    test('toString 就是文档编号，便于日志与断言阅读', () {
      expect(SettingId.set004.toString(), 'SET-004');
    });

    test('all 中的编号与逐个常量一致', () {
      expect(SettingId.all, hasLength(70));
      expect(SettingId.all.first, SettingId.set001);
      expect(SettingId.all.last, SettingId.set084);
    });
  });
}
