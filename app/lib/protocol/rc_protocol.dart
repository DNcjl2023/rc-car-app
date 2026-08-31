// 第 4 轮协议：BLE 通信协议（App <-> ESP32）
// 统一 7 字节帧：[AA][55][Type][D0][D1][D2][CRC8]

/// 帧类型
class RcFrameType {
  static const int control = 0x01; // 摇杆控制（App -> 车）
  static const int config = 0x02;  // 参数配置（App -> 车）
  static const int command = 0x03; // 命令（App -> 车）
  static const int status = 0x11;  // 状态上报（车 -> App）
}

/// 命令 ID（Type=0x03 的 D0）
class RcCommandId {
  static const int stop = 1; // 急停
  static const int resume = 2; // 恢复
  static const int requestBattery = 3; // 请求电量
  static const int handshake = 4; // 握手/设备信息
  static const int standby = 5; // 待机
  static const int clearWifi = 6; // 清除 WiFi 配置（转交前保护隐私）
}

/// 参数 ID（Type=0x02 的 D0）
class RcParamId {
  static const int speedLimit = 1; // 限速百分比 0-100
  static const int steeringCurve = 2; // 转向灵敏度 0-254
  static const int deadzone = 3; // 摇杆死区 0-254
  static const int servoTrim = 4; // 舵机中位微调 0-254（127=不偏）
}

/// 摇杆帧标志位（Type=0x01 的 D2）
class RcFlags {
  static const int sourceAuto = 0x01; // 指令源：0=手动 1=自动/TikTok
  static const int stop = 0x02; // 急停
}

/// 解析后的帧
class RcFrame {
  final int type;
  final int d0;
  final int d1;
  final int d2;

  const RcFrame({
    required this.type,
    required this.d0,
    required this.d1,
    required this.d2,
  });
}

/// CRC8：多项式 0x07，初值 0x00（CRC-8/SMBUS 风格）
int crc8(List<int> data) {
  var crc = 0;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      if ((crc & 0x80) != 0) {
        crc = ((crc << 1) ^ 0x07) & 0xFF;
      } else {
        crc = (crc << 1) & 0xFF;
      }
    }
  }
  return crc;
}

/// 构建 7 字节帧
List<int> buildFrame(int type, int d0, int d1, int d2) {
  final body = [0xAA, 0x55, type & 0xFF, d0 & 0xFF, d1 & 0xFF, d2 & 0xFF];
  return [...body, crc8(body)];
}

/// 解析帧，无效返回 null
RcFrame? parseFrame(List<int> data) {
  if (data.length != 7) return null;
  if (data[0] != 0xAA || data[1] != 0x55) return null;
  if (crc8(data.sublist(0, 6)) != data[6]) return null;
  return RcFrame(type: data[2], d0: data[3], d1: data[4], d2: data[5]);
}

/// 摇杆控制帧：转向/油门 0-254（127=中位/停）
List<int> controlFrame({
  required int steering,
  required int throttle,
  int flags = 0,
}) {
  return buildFrame(RcFrameType.control, steering, throttle, flags);
}

/// 参数配置帧
List<int> configFrame(int paramId, int value) {
  return buildFrame(RcFrameType.config, paramId, value, 0);
}

/// 命令帧
List<int> commandFrame(int commandId) {
  return buildFrame(RcFrameType.command, commandId, 0, 0);
}

/// 状态帧（车 -> App）：电量% / 电压高 8 位 / 电压低 8 位
List<int> statusFrame(int batteryPercent, int voltageMv) {
  return buildFrame(
    RcFrameType.status,
    batteryPercent & 0xFF,
    (voltageMv >> 8) & 0xFF,
    voltageMv & 0xFF,
  );
}

/// 配网帧（Type 0x04，变长）：AA 55 04 [ssid_len][ssid][pass_len][pass][crc]
List<int> buildProvisionFrame(String ssid, String password) {
  final ssidBytes = ssid.codeUnits;
  final passBytes = password.codeUnits;
  final body = <int>[
    0xAA, 0x55, RcFrameType.control + 3, // 0x04
    ssidBytes.length,
    ...ssidBytes,
    passBytes.length,
    ...passBytes,
  ];
  body.add(crc8(body));
  return body;
}