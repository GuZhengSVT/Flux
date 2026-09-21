// 刷新间隔的取值解析（T016；SET-020 与 SET-022）。
//
// 为什么单独一个文件而不是把 int.parse 写在调度里：
//   注册表用 EnumSpec 约束 SET-020 的间隔取值（'manual' / '15' / '30' / '60' /
//   '120'），SET-022 的单源覆盖则用 int（0 = 手动）。两处口径不同，而「某个源下次
//   什么时候该刷新」这一条判断被定时触发与界面提示共同使用。把转换收在一处，可以
//   避免「调度认为 30 分钟到期、界面显示 60 分钟」这类只在特定取值下出现的分歧。
//
// 未知取值返回 null（= 不自动刷新）而不是抛异常或猜一个默认值：
//   这一列是**设置**，用户可能在旧版本里存过一个已下线的取值（例如 '5'）。让调度
//   崩掉显然不行；悄悄按 60 分钟跑则是「用假象代替状态」——用户看到的是自己没设过
//   的行为。返回 null 表达「这个源不参与定时刷新」，界面上「间隔」会如实显示为
//   手动，用户能自己改回来。
library;

/// 把 SET-020 的间隔设置解析为时长；'manual' 或未知取值返回 null。
Duration? intervalFromSetting(String? setting) {
  if (setting == null || setting.isEmpty || setting == 'manual') {
    return null;
  }
  final int? minutes = int.tryParse(setting);
  if (minutes == null || minutes <= 0) {
    return null;
  }
  return Duration(minutes: minutes);
}

/// 把注册表口径的间隔设置转成界面可读的取值（'manual' 保持原样）。
///
/// 界面的下拉框取值集合来自注册表，因此这里只做「未知值 → manual」的收敛，
/// 不新增取值。
String normalizeIntervalSetting(String? setting) =>
    intervalFromSetting(setting) == null ? 'manual' : setting!;
