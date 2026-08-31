import 'dart:async';
import 'dart:math';

import '../protocol/rc_protocol.dart';
import 'car_transport.dart';

/// 模拟外设：虚拟 RC-CAR 设备，行为与真实 ESP32 一致（协议第 4.7 节）
/// - 连接耗时约 600ms
/// - 连接后立即上报电量，之后每 5 秒一次
/// - 电量从 87% 开始，每 5 秒 -1%，电压按 3.3V~4.2V 映射
class MockTransport implements CarTransport {
  final String name;

  final _frames = StreamController<List<int>>.broadcast();
  final _conn = StreamController<bool>.broadcast();

  bool _connected = false;
  Timer? _statusTimer;
  double _battery = 87;
  int _voltageMv = 3700;

  /// 模拟指令日志（调试用）
  final List<String> log = [];

  MockTransport({this.name = 'RC-CAR-MOCK1'});

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
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _connected = true;
    _conn.add(true);
    _sendStatus();
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _battery = max(0, _battery - 1);
      _voltageMv = 3300 + ((_battery / 100) * 900).round();
      _sendStatus();
    });
  }

  @override
  Future<void> disconnect() async {
    _statusTimer?.cancel();
    _statusTimer = null;
    _connected = false;
    _conn.add(false);
  }

  @override
  void send(List<int> frame) {
    final f = parseFrame(frame);
    if (f == null) return;
    switch (f.type) {
      case RcFrameType.control:
        log.add('control S=${f.d0} T=${f.d1} flags=${f.d2}');
      case RcFrameType.config:
        log.add('config id=${f.d0} val=${f.d1}');
      case RcFrameType.command:
        if (f.d0 == RcCommandId.requestBattery) {
          _sendStatus();
        }
        log.add('command id=${f.d0}');
    }
  }

  void _sendStatus() {
    _frames.add(statusFrame(_battery.round(), _voltageMv));
  }

  void dispose() {
    _statusTimer?.cancel();
    _frames.close();
    _conn.close();
  }
}