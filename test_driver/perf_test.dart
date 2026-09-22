// flutter drive 的宿主侧驱动（T052 性能采集）。
//
// 为什么需要它：integration_test 的用例跑在**真实设备/桌面上**，帧时间要通过
// integrationDriver 的 reportData 回传。这里只自定义两件事——把结果写成便于手册
// 引用的文件名，并把关键数字打到控制台；其余走默认。
//
// 执行：flutter drive --profile --driver=test_driver/perf_test.dart
//         --target=integration_test/t052_perf_test.dart
library;

import 'dart:async';

import 'package:integration_test/integration_test_driver.dart';

/// 打印一份便于采集时直接读取的摘要。
void printSummary(Map<String, dynamic> data) {
  final Object? mode = data['mode'];
  final Object? firstFrame = data['firstFrameMs'];
  final Object? steady = data['steadyScroll'];
  final Object? batch = data['batchLoadFrames'];
  // ignore: avoid_print
  print('T052_PERF mode=$mode firstFrameMs=$firstFrame');
  // ignore: avoid_print
  print('T052_PERF steadyScroll=$steady');
  // ignore: avoid_print
  print('T052_PERF batchLoadFrames=$batch');
}

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (Map<String, dynamic>? data) async {
      if (data != null) {
        printSummary(data);
      }
      await writeResponseData(data, testOutputFilename: 't052_perf_frames');
    },
  );
}
