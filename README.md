# Flux

Flux 是一个跨平台 RSS/Atom 阅读器，使用 Flutter 构建。项目优先桌面端体验，并针对大量图片和视频场景优化滚动流畅度与内存占用。

Flux is a cross-platform RSS/Atom reader built with Flutter. It prioritizes the desktop experience and is optimized for smooth scrolling and memory usage in feeds with many images and videos.

当前版本：0.1.0（开发版本）
Current version: 0.1.0 (development release)

## 目录 / Contents

- [简介 / Introduction](#简介--introduction)
- [功能特性 / Features](#功能特性--features)
- [架构 / Architecture](#架构--architecture)
- [快速开始 / Getting Started](#快速开始--getting-started)
- [构建 / Build](#构建--build)
- [文档 / Documentation](#文档--documentation)

## 简介 / Introduction

### 中文

Flux 是一个面向多平台的 RSS/Atom 聚合阅读器，覆盖 macOS、Windows、Linux、Android 和 iOS。它把订阅管理、分组管理、富文本阅读、媒体缓存和离线存储整合到一个应用中，适合每天阅读大量图文和视频内容的用户。

项目的主要目标：

- 在大量图片和视频的订阅源中保持列表滚动流畅。
- 提供桌面优先的阅读界面，同时保留移动端适配。
- 使用本地 SQLite 缓存和媒体 LRU 清理，降低重复网络请求和磁盘占用。
- 支持 RSSHub，方便扩展非标准 RSS 源。

### English

Flux is a multi-platform RSS/Atom aggregator for macOS, Windows, Linux, Android, and iOS. It combines subscription management, group management, rich article rendering, media caching, and offline storage in one application for users who read many image-heavy or video-heavy feeds every day.

Primary goals:

- Keep article lists smooth with feeds that contain many images and videos.
- Provide a desktop-first reading interface while retaining mobile adaptation.
- Use local SQLite caching and LRU media cleanup to reduce repeated network requests and disk usage.
- Support RSSHub to extend non-standard RSS sources.

## 功能特性 / Features

### 中文

- 订阅管理：添加、重命名、修改链接、删除、刷新、收藏、置顶、分级。
- 分组管理：创建、重命名、删除、拖动调整分组；按分组过滤文章。
- 阅读体验：单列、双列、瀑布流三种布局；今日/本周时间筛选；最新/最旧排序。
- 文章阅读：HTML 和 Markdown 渲染，支持图片、表格、KaTeX 风格数学公式，支持跨段落选择。
- 媒体优化：图片懒加载与按显示尺寸解码，视频内嵌播放，失败时回退到外部播放器。
- RSSHub：可配置实例地址，支持 format、limit、fulltext 参数，失败时自动回退默认实例。
- 离线缓存：SQLite 本地存储；文本保留 30 天、图片保留 7 天、视频保留 1 天；媒体缓存 LRU 自动清理。
- 刷新与通知：后台定时刷新，新文章本地通知。
- 导入导出：OPML 导入和导出。
- 多端适配：桌面端右键菜单和快捷键，移动端响应式界面。
- 主题：暗黑/明亮模式，字体大小可调。

### English

- Subscription management: add, rename, edit URL, delete, refresh, favorite, pin, and rate subscriptions.
- Group management: create, rename, delete, drag subscriptions between groups, and filter articles by group.
- Reading experience: single-column, double-column, and masonry layouts; today/this-week time filters; newest/oldest sorting.
- Article rendering: HTML and Markdown, images, tables, KaTeX-style math, and cross-paragraph selection.
- Media optimization: lazy image loading with size-aware decoding, embedded video playback, and fallback to an external player on failure.
- RSSHub: configurable instance URL, format/limit/fulltext parameters, and automatic fallback to the default instance.
- Offline cache: SQLite local storage; text retained for 30 days, images for 7 days, videos for 1 day; LRU media cache cleanup.
- Refresh and notifications: scheduled background refresh and local notifications for new articles.
- Import/export: OPML import and export.
- Multi-platform: desktop context menus and shortcuts, responsive mobile UI.
- Theme: dark/light mode and adjustable font size.

## 架构 / Architecture

### 中文

Flux 采用分层架构，将 UI、状态、业务和数据分离。

- Presentation：`lib/screens/`、`lib/widgets/`、`lib/theme/`
- State：`lib/providers/`，使用 Riverpod
- Models：`lib/models/`
- Data：`lib/data/`，使用 SQLite（`package:sqlite3`）
- Services：`lib/services/`，包含网络抓取、RSS/Atom 解析、RSSHub、OPML、全文提取、媒体缓存、通知、定时刷新和存储清理

数据流：

```text
Feed URL
  -> FeedFetcher (Dio)
  -> FeedParser (RSS/Atom)
  -> AppDatabase (SQLite)
  -> FeedController (Riverpod)
  -> HomeScreen / ArticleReaderScreen
```

媒体策略：

- 文章列表使用虚拟化列表和瀑布流网格，只构建可见区域。
- 图片使用 `LazyNetworkImage`，按显示尺寸传入 `cacheWidth` / `cacheHeight`，降低解码内存。
- 视频使用 `media_kit` 内嵌播放，失败时回退外部播放器。
- 媒体缓存通过 `flutter_cache_manager` 管理，并按 LRU 清理。

### English

Flux uses a layered architecture that separates UI, state, business logic, and data.

- Presentation: `lib/screens/`, `lib/widgets/`, `lib/theme/`
- State: `lib/providers/`, based on Riverpod
- Models: `lib/models/`
- Data: `lib/data/`, based on SQLite (`package:sqlite3`)
- Services: `lib/services/`, including feed fetching, RSS/Atom parsing, RSSHub, OPML, full-text extraction, media cache, notifications, scheduled refresh, and storage cleanup

Data flow:

```text
Feed URL
  -> FeedFetcher (Dio)
  -> FeedParser (RSS/Atom)
  -> AppDatabase (SQLite)
  -> FeedController (Riverpod)
  -> HomeScreen / ArticleReaderScreen
```

Media strategy:

- Article lists use virtualized lists and staggered grids; only visible items are built.
- Images use `LazyNetworkImage` with `cacheWidth` / `cacheHeight` based on display size to reduce decoding memory.
- Videos use `media_kit` for embedded playback and fall back to an external player on failure.
- Media cache is managed by `flutter_cache_manager` and cleaned with LRU.

## 快速开始 / Getting Started

### 中文

环境要求：

- Flutter SDK 3.x（Dart 3.13 或更高）
- macOS 构建需要 Xcode 和 CocoaPods
- Windows 构建需要 Visual Studio C++ 工具链
- Linux 构建需要 GTK 开发库

```bash
flutter pub get
flutter run -d macos
```

其他平台：

```bash
flutter run -d windows
flutter run -d linux
flutter run -d android
flutter run -d ios
```

### English

Prerequisites:

- Flutter SDK 3.x (Dart 3.13 or newer)
- macOS builds require Xcode and CocoaPods
- Windows builds require the Visual Studio C++ toolchain
- Linux builds require GTK development libraries

```bash
flutter pub get
flutter run -d macos
```

Other platforms:

```bash
flutter run -d windows
flutter run -d linux
flutter run -d android
flutter run -d ios
```

## 构建 / Build

### 中文

```bash
flutter build macos --debug
flutter build windows --debug
flutter build linux --debug
flutter build apk --debug
```

macOS 发布包：

```bash
flutter build macos
```

### English

```bash
flutter build macos --debug
flutter build windows --debug
flutter build linux --debug
flutter build apk --debug
```

macOS release build:

```bash
flutter build macos
```

## 文档 / Documentation

- [工作计划 / Development Plan](PLAN.md)
- [架构说明 / Architecture](docs/architecture.md)
- [视觉规范 / Design](docs/design.md)
