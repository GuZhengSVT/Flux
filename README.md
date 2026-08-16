# Flux

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Android%20%7C%20iOS-lightgrey)](#)
[![Version](https://img.shields.io/github/v/tag/GuZhengSVT/Flux?label=version)](https://github.com/GuZhengSVT/Flux)

Flux is a cross-platform RSS/Atom reader built with Flutter. It prioritizes the desktop experience and is optimized for smooth scrolling and memory usage in feeds with many images and videos.

> [中文说明](README.zh-CN.md)

## Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Build](#build)
- [Roadmap](#roadmap)
- [Documentation](#documentation)
- [License](#license)

## Introduction

Flux is a multi-platform RSS/Atom aggregator for macOS, Windows, Linux, Android, and iOS. It combines subscription management, group management, rich article rendering, media caching, and offline storage in one application for users who read many image-heavy or video-heavy feeds every day.

Primary goals:

- Keep article lists smooth with feeds that contain many images and videos.
- Provide a desktop-first reading interface while retaining mobile adaptation.
- Use local SQLite caching and LRU media cleanup to reduce repeated network requests and disk usage.
- Support RSSHub to extend non-standard RSS sources.

## Features

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

## Architecture

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

## Getting Started

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

## Build

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

## Roadmap

Planned development directions:

- Web and PWA support.
- Cross-device synchronization of read state, favorites, and subscriptions.
- Full-text search based on SQLite FTS5.
- Offline article archive and offline reading improvements.
- Per-feed notification controls and granular refresh schedules.
- More RSSHub route templates and a visual route builder.
- Reader annotations, highlights, and note export.
- Isolate-based feed parsing and database operations for lower UI load.
- Custom themes and a plugin interface.
- Mobile home-screen widgets and deeper system integration.
- Performance profiling and memory tuning for low-end devices.

## Documentation

- [Development Plan](PLAN.md)
- [Architecture](docs/architecture.md)
- [Design](docs/design.md)

## License

This project is licensed under the [MIT License](LICENSE).
