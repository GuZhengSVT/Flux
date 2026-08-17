import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../services/media_cache.dart';
import '../theme/flux_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _openCategory(BuildContext context, _SettingsCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CategoryPage(category: category),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ColoredBox(
        color: isDark
            ? FluxColors.darkSurface.withValues(alpha: 0.50)
            : FluxColors.bone.withValues(alpha: 0.50),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            _CategoryTile(
              icon: Icons.palette_outlined,
              title: '外观',
              subtitle: '主题模式、缩略图、背景透明度',
              onTap: () => _openCategory(context, _SettingsCategory.appearance),
            ),
            _CategoryTile(
              icon: Icons.chrome_reader_mode_outlined,
              title: '阅读',
              subtitle: '正文字号',
              onTap: () => _openCategory(context, _SettingsCategory.reading),
            ),
            _CategoryTile(
              icon: Icons.notifications_outlined,
              title: '刷新与通知',
              subtitle: '自动刷新间隔',
              onTap: () => _openCategory(context, _SettingsCategory.refresh),
            ),
            _CategoryTile(
              icon: Icons.storage_outlined,
              title: '存储与缓存',
              subtitle: '保留天数、缓存上限、自动缓存视频',
              onTap: () => _openCategory(context, _SettingsCategory.storage),
            ),
            _CategoryTile(
              icon: Icons.sync_alt,
              title: '数据',
              subtitle: 'OPML 导入与导出',
              onTap: () => _openCategory(context, _SettingsCategory.data),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: _FluxFooter(),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SettingsCategory { appearance, reading, refresh, storage, data }

class _CategoryPage extends ConsumerWidget {
  const _CategoryPage({required this.category});

  final _SettingsCategory category;

  Future<void> _exportOpml(WidgetRef ref) async {
    final xml = ref.read(feedControllerProvider.notifier).exportOpml();
    final uri = await FilePicker.saveFile(
      dialogTitle: '导出 OPML',
      fileName: 'flux-feeds.opml',
      bytes: Uint8List.fromList(utf8.encode(xml)),
      type: FileType.custom,
      allowedExtensions: ['opml', 'xml'],
    );
    if (uri == null) {
      return;
    }
  }

  Future<void> _importOpml(BuildContext context, WidgetRef ref) async {
    final file = await FilePicker.pickFile(
      dialogTitle: '导入 OPML',
      type: FileType.custom,
      allowedExtensions: ['opml', 'xml'],
    );
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    final xml = utf8.decode(bytes);
    final added = await ref
        .read(feedControllerProvider.notifier)
        .importOpml(xml);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导入完成，新增 $added 个订阅')));
    }
  }

  String get _title => switch (category) {
    _SettingsCategory.appearance => '外观',
    _SettingsCategory.reading => '阅读',
    _SettingsCategory.refresh => '刷新与通知',
    _SettingsCategory.storage => '存储与缓存',
    _SettingsCategory.data => '数据',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ColoredBox(
        color: isDark
            ? FluxColors.darkSurface.withValues(alpha: 0.50)
            : FluxColors.bone.withValues(alpha: 0.50),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: switch (category) {
            _SettingsCategory.appearance => [
              const _PageHint('主题模式'),
              SegmentedButton<FluxThemePreference>(
                segments: const [
                  ButtonSegment(
                    value: FluxThemePreference.system,
                    label: Text('跟随系统'),
                    icon: Icon(Icons.brightness_auto),
                  ),
                  ButtonSegment(
                    value: FluxThemePreference.light,
                    label: Text('明亮'),
                    icon: Icon(Icons.light_mode),
                  ),
                  ButtonSegment(
                    value: FluxThemePreference.dark,
                    label: Text('暗黑'),
                    icon: Icon(Icons.dark_mode),
                  ),
                ],
                selected: {settings.themePreference},
                onSelectionChanged: (selection) {
                  controller.setTheme(selection.first);
                },
              ),
              const Divider(height: 28),
              const _PageHint('背景透明度（0% 隐藏，100% 最清晰）'),
              _SliderSetting(
                title: '背景透明度',
                value: settings.backgroundOpacity,
                min: 0,
                max: 1,
                divisions: 20,
                label: '${(settings.backgroundOpacity * 100).round()}%',
                onChanged: controller.setBackgroundOpacity,
              ),
              const Divider(height: 28),
              SwitchListTile(
                title: const Text('显示缩略图'),
                subtitle: const Text('关闭后文章列表不加载图片，可提升滚动流畅度'),
                value: settings.showThumbnails,
                onChanged: controller.setShowThumbnails,
              ),
            ],
            _SettingsCategory.reading => [
              const _PageHint('正文字号（拖动调节）'),
              _SliderSetting(
                title: '正文字号',
                value: settings.readerFontSize,
                min: 12,
                max: 24,
                divisions: 12,
                label: '${settings.readerFontSize.round()}px',
                onChanged: controller.setReaderFontSize,
              ),
            ],
            _SettingsCategory.refresh => [
              _NumberField(
                label: '自动刷新间隔',
                description: '应用运行期间每隔多少分钟自动检查一次新文章',
                value: settings.refreshIntervalMinutes,
                min: 5,
                max: 180,
                suffix: '分钟',
                onChanged: controller.setRefreshInterval,
              ),
            ],
            _SettingsCategory.storage => [
              _NumberField(
                label: '文本保留时间',
                description: '超过该时间的文章会被自动清理',
                value: settings.textRetentionDays,
                min: 7,
                max: 180,
                suffix: '天',
                onChanged: controller.setTextRetentionDays,
              ),
              _NumberField(
                label: '图片缓存保留',
                description: '图片缓存超过该时间后自动失效',
                value: settings.imageRetentionDays,
                min: 1,
                max: 30,
                suffix: '天',
                onChanged: controller.setImageRetentionDays,
              ),
              _NumberField(
                label: '视频缓存保留',
                description: '视频缓存超过该时间后自动失效',
                value: settings.videoRetentionDays,
                min: 1,
                max: 30,
                suffix: '天',
                onChanged: controller.setVideoRetentionDays,
              ),
              _NumberField(
                label: '缓存文件数上限',
                description: '缓存条目超过该值时，自动清理最久未使用的内容',
                value: settings.maxCacheItems,
                min: 100,
                max: 5000,
                suffix: '个',
                onChanged: controller.setMaxCacheItems,
              ),
              const Divider(height: 20),
              SwitchListTile(
                title: const Text('自动缓存视频'),
                subtitle: const Text('开启后视频先缓存到本地再播放，可能增加等待时间'),
                value: settings.autoCacheVideos,
                onChanged: controller.setAutoCacheVideos,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _clearMediaCache(context),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('立即清空媒体缓存'),
                ),
              ),
            ],
            _SettingsCategory.data => [
              TextFormField(
                initialValue: settings.rsshubBaseUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'RSSHub 默认实例',
                  helperText: '添加 RSSHub 路由时使用的默认地址',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
                onFieldSubmitted: controller.setRsshubBaseUrl,
              ),
              const Divider(height: 24),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _importOpml(context, ref),
                  icon: const Icon(Icons.file_open),
                  label: const Text('导入 OPML'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _exportOpml(ref),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('导出 OPML'),
                ),
              ),
            ],
          },
        ),
      ),
    );
  }

  Future<void> _clearMediaCache(BuildContext context) async {
    await MediaCache.instance.clearAll();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('媒体缓存已清空')));
    }
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: FluxColors.red),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: FluxColors.concrete),
          ],
        ),
      ),
    );
  }
}

class _PageHint extends StatelessWidget {
  const _PageHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// 数字填空输入，带范围限制。
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final String description;
  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = widget.value.toString();
      return;
    }
    final clamped = parsed.clamp(widget.min, widget.max);
    if (clamped != parsed) {
      _controller.text = clamped.toString();
    }
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.description,
          suffixText: widget.suffix,
          helperMaxLines: 2,
        ),
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          value: value.clamp(min, max),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _FluxFooter extends StatelessWidget {
  const _FluxFooter();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const Text(
            'Flux',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
              color: FluxColors.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '简洁高效的 RSS 阅读器',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
