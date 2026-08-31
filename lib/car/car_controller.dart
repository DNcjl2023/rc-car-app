import 'dart:async';

import 'package:flutter/foundation.dart';
import 'dart:math';

import '../protocol/rc_protocol.dart';
import '../transport/car_transport.dart';

/// 控制逻辑（协议第 4.4 节）：
/// - 摇杆输入归一化 [-1,1]，映射到 0-254（127=中位/停）
/// - 25Hz 节流发送（Timer 40ms），值不变不发，回中发一次
/// - 限速在映射时强约束；死区在映射后归中
/// - 急停立即发命令帧
class CarController {
  final CarTransport transport;

  final _logs = StreamController<String>.broadcast();

  Timer? _sendTimer;
  int _lastSentSteering = -1;
  int _lastSentThrottle = -1;

  double _steeringNorm = 0;
  double _throttleNorm = 0;
  bool _stopPressed = false;

  // 设置项（默认值：协议 4.9）
  int _speedLimitPercent = 80;
  int _deadzone = 12;
  int _steeringCurve = 128;

  CarController(this.transport) {
    _sendTimer = Timer.periodic(const Duration(milliseconds: 40), (_) => _tick());
  }

  Stream<String> get logs => _logs.stream;

  int get speedLimitPercent => _speedLimitPercent;
  int get deadzone => _deadzone;
  int get steeringCurve => _steeringCurve;

  set speedLimitPercent(int v) {
    _speedLimitPercent = v.clamp(0, 100);
    _sendConfig(RcParamId.speedLimit, _speedLimitPercent);
  }

  set deadzone(int v) {
    _deadzone = v.clamp(0, 254);
    _sendConfig(RcParamId.deadzone, _deadzone);
  }

  set steeringCurve(int v) {
    _steeringCurve = v.clamp(0, 254);
    _sendConfig(RcParamId.steeringCurve, _steeringCurve);
  }

  void _sendConfig(int id, int value) {
    if (transport.isConnected) {
      transport.send(configFrame(id, value));
    }
  }

  /// 摇杆输入：steering/throttle 范围 [-1,1]
  void setJoystick(double steering, double throttle) {
    _steeringNorm = steering.clamp(-1.0, 1.0);
    _throttleNorm = throttle.clamp(-1.0, 1.0);
  }

  bool get isStopPressed => _stopPressed;

  /// 急停锁定/解除（点击切换，避免"点一下松开就恢复"导致无效）
  void toggleStop() {
    _stopPressed = !_stopPressed;
    transport.send(commandFrame(_stopPressed ? RcCommandId.stop : RcCommandId.resume));
    _logs.add(_stopPressed ? 'STOP' : 'RESUME');
    // 解除急停：立即发送当前摇杆值（不阻塞下一个信号，恢复控制）
    if (!_stopPressed) {
      final s = _mapSteering(_steeringNorm);
      final t = _mapThrottle(_throttleNorm);
      _lastSentSteering = s;
      _lastSentThrottle = t;
      transport.send(controlFrame(steering: s, throttle: t));
    }
  }

  /// 急停按下/松开
  void setStop(bool pressed) {
    _stopPressed = pressed;
    if (pressed) {
      transport.send(commandFrame(RcCommandId.stop));
      _logs.add('STOP');
    } else {
      transport.send(commandFrame(RcCommandId.resume));
      _logs.add('RESUME');
    }
  }

  void _tick() {
    if (!transport.isConnected || _stopPressed) return;

    final steering = _mapSteering(_steeringNorm);
    final throttle = _mapThrottle(_throttleNorm);

    // 持续发送：非中位时每 tick 都发（防止固件 300ms 看门狗误停车）；
    // 中位稳定后只发一次（回中）
    final isCenter = steering == 127 && throttle == 127;
    if (isCenter && steering == _lastSentSteering && throttle == _lastSentThrottle) {
      return;
    }

    _lastSentSteering = steering;
    _lastSentThrottle = throttle;
    debugPrint('[send] S=$steering T=$throttle');
    transport.send(controlFrame(steering: steering, throttle: throttle));
    _logs.add('S=$steering T=$throttle');
  }

  int _mapSteering(double norm) {
    var v = norm * 127; // -127..127
    final k = _steeringCurve / 128.0; // 1.0 线性
    if (v != 0) {
      final sign = v < 0 ? -1.0 : 1.0;
      v = pow(v.abs() / 127.0, k).toDouble() * 127 * sign;
    }
    return _applyDeadzone((127 + v).round());
  }

  int _mapThrottle(double norm) {
    // 限速只在固件端生效（协议 4.3：固件强约束，App 发原始油门 0-254）
    final v = norm * 127;
    return _applyDeadzone((127 + v).round());
  }

  int _applyDeadzone(int raw) {
    final dz = _deadzone.clamp(0, 127);
    if ((raw - 127).abs() <= dz) return 127;
    return raw.clamp(0, 254);
  }

  void dispose() {
    _sendTimer?.cancel();
    _logs.close();
  }
}