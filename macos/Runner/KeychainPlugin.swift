import Cocoa
import FlutterMacOS
import Security

/// Flux 的 macOS Keychain 通道（T010）。
///
/// 只做一件事：把 Dart 侧的凭据读写映射到 Security.framework 的 SecItem*。
/// 不引入其他插件，也不碰数据库或文件——架构第 8 节要求凭据只在安全存储里。
///
/// 关键取值：
///   - kSecClassGenericPassword：通用密码条目；
///   - service 固定为包标识，account 由 Dart 侧按「类别:标识」构造；
///   - kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly：
///     `ThisDeviceOnly` 明确不参与 iCloud 钥匙串同步（凭据不同步），
///     `AfterFirstUnlock` 让解锁过一次即可读取（定时总结需要在无人值守时取凭据）。
///
/// 错误码约定（与 Dart 侧 keychain_store.dart 的翻译一致）：
///   - itemNotFound：条目不存在，Dart 侧映射为 isMissing 的 StorageError；
///   - 其他 OSStatus 原样作为 code 返回，便于排查但不含凭据内容。
final class KeychainPlugin {
  /// 通道名，必须与 Dart 侧 fluxKeychainChannelName 一致。
  static let channelName = "io.github.guzhengsvt.flux/keychain"

  /// 通道句柄；注册后由 Flutter 持有。
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: KeychainPlugin.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  /// 把未捕获的 MethodCall 类型转为 FlutterError，避免崩溃。
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // isAvailable 不带参数，必须在解析参数之前处理：否则会被下面的
    // badArguments 分支拒绝，Dart 侧看到 PlatformException 后把能力报成 false，
    // 于是「平台明明支持却说自己不可用」。（T010 真机用例抓到过一次。）
    if call.method == "isAvailable" {
      result(true)
      return
    }

    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "badArguments", message: "expected a map", details: nil))
      return
    }
    guard let service = args["service"] as? String else {
      result(FlutterError(code: "badArguments", message: "missing service", details: nil))
      return
    }

    switch call.method {
    case "read":
      guard let account = args["account"] as? String else {
        result(FlutterError(code: "badArguments", message: "missing account", details: nil))
        return
      }
      read(service: service, account: account, result: result)
    case "write":
      guard let account = args["account"] as? String,
            let value = args["value"] as? String else {
        result(FlutterError(code: "badArguments", message: "missing account or value", details: nil))
        return
      }
      write(service: service, account: account, value: value, result: result)
    case "delete":
      guard let account = args["account"] as? String else {
        result(FlutterError(code: "badArguments", message: "missing account", details: nil))
        return
      }
      delete(service: service, account: account, result: result)
    case "exists":
      guard let account = args["account"] as? String else {
        result(FlutterError(code: "badArguments", message: "missing account", details: nil))
        return
      }
      exists(service: service, account: account, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 查询条目的基础条件：class + service + account。
  private func baseQuery(service: String, account: String) -> [String: Any] {
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  /// 读取凭据；条目不存在时以 itemNotFound 错误码返回。
  private func read(service: String, account: String, result: @escaping FlutterResult) {
    var query = baseQuery(service: service, account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data,
            let value = String(data: data, encoding: .utf8) else {
        result(FlutterError(code: "decodeFailed", message: "stored value is not UTF-8 text", details: nil))
        return
      }
      result(value)
    case errSecItemNotFound:
      result(FlutterError(code: "itemNotFound", message: "no matching keychain item", details: nil))
    default:
      result(FlutterError(code: "osstatus\(status)", message: "SecItemCopyMatching failed", details: nil))
    }
  }

  /// 写入凭据：先尝试更新，不存在时新增（避免重复条目与 errSecDuplicateItem）。
  private func write(service: String, account: String, value: String, result: @escaping FlutterResult) {
    guard let data = value.data(using: .utf8) else {
      result(FlutterError(code: "encodeFailed", message: "value is not encodable", details: nil))
      return
    }

    let query = baseQuery(service: service, account: account)
    let attributes: [String: Any] = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess {
      result(nil)
      return
    }
    if updateStatus != errSecItemNotFound {
      result(FlutterError(code: "osstatus\(updateStatus)", message: "SecItemUpdate failed", details: nil))
      return
    }

    var insert = query
    insert[kSecValueData as String] = data
    // ThisDeviceOnly：不进入 iCloud 钥匙串同步。
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(insert as CFDictionary, nil)
    if addStatus == errSecSuccess {
      result(nil)
    } else {
      result(FlutterError(code: "osstatus\(addStatus)", message: "SecItemAdd failed", details: nil))
    }
  }

  /// 删除凭据；条目不存在也视为成功（幂等）。
  private func delete(service: String, account: String, result: @escaping FlutterResult) {
    let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    if status == errSecSuccess || status == errSecItemNotFound {
      result(nil)
    } else {
      result(FlutterError(code: "osstatus\(status)", message: "SecItemDelete failed", details: nil))
    }
  }

  /// 判断条目是否存在（不取出值，减少敏感数据在内存中的暴露）。
  private func exists(service: String, account: String, result: @escaping FlutterResult) {
    var query = baseQuery(service: service, account: account)
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    switch status {
    case errSecSuccess:
      result(true)
    case errSecItemNotFound:
      result(false)
    default:
      result(FlutterError(code: "osstatus\(status)", message: "SecItemCopyMatching failed", details: nil))
    }
  }
}
