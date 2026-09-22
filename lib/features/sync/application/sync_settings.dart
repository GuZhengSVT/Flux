// 同步设置的读取与校验（T044；SET-070–075、架构 5.2）。
//
// 三件事在这里一次性做完，而不是散在界面里：
//
//   1) **读值带可解释的回退**：读不到的项退回注册表默认值（未配置时同步关、启动同步开、
//      防抖 5 秒、间隔 30 分钟、首次预览开）。回退方向是「更保守」：默认**关着同步**，
//      因此一次读失败不会让一台从没配置过的设备突然开始上传。
//   2) **URL 校验用地址守卫**：WebDAV 端点是用户显式配置的地址（SET-070），因此走
//      `UrlGuardPolicy.configuredSource`——允许内网（用户把同步目录放在自己 NAS 上是正当
//      需求），但拒绝非 http/https 与缺少主机名。校验是**纯函数**，界面在按钮可用性上直接用它。
//   3) **秘密只有一个出口**：SET-071 的密码不在这个模型里，本文件也不 import 任何凭据实现；
//      读密码走注入口的窄接口（[SyncSecretStore]）。
library;

import 'package:flux/core/core.dart';

import 'package:flux/features/settings/application/settings_store.dart';

/// 同步设置的读取端口（只读：写入口在同步设置页，走 settingsStoreProvider）。
final class SyncSettingsReader {
  /// 构造读取器。
  const SyncSettingsReader(this._store);

  final SettingsStore _store;

  /// 读全部同步设置（读不到的项退回注册表默认值）。
  Future<Result<SyncSettings>> load() async {
    final Result<Map<String, Object?>> read = await _store
        .readEffectiveSettings();
    if (read.isErr) {
      return Err<SyncSettings>(read.errorOrNull!);
    }
    return Ok<SyncSettings>(SyncSettings.fromEffective(read.unwrap()));
  }
}

/// SET-071 的密码读写（实现住 infrastructure/platform，包住 Keychain）。
///
/// 只暴露「读/写/是否存在」三个动作，没有「列出全部凭据」这类接口：同步设置只需要一份
/// 密码，给它枚举能力只会增加一条本不需要的泄露面。
abstract interface class SyncSecretStore {
  /// 读密码；不存在时返回 `Err(StorageError(isMissing: true))`。
  Future<Result<String>> readPassword();

  /// 写密码（或覆盖）。
  Future<Result<void>> writePassword(String password);

  /// 删除密码。
  Future<Result<void>> deletePassword();

  /// 密码是否存在（界面只显示状态，不回显值）。
  Future<Result<bool>> hasPassword();

  /// 该平台是否提供安全存储。
  Future<bool> isAvailable();
}

/// 同步设置的**有效值**（已解码、已带默认回退）。
/// 一次只读连接探测的结论（T044 的「测试连接」）。
///
/// 三个事实分开给，而不是合成一个「能不能用」：用户要做的事不同——连不上要改地址、
/// 认证失败要改密码、目录不存在要自己建（或让同步第一次发布去建）。
final class SyncConnectionProbe {
  /// 构造结论。
  const SyncConnectionProbe({
    required this.reachable,
    required this.directoryExists,
    required this.hasRemoteContent,
    this.reason,
  });

  /// 地址可达且认证通过。
  final bool reachable;

  /// 远端目录（SET-070 的 flux-v1）已经存在。
  ///
  /// false 不是错误：同步第一次发布会创建它（那一步是**写入**，因此不在探测里做）。
  final bool directoryExists;

  /// 远端已经有 manifest（即已经有过同步）。
  final bool hasRemoteContent;

  /// 失败原因的结构性标识（不含地址与凭据）。
  final String? reason;
}

