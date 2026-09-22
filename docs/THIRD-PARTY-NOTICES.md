# 第三方软件与原创素材声明

> 本文件由 `dart run tool/generate_third_party_notices.dart`生成，请勿手改。
> 版本号取自已提交的 `pubspec.lock`（本应用提交 lock，因此清单对应实际构建的版本）。
> `test/app/third_party_notices_test.dart`会断言本文件与 lock 一致。

## Flux 自身

| 项目 | 版本 | 许可证 | 版权 |
| --- | --- | --- | --- |
| Flux（本仓库） | 0.2.0+1 | MIT | Copyright (c) 2025 GuZhengSVT |

仓库根 `LICENSE`为 MIT。原创素材（`assets/icons/`下的 28 个 SVG、
`assets/branding/flux-app-icon.svg`应用图标设计源）由本项目绘制，同样按 MIT 授权；每个素材文件顶部都有各自的授权注释。

## 运行时依赖（会进入发布包）

| 包 | 版本 | 许可证 | 版权声明（LICENSE 中的版权行） |
| --- | --- | --- | --- |
| cupertino_icons | 1.0.9 | MIT | Copyright (c) 2016 Vladimir Kharlampidi |
| drift | 2.35.0 | MIT | Copyright (c) 2021 Simon Binder |
| file_selector | 1.1.0 | BSD-3-Clause | Copyright 2013 The Flutter Authors |
| flutter_math_fork | 0.7.4 | Apache-2.0 | 未单独署名（见包内 LICENSE 正文） |
| flutter_riverpod | 3.4.3 | MIT | Copyright (c) 2020 Remi Rousselet |
| flutter_svg | 2.3.0 | MIT | Copyright (c) 2018 Dan Field |
| http | 1.6.0 | BSD-3-Clause | Copyright 2014, the Dart project authors. |
| intl | 0.20.3 | BSD-3-Clause | Copyright 2013, the Dart project authors. |
| markdown | 7.3.1 | BSD-3-Clause | Copyright 2012, the Dart project authors. |
| path | 1.9.1 | BSD-3-Clause | Copyright 2014, the Dart project authors. |
| path_provider | 2.1.6 | BSD-3-Clause | Copyright 2013 The Flutter Authors |
| sqlite3 | 3.6.0 | MIT | Copyright (c) 2020 Simon Binder |
| url_launcher | 6.3.2 | BSD-3-Clause | Copyright 2013 The Flutter Authors. All rights reserved. |
| xml | 7.0.1 | MIT | Copyright (c) 2006-2026 Lukas Renggli. |

### Flutter / Dart SDK

Flutter 与 Dart SDK 按 BSD-3-Clause 授权（Copyright 2014 The Flutter Authors. All rights reserved.），随工具链分发，不逐版本抄录正文。

### 静态链接的原生库

SQLite（经 `sqlite3`包的 native assets 机制带入）为 Public Domain。

## 开发期依赖（不进入发布包）

以下包只在开发/测试期使用，不随应用分发：

- build_runner 2.16.1（BSD-3-Clause）
- drift_dev 2.35.0（MIT）
- flutter_lints 6.0.0（BSD-3-Clause）

另有 109 个传递依赖（由上述包引入），许可证随各自发布的包分发；完整列表见 `pubspec.lock`的 `packages`段。本应用不直接引用它们的 API。

## 与许可证相关的已知取舍

- **不使用 WebView 或网页运行时**（架构第 8 节）：数学排版走 flutter_math_fork 纯自绘，Markdown 只调用解析器，因此不存在内嵌浏览器内核的许可证与安全面。
- **不引入在线字体或图标库**：图标为自制 SVG，字体只用系统字体。
- 无法辨认许可证正文的包不会被写成某一种许可证（清单里标「见正文」），避免在发布物里给出错误的 SPDX 标识。

