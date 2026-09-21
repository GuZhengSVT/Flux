// 检索页状态与控制器（T022）。
//
// 与列表控制器分开：列表的状态是「筛选 + 分页 + 选择集合 + 批量」，检索的状态是
// 「查询词 + 结果 + 是否在搜」。合成一个会让列表的状态机里出现一半字段在检索时无意义
// （批量勾选在搜索结果上没有语义）。
//
// 三条与产品规则对应的选择：
//
//   1) **空查询不检索、也不清空结果**。用户全选删除再重新输入会经过「空查询」这一帧；
//      这时清空结果会让界面闪一下空态。因此空查询只**停止检索**，已有结果保留到下一次
//      有意义的查询。
//
//   2) **竞态用序号挡住**。检索是异步的，快速输入会让多个查询同时在飞；先发的慢查询
//      后返回会覆盖新结果（表现为「搜索结果与输入框里的词对不上」）。因此每次请求带一个
//      自增序号，只有最新序号的响应才被采纳。
//
//   3) **失败与无结果分开**。失败的检索显示错误 + 重试；无结果显示「没有匹配的文章」。
//      把失败画成空态会让用户以为库里真的没有，从而去改查询词。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

import 'article_search_use_case.dart';
import 'article_ports.dart';

/// 检索页状态。
class ArticleSearchState {
  /// 构造状态。
  const ArticleSearchState({
    this.query = '',
    this.results = const <ArticleSearchResult>[],
    this.total = 0,
    this.loading = false,
    this.error,
    this.searched = false,
    this.scope = SearchScope.all,
    this.filter = ArticleFilter.all,
    this.feedId,
  });

  /// 当前查询词（与输入框绑定）。
  final String query;

  /// 结果。
  final List<ArticleSearchResult> results;

  /// 命中总数。
  final int total;

  /// 是否正在检索。
  final bool loading;

  /// 失败原因。
  final AppError? error;

  /// 是否已经执行过一次有意义的检索。
  ///
  /// 为什么要这个 bool 而不是靠 query.isEmpty 推断：查询词非空且结果为空才是「无结果」，
  /// 而「还没搜过」是另一件事。两者在界面上的文案完全不同（「输入关键词开始检索」与
  /// 「没有匹配的文章」）。
  final bool searched;

  /// 检索范围。
  final SearchScope scope;

  /// 范围是「当前筛选」时生效的筛选。
  final ArticleFilter filter;

  /// 来源限定。
  final int? feedId;

  /// 更新部分字段。
  ArticleSearchState copyWith({
    String? query,
    List<ArticleSearchResult>? results,
    int? total,
    bool? loading,
    AppError? error,
    bool? searched,
    SearchScope? scope,
    ArticleFilter? filter,
    int? feedId,
    bool clearError = false,
    bool clearFeed = false,
  }) => ArticleSearchState(
    query: query ?? this.query,
    results: results ?? this.results,
    total: total ?? this.total,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    searched: searched ?? this.searched,
    scope: scope ?? this.scope,
    filter: filter ?? this.filter,
    feedId: clearFeed ? null : (feedId ?? this.feedId),
  );

  /// 是否处于「输入了词但没有任何结果」（界面据此给无结果空态）。
  bool get isEmptyResult =>
      searched &&
      !loading &&
      error == null &&
      results.isEmpty &&
      query.trim().isNotEmpty;

  /// 是否处于「还没搜过」。
  bool get isIdle => !searched && query.trim().isEmpty;
}

/// 检索控制器。
class ArticleSearchController extends Notifier<ArticleSearchState> {
  /// 请求序号：只有最新一次请求的结果会被采纳（见文件头第 2 条）。
  int _sequence = 0;

  /// 防抖计时器。
  Timer? _debounce;

  @override
  ArticleSearchState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _debounce = null;
    });
    return const ArticleSearchState();
  }

  /// 更新查询词并（防抖后）发起检索。
  ///
  /// 防抖 180 ms：逐字输入时不该每敲一个字都查一次库。这是「打字停顿」与「响应感」之间
  /// 的常见折中；更长会让用户觉得卡，更短则几乎等于每个字符都查。
  void setQuery(String value) {
    state = state.copyWith(query: value);
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      // 空查询：停止检索，但**保留**已有结果（见文件头第 1 条）。
      state = state.copyWith(loading: false, clearError: true, searched: false);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(run());
    });
  }

  /// 设置范围/筛选/来源并重新检索。
  void setScope({
    SearchScope? scope,
    ArticleFilter? filter,
    int? feedId,
    bool clearFeed = false,
  }) {
    state = state.copyWith(
      scope: scope,
      filter: filter,
      feedId: feedId,
      clearFeed: clearFeed,
    );
    unawaited(run());
  }

  /// 立即执行一次检索（手动提交或筛选变化）。
  Future<void> run() async {
    final String text = state.query.trim();
    if (text.isEmpty) {
      state = state.copyWith(loading: false, searched: false, clearError: true);
      return;
    }
    final int sequence = ++_sequence;
    state = state.copyWith(loading: true, clearError: true);

    final SearchArticlesUseCase useCase = ref.read(
      searchArticlesUseCaseProvider,
    );
    final Result<ArticleSearchPage> result = await useCase(
      SearchQuery(
        text: text,
        scope: state.scope,
        filter: state.filter,
        feedId: state.feedId,
      ),
    );

    // 竞态：这次响应已经不是最新的（用户又输入了），直接丢弃——覆盖会让结果与输入框
    // 里的词对不上。
    if (sequence != _sequence) {
      return;
    }
    if (result.isErr) {
      state = state.copyWith(
        loading: false,
        searched: true,
        error: result.errorOrNull,
        results: const <ArticleSearchResult>[],
        total: 0,
      );
      return;
    }
    final ArticleSearchPage page = result.unwrap();
    state = state.copyWith(
      loading: false,
      searched: true,
      results: page.results,
      total: page.total,
      clearError: true,
    );
  }

  /// 清空检索（返回浏览列表）。
  void clear() {
    _debounce?.cancel();
    _sequence++;
    state = const ArticleSearchState();
  }
}

/// 检索控制器 Provider。
///
/// 不设 autoDispose：阅读页在窄窗与宽窗之间切换时组件会重建，autoDispose 会把用户
/// 刚输入的查询词丢掉（表现为「切一下窗口搜索框就空了」）。离开阅读页需要清空时由
/// 页面显式调用 clear——那是用户可感知的动作，比一个隐式的生命周期更清楚。
final NotifierProvider<ArticleSearchController, ArticleSearchState>
searchControllerProvider =
    NotifierProvider<ArticleSearchController, ArticleSearchState>(
      ArticleSearchController.new,
    );
