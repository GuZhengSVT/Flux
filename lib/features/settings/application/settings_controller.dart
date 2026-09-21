// 设置页状态控制器（T011）。
//
// 范围：本控制器只服务 T011 真正生效的两项（SET-001 界面语言、SET-002 主题），
// 以及「设置是否可写」这一个运行时状态。其余 SET 项不在这里出现——它们没有实现，
// 因此既不能读写，也不应该有一个看起来能用的开关。
//
// 关键设计：**写入失败必须可见**。
// 设置是用户明确表达意图的动作，静默失败（比如磁盘只读、值被校验拒绝）会让界面
// 显示一个并未保存的状态。因此这里保留 [lastWriteFailed] 与 [lastErrorCode]，
// 由页面渲染成提示；同时把值回退为**已保存的值**，而不是乐观地显示新值。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/l10n/l10n.dart';

import 'settings_store.dart';

/// 设置读写端口的 Provider。
///
/// 默认实现**故意抛错**：具体实现（T010 的 SettingsRepository 适配器）住在
/// infrastructure，只有组合根（lib/app）知道该用哪一个。若某条路径漏了 override，
/// 这里会立刻失败并说明原因，而不是静默用一份内存假数据把「已持久化」演得像真的一样。
final Provider<SettingsStore> settingsStoreProvider = Provider<SettingsStore>(
  (Ref ref) => throw StateError(
    'settingsStoreProvider 未被组合根覆盖：请检查 main.dart 的 ProviderScope overrides',
  ),
);

/// 设置页的一次写入结果。
final class SettingsWriteOutcome {
  /// 构造写入结果。
  const SettingsWriteOutcome({required this.succeeded, this.errorCode});

  /// 是否写入成功。
  final bool succeeded;

  /// 失败时的错误码（SET 编号或操作名），不含任何值内容。
  final String? errorCode;
}

/// 设置页状态：当前生效值 + 写入反馈。
final class SettingsState {
  /// 构造状态。
  const SettingsState({
    required this.language,
    required this.theme,
    required this.loaded,
    this.loadErrorCode,
    this.lastWriteFailed = false,
    this.lastErrorCode,
  });

  /// 初始状态：在读到存储前使用注册表默认值。
  ///
  /// 默认值直接来自 SET 注册表口径（system/system），不是另写一份常量，
  /// 避免「界面默认」与「文档默认」漂移。
  factory SettingsState.initial() => const SettingsState(
    language: AppLanguageSetting.system,
    theme: 'system',
    loaded: false,
    loadErrorCode: null,
  );

  /// SET-001 界面语言。
  final String language;

  /// SET-002 主题。
  final String theme;

  /// 是否已从存储读到有效值。
  final bool loaded;

  /// 读取失败时的错误码；非空表示当前显示的是默认值而非已存值。
  final String? loadErrorCode;

  /// 上一次写入是否失败。
  final bool lastWriteFailed;

  /// 上一次失败的错误码。
  final String? lastErrorCode;

  /// 复制并覆盖部分字段。
  SettingsState copyWith({
    String? language,
    String? theme,
    bool? loaded,
    String? loadErrorCode,
    bool clearLoadError = false,
    bool? lastWriteFailed,
    String? lastErrorCode,
    bool clearLastError = false,
  }) => SettingsState(
    language: language ?? this.language,
    theme: theme ?? this.theme,
    loaded: loaded ?? this.loaded,
    loadErrorCode: clearLoadError
        ? null
        : (loadErrorCode ?? this.loadErrorCode),
    lastWriteFailed: lastWriteFailed ?? this.lastWriteFailed,
    lastErrorCode: clearLastError
        ? null
        : (lastErrorCode ?? this.lastErrorCode),
  );
}

/// 设置页控制器。
///
/// 用 AsyncNotifier 而不是普通 Notifier：首次读取要走数据库，是异步的；
/// 让 Riverpod 承载 loading 状态，页面就不必自己写一套「还没读到就先显示什么」。
final class SettingsController extends AsyncNotifier<SettingsState> {
  /// 写入时按需取端口。
  ///
  /// 用 read 而不是 watch：写入是**动作**，不应该因为端口对象变化而重跑；而且
  /// 在方法里 watch 会建立持久依赖，语义上也不对。
  SettingsStore get _store => ref.read(settingsStoreProvider);

