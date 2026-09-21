// infrastructure/platform：安全存储、文件、分享、外部浏览器、后台调度。
//
// 平台差异（macOS Keychain / Android Keystore）只在这一层出现，
// 上层通过 CredentialStore、PlatformScheduler 等接口使用（架构第 2.2 节）。
//
// TODO(T010): Keychain/Keystore 凭据存储。
// TODO(T020): 文件保存与系统分享。
library;
