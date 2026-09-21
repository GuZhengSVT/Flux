// infrastructure/platform：安全存储、文件、分享、外部浏览器、后台调度。
//
// 平台差异（macOS Keychain / Android Keystore）只在这一层出现，
// 上层通过 CredentialStore、PlatformScheduler 等接口使用（架构第 2.2 节）。
//
// T010 已落地：credential_store.dart（CredentialStore 接口、内存实现与
// 「条目不存在」语义）、keychain_store.dart（macOS Keychain MethodChannel 适配，
// 无安全存储时明确失败、绝不明文回退）。
// T020 已落地：external_link_opener.dart（url_launcher 外开，协议二次校验）、
// image_save_service.dart（HTTP 下载 + 系统保存面板，带下载上限）、
// system_share_service.dart（macOS NSSharingServicePicker 原生通道，不可用时由上层回退复制）。
// TODO(T021): 远程图片缓存与媒体大小/MIME 限额。
library;

export 'credential_store.dart';
export 'device_local_zone.dart';
export 'external_link_opener.dart';
export 'image_save_service.dart';
export 'keychain_store.dart';
export 'system_share_service.dart';