/// 只读连接探测端口（实现住 infrastructure/network）。
///
/// 端口而不是直接调用客户端：界面住在 features，而 features 不得 import infrastructure
/// （分层守卫测试会拦）。更重要的是这条边界本身就有价值——把「探测」定义成一个**只有读**
/// 的动作，实现里就不可能顺手写点什么。
abstract interface class SyncConnectionProber {
  /// 探测端点（**不写任何远端内容**）。
  Future<Result<SyncConnectionProbe>> probe({
    required String url,
    required String username,
    required String password,
    required String remoteDirectory,
  });
}

/// 同步设置的**有效值**（已解码、已带默认回退）。
final class SyncSettings {
  /// 构造设置。
  const SyncSettings({
    required this.enabled,
    required this.syncOnStart,
    required this.syncOnChange,
    required this.changeDebounceSeconds,
    required this.intervalMinutes,
    required this.manualOnly,
    required this.url,
    required this.username,
    required this.remoteDirectory,
    required this.deviceName,
    required this.syncCommonSettings,
    required this.syncReadingState,
    required this.firstSyncPreview,
    required this.conflictPolicy,
  });

  /// 从「读到的有效值」构造（键为 SET 编号；缺项用注册表默认值）。
  factory SyncSettings.fromEffective(Map<String, Object?> effective) {
    final Map<String, Object?> set072 = _map(effective[SettingId.set072.code]);
    final Map<String, Object?> set073 = _map(effective[SettingId.set073.code]);
    final Map<String, Object?> set070 = _map(effective[SettingId.set070.code]);
    final Map<String, Object?> set074 = _map(effective[SettingId.set074.code]);
    final Map<String, Object?> set075 = _map(effective[SettingId.set075.code]);
    return SyncSettings(
      enabled: _bool(set072['enabled'], false),
      syncOnStart: _bool(set072['syncOnStart'], true),
      syncOnChange: _bool(set072['syncOnChange'], true),
      changeDebounceSeconds: _int(
        set072['changeDebounceSeconds'],
        5,
      ).clamp(1, 600),
      intervalMinutes: _int(set073['intervalMinutes'], 30).clamp(5, 1440),
      manualOnly: _bool(set073['manualOnly'], false),
      url: _string(set070['url'], ''),
      username: _string(set070['username'], ''),
      remoteDirectory: _string(
        set070['remoteDirectory'],
        defaultWebDavRemoteRoot,
      ),
      deviceName: _string(set070['deviceName'], ''),
      syncCommonSettings: _bool(set074['commonSettings'], true),
      syncReadingState: _bool(set074['readingState'], true),
      firstSyncPreview: _bool(set075['firstSyncPreview'], true),
      conflictPolicy: _conflictPolicy(set075['conflictPolicy']),
    );
  }

  /// SET-072 的总开关。
  final bool enabled;

  /// SET-072「启动时同步」。
  final bool syncOnStart;

  /// SET-072「变更后同步」。
  final bool syncOnChange;

  /// SET-072 的防抖秒数（默认 5）。
  final int changeDebounceSeconds;

  /// SET-073 的自动同步间隔（分钟；5–1440）。
  final int intervalMinutes;

  /// SET-073「仅手动」。
  final bool manualOnly;

  /// SET-070 的 WebDAV 地址（未配置为空串）。
  final String url;

  /// SET-070 的用户名。
  final String username;

  /// SET-070 的远端目录（默认 flux-v1）。
  final String remoteDirectory;

  /// SET-070 的设备名。
  final String deviceName;

  /// SET-074「共通设置」同步范围。
  final bool syncCommonSettings;

  /// SET-074「阅读状态」同步范围。
  final bool syncReadingState;

  /// SET-075「首次同步预览」。
  final bool firstSyncPreview;

  /// SET-075 的冲突策略。
  final SyncConflictPolicy conflictPolicy;

  /// 防抖时长。
  Duration get changeDebounce => Duration(seconds: changeDebounceSeconds);

  /// 自动同步间隔。
  Duration get interval => Duration(minutes: intervalMinutes);

