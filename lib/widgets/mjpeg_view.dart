import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// MJPEG 视频流显示组件（解析 HTTP multipart/x-mixed-replace 流）
/// 用法：MjpegView(url: 'http://<车IP>:81/stream')
class MjpegView extends StatefulWidget {
  final String url;
  final BoxFit fit;
  const MjpegView({super.key, required this.url, this.fit = BoxFit.contain});

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  Uint8List? _frame;
  bool _failed = false;
  int _frameCount = 0;
  int _lastDisplayMs = 0;
  HttpClient? _client;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _disposed = true;
    _client?.close(force: true);
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      _client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await _client!.getUrl(Uri.parse(widget.url));
      final res = await req.close();
      debugPrint('[mjpeg] connected, status=${res.statusCode}');
      await _parse(res);
    } catch (e) {
      debugPrint('[mjpeg] connect error: $e');
      if (!_disposed && mounted) {
        setState(() => _failed = true);
      }
    }
  }

  /// 解析 MJPEG multipart 流：--frame 分隔，帧头含 Content-Length
  Future<void> _parse(HttpClientResponse res) async {
    final buffer = BytesBuilder();
    final frameMarker = utf8.encode('--frame');
    final headerEndMarker = utf8.encode('\r\n\r\n');

    await for (final chunk in res) {
      if (_disposed) break;
      buffer.add(chunk);
      _extract(buffer, frameMarker, headerEndMarker);
    }
  }

  void _extract(BytesBuilder buffer, List<int> frameMarker, List<int> headerEndMarker) {
    var bytes = buffer.toBytes();
    while (true) {
      // 找帧边界 --frame
      final idx = _indexOf(bytes, frameMarker);
      if (idx < 0) {
        _keepTail(buffer, bytes, 0);
        return;
      }
      // 找帧头结束 \r\n\r\n
      final headerEnd = _indexOf(bytes, headerEndMarker, idx);
      if (headerEnd < 0) {
        _keepTail(buffer, bytes, idx);
        return;
      }
      // 解析 Content-Length
      final header = utf8.decode(bytes.sublist(idx, headerEnd), allowMalformed: true);
      final m = RegExp(r'Content-Length:\s*(\d+)').firstMatch(header);
      if (m == null) {
        bytes = bytes.sublist(headerEnd + 4);
        continue;
      }
      final len = int.parse(m.group(1)!);
      final jpegStart = headerEnd + 4;
      if (bytes.length < jpegStart + len) {
        _keepTail(buffer, bytes, idx);
        return;
      }
      final frame = bytes.sublist(jpegStart, jpegStart + len);
      _frameCount++;
      if (_frameCount % 30 == 1) debugPrint('[mjpeg] frame #$_frameCount len=$len');
      // 显示节流：接收所有帧（避免 TCP 背压拖慢固件），但只每 45ms 更新一次画面（~22fps 稳定）
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastDisplayMs >= 45 && !_disposed && mounted) {
        _lastDisplayMs = nowMs;
        setState(() {
          _frame = frame;
          _failed = false;
        });
      }
      bytes = bytes.sublist(jpegStart + len);
    }
  }

  /// 保留未解析完的尾部字节（从 keepFrom 开始）
  /// 注意：bytes 是 buffer 内部引用，必须先拷贝再 clear，否则数据被清空
  void _keepTail(BytesBuilder buffer, List<int> bytes, int keepFrom) {
    final List<int> tail;
    if (keepFrom < bytes.length) {
      tail = Uint8List.fromList(bytes.sublist(keepFrom));
    } else {
      tail = const [];
    }
    buffer.clear();
    if (tail.isNotEmpty) buffer.add(tail);
  }

  int _indexOf(List<int> haystack, List<int> needle, [int start = 0]) {
    if (needle.isEmpty || haystack.length < needle.length) return -1;
    for (int i = start; i <= haystack.length - needle.length; i++) {
      bool match = true;
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Text('视频流连接失败', style: TextStyle(color: Colors.white54, fontSize: 12)),
      );
    }
    final frame = _frame;
    if (frame == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
        ),
      );
    }
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      alignment: Alignment.center,
      child: Image.memory(
        frame,
        fit: widget.fit,
        gaplessPlayback: true,

        errorBuilder: (_, __, ___) => Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const Text('帧解码失败', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
        ),
      ),
    );
  }
}