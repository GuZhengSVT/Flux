// infrastructure/platform：安全存储、文件、分享、外部浏览器、后台调度。
//
// 平台差异（macOS Keychain / Android Keystore）只在这一层出现，
// 上层通过 CredentialStore、PlatformScheduler 等接口使用（架构第 2.2 节）。
//
// T010 已落地：credential_store.dart（CredentialStore 接口、内存实现与
// 「条目不存在」语义）、keychain_store.dart（macOS Keychain MethodChannel 适配，
// 无安全存储时明确失败、绝不明文回退）。
// TODO(T020): 文件保存与系统分享。
library;

export 'credential_store.dart';
export 'keychain_store.dart';
