// 平台 HTTP 客户端工厂（T013）。
//
// 存在的理由是一个实测到的坑：package:http 的 IOClient 默认让 dart:io 的 HttpClient
// **自动解压** gzip/deflate，但响应的 content-encoding 头会保留。抓取层为了限制解压后
// 体积而自己解压，于是对同一个响应解压两次，真实源（reorx.com/feed.xml）直接报
// 「gzip 数据非法（Filter error, bad data）」。
//
// 解决方式：显式建一个 autoUncompress=false 的 HttpClient。这样 body 是**原始压缩
// 字节**，与 content-encoding 头一致，抓取层的「先限长、再解压、解压后再限长」才成立。
//
// 为什么不做成「先看头有没有 gzip，没有就直接用」的补救：那需要在两层猜测谁解压过，
// 而「响应体是否已解压」这件事无法从响应本身可靠判断（头保留、体已解压）。明确关掉
// 自动解压，语义就只有一种。
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 创建一个**不做自动解压**的 HTTP 客户端。
///
/// 其他设置保持 dart:io 的默认值：不关闭证书校验（架构第 8 节明确禁止全局忽略 TLS），
/// 不自行设置代理，不做重定向（重定向由抓取层手动跟随，以便逐跳校验协议）。
http.Client createRawHttpClient() {
  final HttpClient inner = HttpClient()
    // 关键：关闭自动解压，让 body 保持压缩原样。
    ..autoUncompress = false
    // 连接与空闲超时交给抓取层的请求超时统一控制；这里给一个兜底值，避免连接被
    // 无限期保持（长跑应用里泄漏连接的典型来源）。
    ..idleTimeout = const Duration(seconds: 15);
  return IOClient(inner);
}
