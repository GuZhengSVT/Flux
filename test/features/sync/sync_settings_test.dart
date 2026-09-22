// T044：同步设置的读取、默认回退与 URL 校验（SET-070–075、架构 5.2）。
//
// 三条边界：
//   1) **读不到的项退回注册表默认值**，且方向是保守的（未配置时同步**关着**）；
//   2) **URL 校验与客户端用同一个守卫**（内网允许、非 http/https 拒绝、缺主机名拒绝），
//      并且拒绝原因可区分——用户要改的东西不同；
//   3) **密码不进这个模型**：读设置的结果里没有任何秘密字段。
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/settings_store.dart';
import 'package:flux/features/sync/application/sync_settings.dart';

/// 一个只回答固定值的设置端口（测试替身）。
final class _FakeSettingsStore implements SettingsStore {
  _FakeSettingsStore(this.effective);

  final Map<String, Object?> effective;

  @override
  Future<Result<Object?>> readSetting(SettingId id) async =>
      Ok<Object?>(effective[id.code]);

  @override
  Future<Result<Object?>> writeSetting(SettingId id, Object? value) async =>
      const Ok<Object?>(null);

  @override
  Future<Result<Map<String, Object?>>> readEffectiveSettings() async =>
      Ok<Map<String, Object?>>(effective);
}

void main() {
  group('读设置：默认回退是保守的', () {
    test('什么都没有配置时：同步关着、启动同步开、防抖 5 秒、间隔 30 分钟、首次预览开', () async {
      final SyncSettingsReader reader = SyncSettingsReader(
        _FakeSettingsStore(const <String, Object?>{}),
      );
      final SyncSettings settings = (await reader.load()).unwrap();

      expect(settings.enabled, isFalse, reason: '未配置的设备不得自动开始上传');
      expect(settings.syncOnStart, isTrue);
      expect(settings.syncOnChange, isTrue);
      expect(settings.changeDebounceSeconds, 5);
      expect(settings.intervalMinutes, 30);
      expect(settings.manualOnly, isFalse);
      expect(settings.url, isEmpty);
      expect(settings.remoteDirectory, defaultWebDavRemoteRoot);
      expect(settings.syncCommonSettings, isTrue);
      expect(settings.syncReadingState, isTrue);
      expect(settings.firstSyncPreview, isTrue);
      expect(settings.conflictPolicy, SyncConflictPolicy.manual);
      expect(settings.hasEndpointConfig, isFalse);
      expect(settings.endpoint, isNull);
    });

    test('读到坏值时不猜：类型不符退回默认值，越界值被夹到合法区间', () async {
      final SyncSettingsReader reader = SyncSettingsReader(
        _FakeSettingsStore(<String, Object?>{
          SettingId.set072.code: <String, Object?>{
            'enabled': 'yes',
            'changeDebounceSeconds': 99999,
          },
          SettingId.set073.code: <String, Object?>{'intervalMinutes': 1},
        }),
      );
      final SyncSettings settings = (await reader.load()).unwrap();
      expect(settings.enabled, isFalse, reason: '非布尔按默认（关）处理');
      expect(settings.changeDebounceSeconds, 600, reason: '夹到上限');
      expect(settings.intervalMinutes, 5, reason: '夹到下限');
    });

    test('已配置时读到地址、用户名与远端目录', () async {
      final SyncSettingsReader reader = SyncSettingsReader(
        _FakeSettingsStore(<String, Object?>{
          SettingId.set070.code: <String, Object?>{
            'url': 'https://dav.example.com/remote.php/dav/files/alice',
            'username': 'alice',
            'remoteDirectory': 'flux-v1',
            'deviceName': 'MacBook',
          },
        }),
      );
      final SyncSettings settings = (await reader.load()).unwrap();
      expect(settings.username, 'alice');
      expect(settings.deviceName, 'MacBook');
      expect(settings.hasEndpointConfig, isTrue);
      expect(
        settings.remoteRoot.toString(),
        'https://dav.example.com/remote.php/dav/files/alice/flux-v1',
      );
    });

    test('远端目录为空时回退 flux-v1（不拼出一个没有目录的根地址）', () async {
      final SyncSettingsReader reader = SyncSettingsReader(
        _FakeSettingsStore(<String, Object?>{
          SettingId.set070.code: <String, Object?>{
            'url': 'https://dav.example.com',
            'remoteDirectory': '   ',
          },
        }),
      );
      final SyncSettings settings = (await reader.load()).unwrap();
      expect(settings.remoteRoot.toString(), 'https://dav.example.com/flux-v1');
    });

    test('读取设置的结果里没有任何秘密（SET-071 不经过这里）', () async {
      final SyncSettingsReader reader = SyncSettingsReader(
        _FakeSettingsStore(<String, Object?>{
          SettingId.set070.code: <String, Object?>{
            'url': 'https://dav.example.com',
          },
          SettingId.set071.code: 'should-never-be-read',
        }),
      );
      final SyncSettings settings = (await reader.load()).unwrap();
      expect(settings.toString().contains('should-never-be-read'), isFalse);
    });
  });

  group('URL 校验（与客户端同一个守卫）', () {
    test('合法地址：http/https 都接受', () {
      expect(
        validateSyncUrl('https://dav.example.com/flux-v1'),
        SyncUrlProblem.ok,
      );
      expect(validateSyncUrl('http://dav.example.com'), SyncUrlProblem.ok);
    });

    test('内网地址**允许**（用户把同步目录放在自己 NAS 上是正当需求）', () {
      expect(validateSyncUrl('http://192.168.1.10/dav'), SyncUrlProblem.ok);
      expect(validateSyncUrl('http://nas.local/dav'), SyncUrlProblem.ok);
    });

    test('未填写 / 非法 / 协议不符 / 缺主机名分别给出不同的结论', () {
      expect(validateSyncUrl(''), SyncUrlProblem.empty);
      expect(validateSyncUrl('   '), SyncUrlProblem.empty);
      expect(validateSyncUrl('not a url'), SyncUrlProblem.malformed);
      expect(validateSyncUrl('ftp://dav.example.com'), SyncUrlProblem.scheme);
      expect(validateSyncUrl('https://'), SyncUrlProblem.missingHost);
    });

    test('parseSyncEndpoint 与 validateSyncUrl 结论一致（界面拒绝的运行期也拒绝）', () {
      for (final String raw in <String>[
        'https://dav.example.com/x',
        'http://192.168.1.10/x',
        '',
        'ftp://x.example.com',
        'https://',
      ]) {
        final bool valid = validateSyncUrl(raw) == SyncUrlProblem.ok;
        expect(
          parseSyncEndpoint(raw) != null,
          valid,
          reason: '对 $raw 两个入口必须一致',
        );
      }
    });
  });
}
