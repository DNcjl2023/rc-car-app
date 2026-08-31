import 'dart:async';

/// 车辆传输层抽象：BLE 真机与模拟外设共用同一接口。
/// M1 用 MockTransport；M2 用 BleTransport（flutter_blue_plus）。
abstract class CarTransport {
  /// 收到的原始帧流（如状态帧 0x11）
  Stream<List<int>> get frames;

  /// 连接状态变化（true=已连接）
  Stream<bool> get connectionState;

  bool get isConnected;
  String get deviceName;

  Future<void> connect();
  Future<void> disconnect();
  void send(List<int> frame);
}