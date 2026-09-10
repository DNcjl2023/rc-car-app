import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'car/car_controller.dart';
import 'protocol/rc_protocol.dart';
import 'transport/car_transport.dart';
import 'transport/mock_transport.dart';
import 'transport/wifi_transport.dart';
import 'models/user.dart';
import 'models/discovered_car.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'services/auth_service.dart';

/// App 阶段
enum AppPhase { idle, connecting, connected, error }

/// 全局状态：连接、电量、设置（M1 全部走模拟外设）
class AppState extends ChangeNotifier {
  bool simulateMode = false; // 默认进入真实 WiFi/AP 配网流程；模拟模式仅供开发使用
  bool autoReconnect = true;
  String? carHost; // 车 IP（视频流地址用）
  User? user; // 当前登录用户
  int billingCountdown = 0; // 剩余控制秒数倒计时显示（0=未计时）

  AppPhase phase = AppPhase.idle;
  String? errorMessage;
  String deviceName = '';
  int batteryPercent = -1;
  int voltageMv = -1;

  CarTransport? _transport;
  CarController? _controller;
  StreamSubscription<List<int>>? _frameSub;
  StreamSubscription<bool>? _connSub;
  RawDatagramSocket? _discoverySocket;
  final Map<String, DiscoveredCar> _discoveredCars = {};
  final Map<String, String> _deviceAliases = {};
  bool _discoveryStarted = false;
  bool provisioningCompleted = false;
  final Set<String> _deletedDeviceIds = {};
  static const String _kProvisioningCompleted = 'provisioning_completed_v1';

  static const int discoveryPort = 8889;
  static const String _kDeviceAliases = 'device_aliases_v1';

