// T041：同步投影的纳入/排除边界（架构 5.2、SET-070–075、架构 5.1 的 Settings/SyncState）。
//
// 这一组用例全部是**纯函数断言**，不连库、不连网：数据出境边界必须能在不搭环境的情况下
// 逐条核对，否则「某天某个 Key 进了快照」只会在用户那边被发现。
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

void main() {
  group('共通设置（SET C 类）纳入、S/D 类排除', () {
    test('C 类且可持久化的编号全部纳入', () {
      expect(
        SyncProjection.settingCodes,
        containsAll(<String>[
          'SET-001', // 界面语言（C）
          'SET-002', // 主题（C）
          'SET-020', // 全局自动刷新（C）
          'SET-050', // RSS 内容总开关（C）
          'SET-059', // 每任务总时限（C）
        ]),
      );
    });

    test('投影清单与注册表的 C 类完全一致（不手抄、不遗漏）', () {
      final List<String> fromRegistry =
          SettingRegistry.withClassification(SettingClassification.common)
              .where((SettingDefinition d) => d.isPersistent)
              .map((SettingDefinition d) => d.id.code)
              .toList();
      expect(SyncProjection.settingCodes, fromRegistry);
    });

    test('秘密项（S 类）一个都不纳入，且都在排除清单里', () {
      for (final SettingDefinition definition in SettingRegistry.secrets) {
        expect(
          SyncProjection.includesSetting(definition.id.code),
          isFalse,
          reason: 'SET 类秘密不得纳入同步：${definition.id.code}',
        );
        expect(
          SyncProjection.excludedSettingCodes,
          contains(definition.id.code),
        );
      }
      // 具体点名三处，避免上面的循环在某天「秘密清单空了」时静默通过。
      for (final String code in <String>[
        'SET-027', // 私密源凭据/URL 秘密参数（S）
        'SET-031', // AI API Key（S）
        'SET-039', // 搜索 API Key（S）
        'SET-071', // WebDAV 密码/Token（S）
      ]) {
        expect(SyncProjection.includesSetting(code), isFalse, reason: code);
        expect(SyncProjection.excludedSettingCodes, contains(code));
      }
    });

    test('设备专属（D 类）一个都不纳入：字体/背景/窗口/同步调度开关', () {
      for (final String code in <String>[
        'SET-003', // 背景图（D：设备路径）
        'SET-005', // 字体（D）
        'SET-006', // 字号（D）
        'SET-008', // 列表视图/桌面栏宽（D：窗口布局）
        'SET-072', // 同步启用/启动同步（D：执行调度开关）
        'SET-073', // 自动同步间隔（D）
        'SET-074', // 同步范围（D：本机选择）
        'SET-056', // 本设备自动定时总结（D）
      ]) {
        expect(SyncProjection.includesSetting(code), isFalse, reason: code);
        expect(SyncProjection.excludedSettingCodes, contains(code));
      }
    });

    test('未注册编号不纳入（拼错的键不会变成一条会离开本机的配置）', () {
      expect(SyncProjection.includesSetting('SET-999'), isFalse);
      expect(
        SyncProjection.includesSetting('device.onboardingCompleted'),
        isFalse,
      );
    });
  });

  group('订阅/分组/文章状态字段投影', () {
    test('订阅：地址、名称、分组、加精、启用、新闻开关、排序纳入', () {
      for (final String field in <String>[
        'syncId',
        'normalizedUrl',
        'name',
        'groupSyncId',
        'favorite',
        'newsEnabled',
        'sortOrder',
      ]) {
        expect(SyncProjection.syncsFeedField(field), isTrue, reason: field);
      }
    });

    test('订阅：本机 id、凭据引用、条件请求缓存与抓取诊断排除', () {
      for (final String field in <String>[
        'id',
        'credentialRef',
        'httpEtag',
        'httpLastModified',
        'lastCheckedAt',
        'lastRefreshResult',
        'lastRefreshErrorKind',
      ]) {
        expect(SyncProjection.syncsFeedField(field), isFalse, reason: field);
        expect(SyncProjection.excludedFeedFields, contains(field));
      }
    });

    test('分组：名称/排序/置顶纳入，本机 id 排除', () {
      for (final String field in <String>[
        'syncId',
        'name',
        'sortOrder',
        'pinned',
      ]) {
        expect(SyncProjection.syncsGroupField(field), isTrue, reason: field);
      }
      expect(SyncProjection.syncsGroupField('id'), isFalse);
    });

    test('文章：只有状态与收藏纳入，正文/摘要/图片/统计全部排除', () {
      for (final String field in <String>[
        'syncKey',
        'readingState',
        'favorite',
        'deleted',
        'revision',
      ]) {
        expect(
          SyncProjection.syncsArticleStateField(field),
          isTrue,
          reason: field,
        );
      }
      for (final String field in <String>[
        'body',
        'summary',
        'aiSummary',
        'imageUrl',
        'extractedBody',
        'readingSeconds',
      ]) {
        expect(
          SyncProjection.syncsArticleStateField(field),
          isFalse,
          reason: '$field 首发不自动同步（架构 5.2）',
        );
        expect(SyncProjection.excludedArticleFields, contains(field));
      }
    });

    test('投影里没有任何一层出现「凭据」类字段名', () {
      final List<String> allFields = <String>[
        ...SyncProjection.feedFields,
        ...SyncProjection.groupFields,
        ...SyncProjection.articleStateFields,
        ...SyncProjection.newsRuleKinds,
      ];
      for (final String field in allFields) {
        final String lower = field.toLowerCase();
        expect(lower, isNot(contains('password')));
        expect(lower, isNot(contains('secret')));
        expect(lower, isNot(contains('apikey')));
        expect(lower, isNot(contains('token')));
        expect(lower, isNot(contains('credentialvalue')));
      }
    });
  });

  group('新闻来源规则（T036 产物）纳入', () {
    test('必访站、三个有序列表、prompt 版本都在投影里', () {
      expect(SyncProjection.newsRuleKinds, contains('requiredSites'));
      expect(
        SyncProjection.newsRuleKinds,
        containsAll(<String>[
          NewsListCategory.keywords,
          NewsListCategory.blockedQueryTerms,
          NewsListCategory.excludedTopics,
        ]),
      );
      expect(SyncProjection.newsRuleKinds, contains('promptVersions'));
    });

    test('三个列表类别与 T036 的常量一致（不写第二份字面量）', () {
      for (final String kind in NewsListCategory.all) {
        expect(
          SyncProjection.includesNewsRuleKind(kind),
          isTrue,
          reason: '$kind 是 T036 的产物，必须纳入同步',
        );
      }
      expect(SyncProjection.includesNewsRuleKind('unknownList'), isFalse);
    });

    test('中英两套 prompt 都要同步', () {
      expect(SyncProjection.newsPromptLanguages, <String>['zh-Hans', 'en']);
    });
  });

  group('实体类别清单', () {
    test('类别标识稳定且不重复（快照分区依赖它）', () {
      expect(SyncEntityKind.all.toSet().length, SyncEntityKind.all.length);
      expect(
        SyncEntityKind.all,
        containsAll(<String>[
          SyncEntityKind.setting,
          SyncEntityKind.feed,
          SyncEntityKind.group,
          SyncEntityKind.articleState,
        ]),
      );
    });
  });
}
