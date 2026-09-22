// 备份用例的 Provider 装配（T046）。
//
// 与 T044 的同步 Provider 同一做法：默认实现**抛错**（漏接线立刻暴露），组合根把
// infrastructure 的实现接上来。默认抛错而不是给一个空实现，是因为一个「什么都不做的
// 假备份服务」会让用户以为导出成功了，而磁盘上什么都没有。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backup_use_case.dart';

/// 恢复目标目录的规划器：给定一个标识，返回**一个新的数据目录**路径。
///
/// 为什么由组合根提供而不是用例自己拼：目录布局（数据目录叫什么、恢复目录与它并列放在哪）
/// 是**平台侧的事实**，只有组合根知道；而 features 不得 import 平台层。规划器返回的路径
/// 必须是一个当前不存在的目录（恢复目标只接受空目录或新目录）。
///
/// 默认**抛错**：一个「返回空串」的默认实现会让恢复写到当前工作目录，而那可能正是运行时
/// 数据目录——「失败不动原库」会因此被静默破坏。
final Provider<String Function(String token)> backupNewDirectoryProvider =
    Provider<String Function(String token)>(
      (Ref ref) => throw StateError(
        'backupNewDirectoryProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 备份导出与恢复用例（组合根提供实现）。
final Provider<BackupUseCase> backupUseCaseProvider = Provider<BackupUseCase>(
  (Ref ref) => throw StateError(
    'backupUseCaseProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
  ),
);
