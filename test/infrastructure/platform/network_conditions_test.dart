// 网络状况探测测试（T016）。
//
// 本文件断言的是**如实回答**这件事，而不是「探测到了什么」：
//   - 桌面没有计费网络 API，因此 isMetered 必须是 false（= 没有证据表明受限），
//     而不是 true（会把 SET-013 在桌面上变成「默认禁止刷新」，用户完全无法理解）；
//   - isOffline 的判定只依据本地网络接口，不做任何联网探测（探测本身不能产生流量，
//     也不能因为目标站点故障就报「离线」）；
//   - 探测失败时不拦（返回 false），理由是宁可多一次会失败留痕的请求，也不要因为
//     探测不到就把刷新永久停住。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/platform/network_conditions.dart';

void main() {
  group('桌面网络探测', () {
    const DesktopNetworkConditions conditions = DesktopNetworkConditions();

    test('桌面不判定计费网络（如实返回 false，不假装遵守 SET-013）', () async {
      // 这条断言的意图很具体：macOS 没有公开的计费网络 API。若这里返回 true，
      // SET-013 的默认值（关）会让桌面上的自动刷新被静默停住。
      expect(await conditions.isMetered(), isFalse);
    });

    test('isOffline 永不抛异常（权限/平台限制时回答「不确定」）', () async {
      // 只断言不抛与类型：真实网络状态取决于跑测试的机器，把这个值写死会让测试
      // 在离线机器上失败、在联网机器上通过——那种断言验证的是环境而不是代码。
      final bool offline = await conditions.isOffline();
      expect(offline, isA<bool>());
    });

    test('放行实现（默认端口）不拦任何刷新', () async {
      const PermissiveNetworkConditions permissive =
          PermissiveNetworkConditions();
      expect(await permissive.isMetered(), isFalse);
      expect(await permissive.isOffline(), isFalse);
    });
  });
}
