// WebDAV 能力探测的编排（T044；架构 5.2「多写入服务须验证强 ETag/If-Match 等条件发布能力」）。
//
// 判定本身是 T042 的纯函数（evaluateConditionalWriteProbe）；本文件只负责**做那四个实验**：
// 在远端目录里放一个自己的探测文件，观测「ETag 是否存在 / 带 If-Match 的写是否成功 /
// 写后 ETag 是否变化 / 过期 ETag 是否被拒」，然后把四条事实交给纯函数判定。
//
// 三条纪律：
//   1) **只动自己的探测文件**，不碰用户任何快照或 manifest，也不列别人的目录——探测不该
//      污染或窥探用户的远端内容。探测结束即删掉它。
//   2) **任何一步失败都不猜**：网络中断/认证失败/写被拒都分别映射到一个结论，而不是「大概
//      能用吧」——判错方向的代价是「忽略 If-Match 的服务器被判成支持条件写」，那会在多端
//      并发时静默互相覆盖。
//   3) **判定只有一处实现**（T042 的纯函数），本文件不复制它的规则。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/sync/application/sync_settings.dart';

import 'webdav_client.dart';

/// 探测文件的文件名前缀（后缀带时间戳，避免与上一次探测的残留文件撞名）。
const String _probeFilePrefix = 'flux-capability-probe';

/// 对一个端点做四步能力探测，返回判定结论。
Future<Result<WebDavWriteCapability>> probeWebDavCapability({
  required WebDavClient client,
  required SyncSettings settings,
  required String password,
}) async {
  final Uri? endpoint = parseSyncEndpoint(settings.url);
  if (endpoint == null) {
    return Err<WebDavWriteCapability>(
      ValidationError(field: 'SET-070.url', reason: '地址非法或未填写'),
    );
  }
  final String directory = settings.remoteDirectory.trim().isEmpty
      ? defaultWebDavRemoteRoot
      : settings.remoteDirectory.trim();
  final Uri directoryUrl = endpoint.replace(
    pathSegments: <String>[
      ...endpoint.pathSegments.where((String segment) => segment.isNotEmpty),
      directory,
    ],
  );
  final String username = settings.username;
  final Uri probeUrl = directoryUrl.replace(
    pathSegments: <String>[
      ...directoryUrl.pathSegments,
      '$_probeFilePrefix-${DateTime.now().microsecondsSinceEpoch}',
    ],
  );

  // 目录必须先存在（MKCOL 幂等；已存在视为成功）。
  final WebDavResponse mkcol = await client.mkcol(
    directoryUrl,
    username: username,
    password: password,
  );
  if (!mkcol.isOk && mkcol.status != WebDavStatus.writeRejected) {
    // 目录建不出来（权限/只读/不支持 MKCOL）：**不猜**能力，报失败让用户先修配置。
    return Err<WebDavWriteCapability>(_writeError(mkcol, 'sync.probe.mkcol'));
  }

  // 第 1 步：不带 If-Match 的写。
  final WebDavResponse first = await client.put(
    probeUrl,
    username: username,
    password: password,
    bytes: const <int>[49],
  );
  final bool probePutOk = first.isOk;

  // 第 2 步：读回 ETag（不少服务器只在 GET 上给 ETag）。
  String? readEtag = first.etag;
  if (readEtag == null && probePutOk) {
    final WebDavResponse read = await client.get(
      probeUrl,
      username: username,
      password: password,
    );
    readEtag = read.isOk ? read.etag : null;
  }

  // 第 3 步：带**当前** ETag 的写（应当成功），再看 ETag 是否变化。
  WebDavResponse conditional = const WebDavResponse(
    status: WebDavStatus.failed,
    httpStatus: null,
  );
  if (readEtag != null) {
    conditional = await client.put(
      probeUrl,
      username: username,
      password: password,
      bytes: const <int>[50],
      ifMatch: readEtag,
    );
  }
  String? secondEtag = conditional.etag;
  if (conditional.isOk && secondEtag == null) {
    final WebDavResponse read = await client.get(
      probeUrl,
      username: username,
      password: password,
    );
    secondEtag = read.isOk ? read.etag : null;
  }

  // 第 4 步：**过期** ETag 必须被拒（识破「忽略 If-Match 的服务器」的唯一实验）。
  bool staleRejected = false;
  if (readEtag != null && conditional.isOk) {
    final WebDavResponse stale = await client.put(
      probeUrl,
      username: username,
      password: password,
      bytes: const <int>[51],
      // 用**已经用过**的那个 ETag（此刻远端 ETag 已经是新的了）。
      ifMatch: readEtag,
    );
    staleRejected = stale.status == WebDavStatus.conflict;
  }

  final WebDavProbeResult verdict = evaluateConditionalWriteProbe(
    WebDavProbeFacts(
      probePutOk: probePutOk,
      firstEtag: readEtag,
      conditionalPutOk: conditional.isOk,
      secondEtag: secondEtag,
      staleIfMatchRejected: staleRejected,
    ),
  );
  // 清掉探测文件（不在用户目录里留垃圾）。清理失败不影响结论：它只是收尾。
  await client.delete(probeUrl, username: username, password: password);
  return Ok<WebDavWriteCapability>(verdict.capability);
}

AppError _writeError(WebDavResponse response, String operation) {
  if (response.status == WebDavStatus.unauthorized) {
    return AuthError(
      provider: 'webdav',
      statusCode: response.httpStatus,
      detail: '认证失败：请检查用户名与密码（SET-070/071）',
    );
  }
  return NetworkError(
    uri: '',
    statusCode: response.httpStatus,
    reason: response.reason ?? operation,
  );
}