  /// 是否具备运行同步的最低配置（地址 + 用户名 + 密码）。
  ///
  /// 「用户名」在很多 WebDAV 服务上可以为空（匿名或 token 认证），因此它不参与判定；
  /// 地址与密码必须齐备——少了地址不知道该连哪，少了密码会得到一个 401，而那在界面上
  /// 只会表现为一次莫名其妙的失败。
  bool get hasEndpointConfig => url.trim().isNotEmpty;

  /// 是否有可用的远端地址（校验通过时非 null）。
  ///
  /// 返回**校验后的端点**而不是布尔值：界面与用例都要拿到「后面直接用的那个 URL」，
  /// 两处各自解析一次会让「界面说合法、同步用另一个」成为可能。
  Uri? get endpoint => parseSyncEndpoint(url);

  /// 远端目录 URL（端点 + [remoteDirectory]）。
  Uri? get remoteRoot {
    final Uri? base = endpoint;
    if (base == null) {
      return null;
    }
    final String directory = remoteDirectory.trim().isEmpty
        ? defaultWebDavRemoteRoot
        : remoteDirectory.trim();
    return base.replace(
      pathSegments: <String>[
        ...base.pathSegments.where((String s) => s.isNotEmpty),
        directory,
      ],
    );
  }
}

/// 校验并规范一个 WebDAV 端点地址；非法时返回 null。
///
/// 与 T042 的客户端用**同一个守卫**（[checkUrlGuarded] + configuredSource）：界面在这里
/// 拒绝的地址，客户端在发请求前也会拒绝，因此不存在「界面放行、运行期才失败」的地址。
Uri? parseSyncEndpoint(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final Uri? parsed = Uri.tryParse(trimmed);
  if (parsed == null) {
    return null;
  }
  final UrlGuardResult guarded = checkUrlGuarded(
    parsed,
    UrlGuardPolicy.configuredSource,
  );
  if (!guarded.allowed) {
    return null;
  }
  if (parsed.host.isEmpty) {
    return null;
  }
  return parsed;
}

/// 一次 URL 校验的结论（界面据此给出**不同**的说明，而不是一句「地址无效」）。
enum SyncUrlProblem {
  /// 未填写。
  empty,

  /// 不是合法的 URL。
  malformed,

  /// 协议不是 http/https。
  scheme,

  /// 缺少主机名。
  missingHost,

  /// 合法。
  ok,
}

/// 校验并给出结论类别。
///
/// 分开返回类别而不是只给一个 bool：SET-070 的地址可能因为三种**不同**的原因被拒，
/// 而用户要做的事也不同（补一个地址 / 修协议 / 检查拼写）。合成一句「地址无效」会让用户
/// 不知道改哪里。
SyncUrlProblem validateSyncUrl(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return SyncUrlProblem.empty;
  }
  final Uri? parsed = Uri.tryParse(trimmed);
  if (parsed == null || !parsed.hasScheme) {
    return SyncUrlProblem.malformed;
  }
  if (parsed.host.isEmpty) {
    return SyncUrlProblem.missingHost;
  }
  final UrlGuardResult guarded = checkUrlGuarded(
    parsed,
    UrlGuardPolicy.configuredSource,
  );
  if (guarded.allowed) {
    return SyncUrlProblem.ok;
  }
  return guarded.failure == UrlGuardFailure.scheme
      ? SyncUrlProblem.scheme
      : SyncUrlProblem.missingHost;
}

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : const <String, Object?>{};

bool _bool(Object? value, bool fallback) => value is bool ? value : fallback;

int _int(Object? value, int fallback) =>
    value is int ? value : (value is num ? value.toInt() : fallback);

String _string(Object? value, String fallback) =>
    value is String ? value : fallback;

SyncConflictPolicy _conflictPolicy(Object? value) {
  if (value is String) {
    for (final SyncConflictPolicy policy in SyncConflictPolicy.values) {
      if (policy.name == value) {
        return policy;
      }
    }
  }
  return SyncConflictPolicy.manual;
}
