import 'dart:async';
import 'dart:io';

import 'car_transport.dart';

/// WiFi TCP 传输层（端口 3333，复用第 4 轮 7 字节协议）
/// 与模拟外设 MockTransport 实现同一接口，控制逻辑零改动
class WifiTransport implements CarTransport {
  final String host;
  final int port;
  final String name;

  Socket? _socket;
  StreamSubscription<List<int>>? _sub;
  final _frames = StreamController<List<int>>.broadcast();
  final _conn = StreamController<bool>.broadcast();
  final List<int> _buffer = [];
  bool _connected = false;

  WifiTransport({required this.host, this.port = 3333, this.name = 'RC-CAR'});

  @override
  Stream<List<int>> get frames => _frames.stream;

  @override
  Stream<bool> get connectionState => _conn.stream;

  @override
  bool get isConnected => _connected;

  @override
  String get deviceName => name;

  @override
  Future<void> connect() async {
    await disconnect();
    final socket = await Socket.connect(host, port,
        timeout: const Duration(seconds: 5));
    _socket = socket;
    _connected = true;
    _conn.add(true);
    _sub = socket.listen(
      (data) {
        _buffer.addAll(data);
        _extractFrames();
      },
      onError: (_) => _onDisconnected(),
      onDone: _onDisconnected,
    );
  }

  /// TCP 是字节流，可能粘包/半包：按帧头 AA 55 找 7 字节完整帧
  void _extractFrames() {
    while (_buffer.length >= 2) {
      int start = -1;
      for (int i = 0; i < _buffer.length - 1; i++) {
        if (_buffer[i] == 0xAA && _buffer[i + 1] == 0x55) {
          start = i;
          break;
        }
      }
      if (start < 0) {
        _buffer.clear();
        break;
      }
      if (start > 0) _buffer.removeRange(0, start);
      if (_buffer.length < 7) break;
      final frame = List<int>.from(_buffer.sublist(0, 7));
      _buffer.removeRange(0, 7);
      _frames.add(frame);
    }
  }

  void _onDisconnected() {
    if (!_connected) return;
    _connected = false;
    _socket?.destroy();
    _socket = null;
    _conn.add(false);
  }

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    _socket?.destroy();
    _socket = null;
    if (_connected) {
      _connected = false;
      _conn.add(false);
    }
    _buffer.clear();
  }

  @override
  void send(List<int> frame) {
    _socket?.add(frame);
  }

  /// 发送配网帧（变长，SSID + 密码），配网成功后芯片会重启
  void sendProvision(List<int> frame) {
    _socket?.add(frame);
  }
}