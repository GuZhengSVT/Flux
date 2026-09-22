// T046：自实现 ZIP 编解码的互操作与失败分支（core/archive/zip_archive.dart）。
//
// 为什么这份编解码需要独立用例：备份包是**唯一**跨进程、跨工具的产物（用户会拿它去恢复，
// 甚至可能用别的解压器打开看一眼）。因此这里验两件事：
//   1) **与外部工具互操作**：Python 的 zipfile 能读出我们写的包（含非 ASCII 名与 DEFLATE），
//      我们也能读它写的包——只对自己读自己写，等于没有验证格式；
//   2) **损坏必须被发现**：截断、篡改载荷、垃圾数据、Zip64 哨兵值一律返回 null
//      （恢复路径据此报「包损坏」并**不动原库**，而不是解开一半再失败）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

void main() {
  test('自写自读：内容、名字（含中文）与顺序都保持', () {
    final Uint8List archive = zipEncode(<ZipEntry>[
      ZipEntry(
        name: 'manifest.json',
        bytes: Uint8List.fromList(utf8.encode('{"formatVersion":1}')),
      ),
      ZipEntry(
        name: 'media/中文-图.bin',
        bytes: Uint8List.fromList(List<int>.generate(5000, (int i) => i % 251)),
      ),
      ZipEntry(
        name: 'flux.sqlite',
        bytes: Uint8List.fromList(<int>[7, 7, 7, 7]),
      ),
    ]);
    final List<ZipDecodedEntry> decoded = zipDecode(archive)!;
    expect(decoded.map((ZipDecodedEntry e) => e.name).toList(), <String>[
      'manifest.json',
      'media/中文-图.bin',
      'flux.sqlite',
    ]);
    expect(utf8.decode(decoded.first.bytes), '{"formatVersion":1}');
    expect(decoded[1].bytes.length, 5000);
    expect(decoded[1].bytes[250], 250 % 251);
    expect(decoded.last.bytes, <int>[7, 7, 7, 7]);
  });

  test('小条目退回 stored（压缩后更大时不硬压）', () {
    final Uint8List archive = zipEncode(<ZipEntry>[
      ZipEntry(name: 'flux.sqlite', bytes: Uint8List.fromList(<int>[1, 2, 3])),
    ]);
    expect(zipDecode(archive)!.single.bytes, <int>[1, 2, 3]);
  });

  test('与 Python zipfile 互操作：它能读出我们写的包（含非 ASCII 名）', () async {
    final Directory dir = Directory.systemTemp.createTempSync(
      'flux-zip-interop',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final String path = '${dir.path}/ours.zip';
    File(path).writeAsBytesSync(
      zipEncode(<ZipEntry>[
        ZipEntry(
          name: 'flux.sqlite',
          bytes: Uint8List.fromList(
            List<int>.generate(3000, (int i) => (i * 7) % 256),
          ),
        ),
        ZipEntry(
          name: 'media/图.bin',
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
        ),
      ]),
    );
    final ProcessResult result = await Process.run('python3', <String>[
      '-c',
      'import zipfile,sys;'
          'z=zipfile.ZipFile(sys.argv[1]);'
          'print(sorted(z.namelist()));'
          'print(len(z.read("flux.sqlite")));'
          'print(list(z.read("media/图.bin")));'
          'print(z.testzip())',
      path,
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final List<String> lines = const LineSplitter().convert(
      result.stdout.toString(),
    );
    expect(lines[0], contains('flux.sqlite'));
    expect(lines[0], contains('media/图.bin'));
    expect(lines[1], '3000');
    expect(lines[2], '[1, 2, 3, 4, 5]');
    expect(lines[3], 'None', reason: '外部工具校验 CRC 通过');
  });

  test('与 Python zipfile 互操作：我们能读它写的包（DEFLATE）', () async {
    final Directory dir = Directory.systemTemp.createTempSync('flux-zip-read');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String path = '${dir.path}/theirs.zip';
    final ProcessResult made = await Process.run('python3', <String>[
      '-c',
      'import zipfile,sys;'
          'z=zipfile.ZipFile(sys.argv[1],"w",zipfile.ZIP_DEFLATED);'
          'z.writestr("flux.sqlite","hello sqlite "*500);'
          'z.writestr("media/x.bin", bytes(range(200)));'
          'z.close()',
      path,
    ]);
    expect(made.exitCode, 0, reason: made.stderr.toString());
    final List<ZipDecodedEntry> decoded = zipDecode(
      File(path).readAsBytesSync(),
    )!;
    expect(decoded.map((ZipDecodedEntry e) => e.name).toList(), <String>[
      'flux.sqlite',
      'media/x.bin',
    ]);
    expect(utf8.decode(decoded.first.bytes), 'hello sqlite ' * 500);
    expect(decoded.last.bytes.length, 200);
  });

  test('失败分支：截断 / 垃圾 / 篡改载荷都返回 null', () {
    final Uint8List archive = zipEncode(<ZipEntry>[
      ZipEntry(
        name: 'flux.sqlite',
        bytes: Uint8List.fromList(List<int>.generate(9000, (int i) => i % 251)),
      ),
    ]);
    expect(
      zipDecode(Uint8List.sublistView(archive, 0, archive.length - 10)),
      isNull,
      reason: '截断（少了结束记录）',
    );
    expect(
      zipDecode(Uint8List.fromList(List<int>.filled(100, 1))),
      isNull,
      reason: '垃圾数据',
    );
    final Uint8List tampered = Uint8List.fromList(archive);
    final int middle = archive.length ~/ 2;
    tampered[middle] = (tampered[middle] + 1) & 0xff;
    expect(zipDecode(tampered), isNull, reason: '篡改载荷（CRC 或 DEFLATE 报错）');
  });

  test('声明 Zip64（0xffff 条目数）时拒绝而不是猜一个偏移', () {
    final Uint8List archive = zipEncode(<ZipEntry>[
      ZipEntry(name: 'flux.sqlite', bytes: Uint8List.fromList(<int>[1, 2, 3])),
    ]);
    int eocd = -1;
    for (int i = archive.length - 22; i >= 0; i--) {
      if (archive[i] == 0x50 &&
          archive[i + 1] == 0x4b &&
          archive[i + 2] == 0x05 &&
          archive[i + 3] == 0x06) {
        eocd = i;
        break;
      }
    }
    expect(eocd, greaterThanOrEqualTo(0));
    final Uint8List patched = Uint8List.fromList(archive);
    patched[eocd + 10] = 0xff;
    patched[eocd + 11] = 0xff;
    expect(zipDecode(patched), isNull);
  });
}
