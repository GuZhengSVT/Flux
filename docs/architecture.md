# Flux 架构说明

## 分层

- **Presentation**: Flutter Widgets，位于 `lib/screens/`、`lib/widgets/`、`lib/theme/`
- **State**: Riverpod，位于 `lib/providers/`
- **Models**: `lib/models/`
- **Data**: `lib/data/app_database.dart`，使用 SQLite（`package:sqlite3`）
- **Services**: `lib/services/`，包含网络抓取、RSS/Atom 解析、RSSHub、OPML、全文提取、媒体缓存、通知、定时刷新和存储清理

## 数据流

```text
Feed URL
  -> FeedFetcher (Dio)
  -> FeedParser (RSS/Atom)
  -> AppDatabase (SQLite)
  -> FeedController (Riverpod)
  -> HomeScreen / ArticleReaderScreen
```

## 数据库

- SQLite，直接使用 `package:sqlite3`，避免 ORM 代码生成。
- 表：`feeds`、`articles`、`groups`。
- 唯一索引 `(feed_id, link, title)` 防止重复抓取。
- `_ensureColumn` 处理新增订阅字段的迁移。

## 媒体策略

- 文章列表使用虚拟化列表与瀑布流网格，只构建可见区域。
- 图片使用 `LazyNetworkImage`，按显示尺寸传入 `cacheWidth/cacheHeight`，降低解码内存。
- 图片缓存由 `cached_network_image` 和 `flutter_cache_manager` 提供。
- 视频使用 `media_kit` 内嵌播放，失败时回退外部播放器。
- 媒体缓存按 LRU 清理；保留策略为文本 30 天、图片 7 天、视频 1 天。

## RSSHub

- 支持配置实例基础地址。
- 路由构建支持 format、limit、fulltext 参数。
- 非默认实例失败时自动回退默认实例。

## 扩展点

- `FeedParser` 可放入 Isolate 运行。
- `AppDatabase` 可增加 OPML 导入表和全文检索 FTS5。
- 刷新调度与本地通知可扩展为系统级后台任务。