  CarController? get controller => _controller;
  CarTransport? get transport => _transport;
  bool get isConnected => phase == AppPhase.connected;
  List<DiscoveredCar> get discoveredCars =>
      _discoveredCars.values.toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));

  Future<void> startDiscovery() async {
    if (_discoveryStarted) return;
    _discoveryStarted = true;
    try {
      await _loadDeviceAliases();
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _discoverySocket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        _handleDiscovery(datagram);
      });
    } catch (e) {
      _discoveryStarted = false;
      errorMessage = '无法监听小车发现广播：$e';
      notifyListeners();
    }
  }

  Future<void> stopDiscovery() async {
    _discoverySocket?.close();
    _discoverySocket = null;
    _discoveryStarted = false;
  }

  void _handleDiscovery(Datagram datagram) {
    final message = utf8.decode(datagram.data, allowMalformed: true).trim();
    final match = RegExp(
      r'^RC-DISCOVER ([0-9A-F]{12}) ((?:[0-9]{1,3}\.){3}[0-9]{1,3})$',
    ).firstMatch(message);
    if (match == null) return;
    final deviceId = match.group(1)!;
    if (_deletedDeviceIds.contains(deviceId)) return;
    final ip = match.group(2)!;
    if (ip.split('.').any((part) => int.parse(part) > 255)) return;
    final old = _discoveredCars[deviceId];
    _discoveredCars[deviceId] = DiscoveredCar(
      deviceId: deviceId,
      ip: ip,
      lastSeen: DateTime.now(),
      alias: _deviceAliases[deviceId] ?? old?.alias,
    );
    notifyListeners();
  }

  Future<void> setDeviceAlias(String deviceId, String alias) async {
    final normalized = alias.trim();
    if (normalized.isEmpty) {
      _deviceAliases.remove(deviceId);
    } else {
      _deviceAliases[deviceId] = normalized;
    }
    final car = _discoveredCars[deviceId];
    if (car != null) {
      _discoveredCars[deviceId] = car.copyWith(alias: _deviceAliases[deviceId]);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceAliases, jsonEncode(_deviceAliases));
    notifyListeners();
  }

  Future<void> _loadDeviceAliases() async {
    final prefs = await SharedPreferences.getInstance();
    provisioningCompleted = prefs.getBool(_kProvisioningCompleted) ?? false;
    notifyListeners();
    final raw = prefs.getString(_kDeviceAliases);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _deviceAliases
        ..clear()
        ..addAll(decoded.map((key, value) => MapEntry(key, value.toString())));
    } catch (_) {
      // Ignore malformed old local data.
    }
  }

  Future<void> completeProvisioning() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_kProvisioningCompleted, true)) {
      throw StateError('无法保存配网进度');
    }
    provisioningCompleted = true;
    _deletedDeviceIds.clear();
    notifyListeners();
  }

  /// 固件没有 ACK：这里只确认 TCP 写入，不宣称设备已执行清除。
  /// 发送失败时保留本机记录；只在用户二次确认后调用。
  Future<void> deleteCar(String deviceId) async {
    final car = _discoveredCars[deviceId];
    if (car == null) throw StateError('未发现该小车');
    if (DateTime.now().difference(car.lastSeen) > const Duration(seconds: 30)) {
      throw StateError('车辆发现信息已过期，请等待新的广播后重试');
    }
    if (carHost == car.ip) await disconnect();
    Socket? socket;
    try {
      socket = await Socket.connect(
        car.ip,
        3333,
        timeout: const Duration(seconds: 5),
      );
      socket.add(commandFrame(RcCommandId.stop));
      socket.add(commandFrame(RcCommandId.clearWifi));
      await socket.flush().timeout(const Duration(seconds: 5));
      // 保持连接给固件控制循环处理帧；这不是设备执行成功的回执。
      await Future<void>.delayed(const Duration(seconds: 1));
      await socket.close().timeout(const Duration(seconds: 5));
    } finally {
      socket?.destroy();
    }
    final aliases = Map<String, String>.from(_deviceAliases)..remove(deviceId);
    final hasOtherCars =
        aliases.isNotEmpty || _discoveredCars.keys.any((id) => id != deviceId);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_kDeviceAliases, jsonEncode(aliases))) {
      throw StateError('无法删除本机记录');
    }
    if (!hasOtherCars && !await prefs.setBool(_kProvisioningCompleted, false)) {
      throw StateError('无法清除本机配网进度');
    }
    _deviceAliases.remove(deviceId);
    _deletedDeviceIds.add(deviceId);
    _discoveredCars.remove(deviceId);
    if (!hasOtherCars) provisioningCompleted = false;
    notifyListeners();
  }

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
            if (autoReconnect &&
                carHost == host &&
                phase != AppPhase.connected) {
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

  bool get isLoggedIn => user != null;

  /// 登录（成功后可选连接页面自动进入）
  Future<String?> login(String username, String password) async {
    final u = await authService.login(username.trim(), password);
    if (u == null) return '用户名或密码错误';
    user = u;
    notifyListeners();
    return null;
  }

  /// 注册
  Future<String?> register(
    String username,
    String password,
    String email,
  ) async {
    final err = await authService.register(
      username.trim(),
      password,
      email.trim(),
    );
    if (err == null) {
      // 注册成功后自动登录
      return login(username.trim(), password);
    }
    return err;
  }

  Future<void> logout() async {
    await authService.logout();
    user = null;
    billingCountdown = 0;
    notifyListeners();
  }

  /// 恢复会话（启动时）
  Future<void> restoreSession() async {
    user = await authService.restoreSession();
    notifyListeners();
  }

  /// 充值到账（秒）
  void addCredits(int seconds) {
    final u = user;
    if (u == null || u.unlimited) return;
    user = u.copyWith(credits: u.credits + seconds);
    notifyListeners();
  }

  /// 计费扣秒（控制页每秒调用；admin 无限；余额耗尽返回 false 需断开）
  bool tickBilling() {
    final u = user;
    if (u == null || u.unlimited) {
      billingCountdown = 0;
      return true;
    }
    if (u.credits <= 0) return false;
    user = u.copyWith(credits: u.credits - 1);
    billingCountdown = u.credits - 1;
    notifyListeners();
    return true;
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
  Future<void> connectWifi(String host, {int port = 3333, String? name}) async {
    await disconnect();

    carHost = host;
    final t = WifiTransport(
      host: host,
      port: port,
      name: name ?? 'RC-CAR ($host)',
    );
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
            if (autoReconnect &&
                carHost == host &&
                phase != AppPhase.connected) {
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
    final frame = buildProvisionFrame(ssid, pass);
    Socket? socket;
    try {
      // 配网时不保留旧控制连接，避免自动重连与 AP 连接争用。
      await disconnect();
      socket = await Socket.connect(
        host,
        3333,
        timeout: const Duration(seconds: 5),
      );
      socket.add(frame);
      await socket.flush().timeout(const Duration(seconds: 5));
      // 保持连接给固件控制循环处理帧；这不是设备执行成功的回执。
      await Future<void>.delayed(const Duration(seconds: 1));
      await socket.close().timeout(const Duration(seconds: 5));
      errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = '配网失败：$e';
      notifyListeners();
      return false;
    } finally {
      socket?.destroy();
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
