import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../services/rsshub_service.dart';
import '../theme/flux_theme.dart';

enum _AddMode { rss, rsshub }

class AddFeedScreen extends ConsumerStatefulWidget {
  const AddFeedScreen({super.key});

  @override
  ConsumerState<AddFeedScreen> createState() => _AddFeedScreenState();
}

class _AddFeedScreenState extends ConsumerState<AddFeedScreen> {
  final _urlController = TextEditingController();
  final _rsshubBaseController = TextEditingController();
  final _routeController = TextEditingController();
  final _limitController = TextEditingController();

  _AddMode _mode = _AddMode.rss;
  String _format = 'rss';
  bool _fullText = false;

  @override
  void initState() {
    super.initState();
    _rsshubBaseController.text = ref.read(settingsProvider).rsshubBaseUrl;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _rsshubBaseController.dispose();
    _routeController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    late final String url;
    String? rsshubBase;

    if (_mode == _AddMode.rsshub) {
      final route = _routeController.text.trim();
      if (route.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请输入 RSSHub 路由路径')));
        return;
      }
      rsshubBase = _rsshubBaseController.text.trim();
      try {
        url = const RSSHubService().buildUrl(
          baseUrl: rsshubBase,
          route: route,
          format: _format,
          limit: int.tryParse(_limitController.text.trim()),
          fullText: _fullText,
        );
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('RSSHub 地址生成失败：$e')));
        return;
      }
    } else {
      final rawUrl = _urlController.text.trim();
      if (rawUrl.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请输入 Feed URL')));
        return;
      }
      url = rawUrl;
    }

    final added = await _tryAdd(url);
    if (added) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    if (!mounted) {
      return;
    }

    // RSSHub 实例不可用时，自动改用默认实例重试一次。
    if (_mode == _AddMode.rsshub &&
        rsshubBase != null &&
        rsshubBase != 'https://rsshub.app') {
      final fallbackUrl = const RSSHubService().buildUrl(
        baseUrl: 'https://rsshub.app',
        route: _routeController.text.trim(),
        format: _format,
        limit: int.tryParse(_limitController.text.trim()),
        fullText: _fullText,
      );
      final fallbackAdded = await _tryAdd(fallbackUrl);
      if (fallbackAdded && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前 RSSHub 实例不可用，已自动改用默认实例 https://rsshub.app'),
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<bool> _tryAdd(String url) async {
    final controller = ref.read(feedControllerProvider.notifier);
    await controller.addFeed(url);
    if (!mounted) {
      return false;
    }
    final error = ref.read(feedControllerProvider).error;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(feedControllerProvider).loading;
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('添加订阅'),
        actions: [
          TextButton(
            onPressed: loading ? null : _submit,
            child: const Text('添加'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const _FluxMark(),
          const SizedBox(height: 24),
          Text('添加订阅', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          SegmentedButton<_AddMode>(
            segments: const [
              ButtonSegment(
                value: _AddMode.rss,
                label: Text('RSS / Atom'),
                icon: Icon(Icons.rss_feed),
              ),
              ButtonSegment(
                value: _AddMode.rsshub,
                label: Text('RSSHub'),
                icon: Icon(Icons.hub_outlined),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) {
              setState(() => _mode = selection.first);
            },
          ),
          const SizedBox(height: 20),
          if (_mode == _AddMode.rss) ...[
            TextField(
              controller: _urlController,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Feed URL',
                hintText: 'https://example.com/feed.xml',
                prefixIcon: Icon(Icons.rss_feed),
              ),
            ),
          ] else ...[
            TextField(
              controller: _rsshubBaseController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'RSSHub 实例',
                hintText: 'https://rsshub.app',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _routeController,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: '路由路径',
                hintText: '/zhihu/daily 或 zhihu/daily',
                prefixIcon: Icon(Icons.route_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _format,
                    decoration: const InputDecoration(labelText: '输出格式'),
                    items: const [
                      DropdownMenuItem(value: 'rss', child: Text('RSS')),
                      DropdownMenuItem(value: 'atom', child: Text('Atom')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _format = value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _limitController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '条数限制',
                      hintText: '可选',
                      suffixText: '条',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('抓取全文'),
              subtitle: const Text('部分路由支持 fulltext=true，会增加抓取时间'),
              value: _fullText,
              onChanged: (value) => setState(() => _fullText = value),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Text(
              '当前默认实例：${settings.rsshubBaseUrl}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (loading)
            const LinearProgressIndicator(color: FluxColors.red)
          else
            Text(
              _mode == _AddMode.rsshub
                  ? '输入 RSSHub 路由路径即可生成订阅地址，例如 /zhihu/daily。'
                  : '也可以稍后在浏览器中找到某个网站的 RSS 图标，复制其链接粘贴到这里。',
              style: const TextStyle(color: FluxColors.gray),
            ),
        ],
      ),
    );
  }
}

class _FluxMark extends StatelessWidget {
  const _FluxMark();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Stack(
        children: [
          Container(width: 72, height: 72, color: FluxColors.red),
          Positioned(
            right: -8,
            bottom: -8,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                border: Border.all(color: FluxColors.red, width: 4),
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: Transform.rotate(
              angle: 0.3,
              child: Container(width: 48, height: 4, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
