// 发布元数据（T011，SET-084 只读项的当前取值）。
//
// 放在 lib/core 而不是 lib/app：这些是**跨模块只读数据**——设置页（features）
// 要显示它们，而 lib/app 又负责渲染 features。若把常量放 lib/app，features
// 就得 import app，形成目录级循环依赖。core 是所有层都可以依赖的基础层，
// 是它的正确归属（与 lib/core/design 的设计 token 同理）。
//
// 为什么不读 package_info：
//   - package_info_plus 属于新增第三方依赖，T011 的依赖白名单只允许
//     flutter_localizations（官方 i18n 必需），因此本轮不引入；
//   - 常量有一个明确的失效风险：忘记随 pubspec.yaml 升版本。用测试钉住它
//     （test/app/app_metadata_test.dart 直接读 pubspec.yaml 比对），比引入依赖
//     更早暴露漂移。
//
// URL 口径（SET-084：不存在 URL 时不伪造）：
//   - 仓库与 Issue 地址在 2026-09-21 通过 GitHub 公开接口核实过存在、未归档、
//     且 has_issues 为 true，因此可以展示；
//   - 界面保留「未配置」分支：一旦地址被清空，UI 必须显示未配置，而不是拼一个
//     看起来合理的地址。检查更新与 Release 页由 T053 交付。
library;

/// 应用版本号（与 pubspec.yaml 的 version 一致，由测试保证）。
const String fluxAppVersion = '0.2.0+1';

/// 版本号来源说明（关于页展示，避免读者以为它总与最新发行版一致）。
const String fluxVersionSource = 'pubspec.yaml';

/// 仓库地址；留空表示未配置（界面显示「未配置」）。
const String fluxRepositoryUrl = 'https://github.com/GuZhengSVT/Flux';

/// Issue 地址；留空表示未配置。
const String fluxIssueUrl = 'https://github.com/GuZhengSVT/Flux/issues';

/// 开发者名。
const String fluxDeveloperName = 'GuZhengSVT';

/// 许可标识（仓库根 LICENSE 为 MIT）。
const String fluxLicenseName = 'MIT License';

/// 发布元数据的核实日期。
const String fluxMetadataVerifiedOn = '2026-09-21';
