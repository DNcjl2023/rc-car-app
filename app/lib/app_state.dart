import 'dart:async';

import 'package:flutter/foundation.dart';

import 'car/car_controller.dart';
import 'protocol/rc_protocol.dart';
import 'transport/car_transport.dart';
import 'transport/mock_transport.dart';
import 'transport/wifi_transport.dart';

/// App 阶段
enum AppPhase { idle, connecting, connected, error }

/// 全局状态：连接、电量、设置（M1 全部走模拟外设）
class AppState extends ChangeNotifier {
  bool simulateMode = true; // 模拟模式开关（开发用）
  bool autoReconnect = true;
  bool liveMode = false; // 直播模式：视频画面移交抖音，本框隐藏
  String? carHost; // 车 IP（视频流地址用）

  AppPhase phase = AppPhase.idle;
  String? errorMessage;
  String deviceName = '';
  int batteryPercent = -1;
  int voltageMv = -1;

  CarTransport? _transport;
  CarController? _controller;
  StreamSubscription<List<int>>? _frameSub;
  StreamSubscription<bool>? _connSub;

  CarController? get controller => _controller;
  CarTransport? get transport => _transport;
  bool get isConnected => phase == AppPhase.connected;

  /// 连接模拟设备（M1）。M2 时替换为真实 BLE 扫描/连接。
  Future<void> connectMock({String name = 'RC-CAR-MOCK1'}) async {
    await disconnect();

    final t = MockTransport(name: name);
    _controller = CarController(t);
    _transport = t;

    phase = AppPhase.connecting;
    errorMessage = null;
    notifyListeners();

    _frameSub = t.frames.listen(_onFrame);
    _connSub = t.connectionState.listen((connected) {
      if (!connected && phase == AppPhase.connected) {
        phase = AppPhase.idle;
        batteryPercent = -1;
        notifyListeners();
        // 自动重连模式：断开后延迟重连（用全新连接，不接收旧信号）
        if (autoReconnect && carHost != null) {
          final host = carHost!;
          Future.delayed(const Duration(seconds: 2), () {
            if (autoReconnect && carHost == host && phase != AppPhase.connected) {
              connectWifi(host);
            }
          });
        }
      }
    });

    await t.connect();

    phase = AppPhase.connected;
    deviceName = t.deviceName;
    notifyListeners();

    // 连接后重发当前设置（协议 4.3）并请求电量
    _controller!.speedLimitPercent = _controller!.speedLimitPercent;
    _controller!.deadzone = _controller!.deadzone;
    _controller!.steeringCurve = _controller!.steeringCurve;
    t.send(commandFrame(RcCommandId.requestBattery));
  }

  void setSimulateMode(bool v) {
    simulateMode = v;
    notifyListeners();
  }

  void setAutoReconnect(bool v) {
    autoReconnect = v;
    notifyListeners();
  }

  /// 控制相关状态变化时刷新 UI（急停按钮状态等）
  void controlChanged() {
    notifyListeners();
  }

  void setLiveMode(bool v) {
    liveMode = v;
    notifyListeners();
  }

  Future<void> disconnect() async {
    carHost = null;
    _frameSub?.cancel();
    _connSub?.cancel();
    _frameSub = null;
    _connSub = null;
    _controller?.dispose();
    _controller = null;
    await _transport?.disconnect();
    _transport = null;
    phase = AppPhase.idle;
    batteryPercent = -1;
    voltageMv = -1;
    notifyListeners();
  }

  /// 通过 WiFi TCP 连接车（STA 局域网 或 AP 热点）
  Future<void> connectWifi(String host, {int port = 3333}) async {
    await disconnect();

    carHost = host;
    final t = WifiTransport(host: host, port: port, name: 'RC-CAR ($host)');
    _controller = CarController(t);
    _transport = t;

    phase = AppPhase.connecting;
    errorMessage = null;
    notifyListeners();

    _frameSub = t.frames.listen(_onFrame);
    _connSub = t.connectionState.listen((connected) {
      if (!connected && phase == AppPhase.connected) {
        phase = AppPhase.idle;
        batteryPercent = -1;
        notifyListeners();
        // 自动重连模式：断开后延迟重连（用全新连接，不接收旧信号）
        if (autoReconnect && carHost != null) {
          final host = carHost!;
          Future.delayed(const Duration(seconds: 2), () {
            if (autoReconnect && carHost == host && phase != AppPhase.connected) {
              connectWifi(host);
            }
          });
        }
      }
    });

    try {
      await t.connect();
    } catch (e) {
      phase = AppPhase.error;
      errorMessage = '无法连接 $host：$e';
      notifyListeners();
      return;
    }

    phase = AppPhase.connected;
    deviceName = t.deviceName;
    // 重连后重置摇杆回中（不发送断开前的残留旧值，防止"旧信号"让车乱动）
    _controller?.setJoystick(0, 0);
    notifyListeners();

    // 连接后重发当前设置并请求电量
    _controller!.speedLimitPercent = _controller!.speedLimitPercent;
    _controller!.deadzone = _controller!.deadzone;
    _controller!.steeringCurve = _controller!.steeringCurve;
    t.send(commandFrame(RcCommandId.requestBattery));
  }

  /// 配网：连接 AP 热点后发送 SSID/密码，芯片保存后自动重启
  Future<bool> provisionWifi(String host, String ssid, String pass) async {
    final t = WifiTransport(host: host, port: 3333, name: 'provision');
    try {
      await t.connect();
      t.send(buildProvisionFrame(ssid, pass));
      await Future.delayed(const Duration(seconds: 1));
      await t.disconnect();
      return true;
    } catch (e) {
      errorMessage = '配网失败：$e';
      notifyListeners();
      return false;
    }
  }
  void _onFrame(List<int> data) {
    final f = parseFrame(data);
    if (f == null) return;
    if (f.type == RcFrameType.status) {
      batteryPercent = f.d0;
      voltageMv = (f.d1 << 8) | f.d2;
      notifyListeners();
    }
  }
}

/// 全局单例
final AppState appState = AppState();
