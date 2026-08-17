import 'package:test/test.dart';

import 'package:flux/services/rsshub_service.dart';

void main() {
  test('RSSHubService builds route URL', () {
    const service = RSSHubService();
    final url = service.buildUrl(
      baseUrl: 'https://rsshub.app/',
      route: 'zhihu/daily',
      format: 'rss',
      limit: 10,
      fullText: true,
    );
    expect(url, 'https://rsshub.app/zhihu/daily?limit=10&fulltext=true');

    final atom = service.buildUrl(
      baseUrl: 'https://rsshub.app',
      route: '/bilibili/user/video/1',
      format: 'atom',
    );
    expect(atom, 'https://rsshub.app/bilibili/user/video/1?format=atom');
  });
}