  @override
  Future<SettingsState> build() async {
    // 读取时用 watch：端口本身是可以被替换的（组合根注入、测试替换）。
    // 若这里用 read，替换端口后控制器不会重建，界面会继续显示旧端口的数据——
    // 这个 bug 在 T011 的证据采集里真实出现过：同一棵 element 树里换成「英文」
    // 端口后界面仍是中文。watch 让「端口变了就重新读」成为默认行为。
    final SettingsStore store = ref.watch(settingsStoreProvider);
    // 默认值取自注册表口径，读取失败时退回到它并明确标记未加载成功。
    final SettingsState fallback = SettingsState.initial();
    final Result<Object?> language = await store.readSetting(SettingId.set001);
    final Result<Object?> theme = await store.readSetting(SettingId.set002);

    final String? errorCode = language.isErr
        ? SettingId.set001.code
        : (theme.isErr ? SettingId.set002.code : null);

    return fallback.copyWith(
      language: _asLanguage(language.valueOrNull, fallback.language),
      theme: _asTheme(theme.valueOrNull, fallback.theme),
      loaded: errorCode == null,
      loadErrorCode: errorCode,
      clearLoadError: errorCode == null,
    );
  }

  /// 写入 SET-001 界面语言。
  Future<SettingsWriteOutcome> setLanguage(String value) =>
      _write(SettingId.set001, value, (SettingsState state, String written) {
        state = state.copyWith(language: written);
        return state;
      });

  /// 写入 SET-002 主题。
  Future<SettingsWriteOutcome> setTheme(String value) =>
      _write(SettingId.set002, value, (SettingsState state, String written) {
        state = state.copyWith(theme: written);
        return state;
      });

  /// 清掉上一次的写入失败提示。
  void clearWriteFailure() {
    final SettingsState? current = state.value;
    if (current == null || !current.lastWriteFailed) {
      return;
    }
    state = AsyncData<SettingsState>(
      current.copyWith(lastWriteFailed: false, clearLastError: true),
    );
  }

  /// 通用的「先写存储、成功了再改状态」流程。
  ///
  /// 顺序不能反：若先改内存状态再写存储，一次失败的写入会让界面显示一个并未
  /// 保存的值，用户下次启动又看到旧值，且中间没有任何提示。
  Future<SettingsWriteOutcome> _write(
    SettingId id,
    String value,
    SettingsState Function(SettingsState state, String written) apply,
  ) async {
    final SettingsState current = state.value ?? SettingsState.initial();
    final Result<Object?> result = await _store.writeSetting(id, value);
    if (result.isErr) {
      state = AsyncData<SettingsState>(
        current.copyWith(lastWriteFailed: true, lastErrorCode: id.code),
      );
      return SettingsWriteOutcome(succeeded: false, errorCode: id.code);
    }
    final String written = result.valueOrNull is String
        ? result.valueOrNull! as String
        : value;
    state = AsyncData<SettingsState>(
      apply(
        current.copyWith(lastWriteFailed: false, clearLastError: true),
        written,
      ),
    );
    return const SettingsWriteOutcome(succeeded: true);
  }

  /// 把存储中的值收敛为 SET-001 的合法取值。
  static String _asLanguage(Object? value, String fallback) =>
      value is String && AppLanguageSetting.values.contains(value)
      ? value
      : fallback;

  /// 把存储中的值收敛为 SET-002 的合法取值。
  static String _asTheme(Object? value, String fallback) =>
      value is String && _themeValues.contains(value) ? value : fallback;
}

/// SET-002 的合法取值（与注册表口径一致）。
const List<String> _themeValues = <String>['system', 'light', 'dark'];

/// 设置页控制器的 Provider。
final AsyncNotifierProvider<SettingsController, SettingsState>
settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, SettingsState>(
      SettingsController.new,
    );
