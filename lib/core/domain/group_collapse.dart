// 分组展开/折叠的本机记忆端口（T014；SET-025）。
//
// 为什么是**本机**状态而不是 SET 注册表里的一个值：
//   - SET-025 的分类是 D（设备专属，架构第 6 节）：展开/折叠描述的是「这台设备上
//     这一屏看到了什么」，同步到另一台设备（屏幕尺寸与关注点都不同）没有意义；
//   - 注册表里 SET-025 只有一个布尔（文档口径的**默认值**：展开），而实际需要记住
//     的是**每个分组**的状态。把一个「groupId → bool」的映射硬塞进 BoolSpec 会让
//     注册表的口径与文档不符，交叉核对测试会立刻发现；
//   - 因此走与本机引导标记同一条路：settings 窄表里 device. 命名空间的键，天然
//     不进入同步投影与备份投影（见 infrastructure/local/device_state_repository.dart）。
//
// 为什么端口在 core 而不是 features：实现住在 infrastructure，而 infrastructure
// **不得**依赖 features（依赖方向为 app/features → core ← infrastructure）。
// 这条与 T013 把 FeedFetcher 放进 core 是同一个理由。
library;

import '../result.dart';

/// 分组折叠状态的本机存储端口。
abstract interface class GroupCollapseStore {
  /// 读取全部已记录的折叠状态：键为分组 id 的字符串形式，true 表示已折叠。
  Future<Result<Map<String, bool>>> readAll();

  /// 写入某个分组的折叠状态。
  Future<Result<void>> write({required int groupId, required bool collapsed});
}

/// 纯内存实现（测试与「本机存储不可用」时使用）。
///
/// 存储失败**不阻塞界面**：折叠是纯展示偏好，读不到时按默认（展开）渲染即可，
/// 只是这次会话的折叠不会被记住。把「记不住折叠」做成错误提示，会让一个无关紧要的
/// 磁盘问题看起来像数据损坏。
final class InMemoryGroupCollapseStore implements GroupCollapseStore {
  /// 构造空的内存折叠状态。
  InMemoryGroupCollapseStore();

  final Map<String, bool> _values = <String, bool>{};

  @override
  Future<Result<Map<String, bool>>> readAll() async =>
      Ok<Map<String, bool>>(Map<String, bool>.of(_values));

  @override
  Future<Result<void>> write({
    required int groupId,
    required bool collapsed,
  }) async {
    _values['$groupId'] = collapsed;
    return okUnit();
  }
}
