# Flux

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Android%20%7C%20iOS-lightgrey)](#)
[![Version](https://img.shields.io/github/v/tag/GuZhengSVT/Flux?label=version)](https://github.com/GuZhengSVT/Flux)

Flux 是一个跨平台 RSS/Atom 阅读器，使用 Flutter 构建。项目优先桌面端体验，并针对大量图片和视频场景优化滚动流畅度与内存占用。

> [English README](README.md)

## 目录

- [简介](#简介)
- [功能特性](#功能特性)
- [架构](#架构)
- [快速开始](#快速开始)
- [构建](#构建)
- [未来开发方向](#未来开发方向)
- [文档](#文档)
- [开源协议](#开源协议)

## 简介

Flux 是一个面向多平台的 RSS/Atom 聚合阅读器，覆盖 macOS、Windows、Linux、Android 和 iOS。它把订阅管理、分组管理、富文本阅读、媒体缓存和离线存储整合到一个应用中，适合每天阅读大量图文和视频内容的用户。

项目的主要目标：

- 在大量图片和视频的订阅源中保持列表滚动流畅。
- 提供桌面优先的阅读界面，同时保留移动端适配。
- 使用本地 SQLite 缓存和媒体 LRU 清理，降低重复网络请求和磁盘占用。
- 支持 RSSHub，方便扩展非标准 RSS 源。

## 功能特性

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

## 架构

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

## 快速开始

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

## 构建

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

## 未来开发方向

计划中的开发方向：

- Web 与 PWA 支持。
- 阅读状态、收藏和订阅的跨设备同步。
- 基于 SQLite FTS5 的全文搜索。
- 离线文章归档与离线阅读增强。
- 按订阅源设置通知开关和更细粒度的刷新计划。
- 更多 RSSHub 路由模板和可视化路由配置界面。
- 阅读器批注、高亮和笔记导出。
- 将解析和数据库操作迁移到 Isolate，降低 UI 线程负载。
- 自定义主题和插件接口。
- 移动端桌面小组件和更深的系统集成。
- 针对低端设备的性能分析和内存优化。

## 文档

- [工作计划](PLAN.md)
- [架构说明](docs/architecture.md)
- [视觉规范](docs/design.md)

## 开源协议

本项目使用 [MIT License](LICENSE)。
