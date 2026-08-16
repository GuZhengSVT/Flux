/// RSSHub 路由适配工具。
///
/// RSSHub 返回标准 RSS/Atom，Flux 本身已能解析；
/// 这里主要是帮助用户把 `路由路径` 拼成可订阅的完整 URL，
/// 并支持 `format` / `limit` / `fulltext` 等常用参数。
class RSSHubService {
  const RSSHubService();

  /// 把 RSSHub 路由路径或完整 URL 构造成订阅地址。
  ///
  /// - [route] 可以是 `zhihu/daily`、`/zhihu/daily` 或完整 RSSHub URL。
  /// - [format] 支持 `rss` / `atom`。
  /// - [limit] 限制条目数，<=0 时不添加。
  /// - [fullText] 为 true 时添加 `fulltext=true`（部分路由支持全文）。
  String buildUrl({
    required String baseUrl,
    required String route,
    String format = 'rss',
    int? limit,
    bool fullText = false,
  }) {
    var path = route.trim();
    if (path.isEmpty) {
      throw ArgumentError('RSSHub 路由不能为空');
    }

    final query = <String, String>{
      if (format == 'atom') 'format': 'atom',
      if (limit != null && limit > 0) 'limit': '$limit',
      if (fullText) 'fulltext': 'true',
    };

    // 用户直接粘贴完整 URL 时，直接使用并合并参数。
    if (path.startsWith('http://') || path.startsWith('https://')) {
      final uri = Uri.parse(path);
      return uri
          .replace(queryParameters: {...uri.queryParameters, ...query})
          .toString();
    }

    if (!path.startsWith('/')) {
      path = '/$path';
    }

    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base$path');
    return uri
        .replace(queryParameters: {...uri.queryParameters, ...query})
        .toString();
  }

  /// 判断是否为 RSSHub 地址（用于自动识别）。
  bool isRssHubUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host == 'rsshub.app' ||
        host.endsWith('.rsshub.app') ||
        host.contains('rsshub');
  }
}
