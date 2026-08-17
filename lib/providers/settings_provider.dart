import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/media_cache.dart';

enum FluxThemePreference { system, light, dark }

class SettingsState {
  const SettingsState({
    this.themePreference = FluxThemePreference.system,
    this.showThumbnails = true,
    this.readerFontSize = 16,
    this.refreshIntervalMinutes = 30,
    this.textRetentionDays = 30,
    this.imageRetentionDays = 7,
    this.videoRetentionDays = 1,
    this.maxCacheItems = 500,
    this.autoCacheVideos = false,
    this.rsshubBaseUrl = 'https://rsshub.app',
  });

  final FluxThemePreference themePreference;
  final bool showThumbnails;
  final double readerFontSize;
  final int refreshIntervalMinutes;

  // 存储与缓存
  final int textRetentionDays;
  final int imageRetentionDays;
  final int videoRetentionDays;
  final int maxCacheItems;
  final bool autoCacheVideos;

  // RSSHub
  final String rsshubBaseUrl;

  ThemeMode get themeMode => switch (themePreference) {
    FluxThemePreference.system => ThemeMode.system,
    FluxThemePreference.light => ThemeMode.light,
    FluxThemePreference.dark => ThemeMode.dark,
  };

  SettingsState copyWith({
    FluxThemePreference? themePreference,
    bool? showThumbnails,
    double? readerFontSize,
    int? refreshIntervalMinutes,
    int? textRetentionDays,
    int? imageRetentionDays,
    int? videoRetentionDays,
    int? maxCacheItems,
    bool? autoCacheVideos,
    String? rsshubBaseUrl,
  }) {
    return SettingsState(
      themePreference: themePreference ?? this.themePreference,
      showThumbnails: showThumbnails ?? this.showThumbnails,
      readerFontSize: readerFontSize ?? this.readerFontSize,
      refreshIntervalMinutes:
          refreshIntervalMinutes ?? this.refreshIntervalMinutes,
      textRetentionDays: textRetentionDays ?? this.textRetentionDays,
      imageRetentionDays: imageRetentionDays ?? this.imageRetentionDays,
      videoRetentionDays: videoRetentionDays ?? this.videoRetentionDays,
      maxCacheItems: maxCacheItems ?? this.maxCacheItems,
      autoCacheVideos: autoCacheVideos ?? this.autoCacheVideos,
      rsshubBaseUrl: rsshubBaseUrl ?? this.rsshubBaseUrl,
    );
  }

  Map<String, Object> toJson() {
    return {
      'themePreference': themePreference.name,
      'showThumbnails': showThumbnails,
      'readerFontSize': readerFontSize,
      'refreshIntervalMinutes': refreshIntervalMinutes,
      'textRetentionDays': textRetentionDays,
      'imageRetentionDays': imageRetentionDays,
      'videoRetentionDays': videoRetentionDays,
      'maxCacheItems': maxCacheItems,
      'autoCacheVideos': autoCacheVideos,
      'rsshubBaseUrl': rsshubBaseUrl,
    };
  }

  factory SettingsState.fromJson(Map<String, Object?> json) {
    return SettingsState(
      themePreference:
          FluxThemePreference.values.asNameMap()[json['themePreference']] ??
          FluxThemePreference.system,
      showThumbnails: json['showThumbnails'] as bool? ?? true,
      readerFontSize: (json['readerFontSize'] as num?)?.toDouble() ?? 16,
      refreshIntervalMinutes: json['refreshIntervalMinutes'] as int? ?? 30,
      textRetentionDays: json['textRetentionDays'] as int? ?? 30,
      imageRetentionDays: json['imageRetentionDays'] as int? ?? 7,
      videoRetentionDays: json['videoRetentionDays'] as int? ?? 1,
      maxCacheItems: json['maxCacheItems'] as int? ?? 500,
      autoCacheVideos: json['autoCacheVideos'] as bool? ?? false,
      rsshubBaseUrl: json['rsshubBaseUrl'] as String? ?? 'https://rsshub.app',
    );
  }
}

class SettingsController extends StateNotifier<SettingsState> {
  SettingsController(super.state) {
    _applyMediaCache();
  }

  /// 当前设置快照（避免在 main 中直接访问 StateNotifier.state）。
  SettingsState get value => state;

  static const _prefsKey = 'flux_settings';

  static Future<SettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) {
      return SettingsController(const SettingsState());
    }
    try {
      final decoded = Map<String, Object?>.from(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
      return SettingsController(SettingsState.fromJson(decoded));
    } catch (_) {
      return SettingsController(const SettingsState());
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  void _applyMediaCache() {
    MediaCache.instance.configure(
      imageRetentionDays: state.imageRetentionDays,
      videoRetentionDays: state.videoRetentionDays,
      maxCacheItems: state.maxCacheItems,
    );
  }

  Future<void> setTheme(FluxThemePreference preference) async {
    state = state.copyWith(themePreference: preference);
    await _save();
  }

  Future<void> setShowThumbnails(bool value) async {
    state = state.copyWith(showThumbnails: value);
    await _save();
  }

  Future<void> setReaderFontSize(double value) async {
    state = state.copyWith(readerFontSize: value);
    await _save();
  }

  Future<void> setRefreshInterval(int minutes) async {
    state = state.copyWith(refreshIntervalMinutes: minutes);
    await _save();
  }

  Future<void> setTextRetentionDays(int days) async {
    state = state.copyWith(textRetentionDays: days);
    await _save();
  }

  Future<void> setImageRetentionDays(int days) async {
    state = state.copyWith(imageRetentionDays: days);
    _applyMediaCache();
    await _save();
  }

  Future<void> setVideoRetentionDays(int days) async {
    state = state.copyWith(videoRetentionDays: days);
    _applyMediaCache();
    await _save();
  }

  Future<void> setMaxCacheItems(int items) async {
    state = state.copyWith(maxCacheItems: items);
    _applyMediaCache();
    await _save();
  }

  Future<void> setAutoCacheVideos(bool value) async {
    state = state.copyWith(autoCacheVideos: value);
    await _save();
  }

  Future<void> setRsshubBaseUrl(String value) async {
    final normalized = value.trim().isEmpty
        ? 'https://rsshub.app'
        : value.trim().replaceAll(RegExp(r'/+$'), '');
    state = state.copyWith(rsshubBaseUrl: normalized);
    await _save();
  }
}

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
      throw UnimplementedError(
        'settingsControllerProvider must be overridden in main()',
      );
    });

final settingsProvider = Provider<SettingsState>(
  (ref) => ref.watch(settingsControllerProvider),
);
