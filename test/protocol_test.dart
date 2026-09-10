import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rc_car_app/protocol/rc_protocol.dart';

void main() {
  test('配网名称按 UTF-8 字节编码，与固件长度字段一致', () {
    final ssid = utf8.encode('家里WiFi');
    final password = utf8.encode('password123');
    final frame = buildProvisionFrame('家里WiFi', 'password123');
    expect(frame.sublist(0, 4), [0xAA, 0x55, 0x04, ssid.length]);
    expect(frame.sublist(4, 4 + ssid.length), ssid);
    expect(frame[4 + ssid.length], password.length);
    expect(frame.sublist(5 + ssid.length, frame.length - 1), password);
    expect(frame.last, crc8(frame.sublist(0, frame.length - 1)));
  });

  test('构建的帧为 7 字节且带正确帧头', () {
    final frame = controlFrame(steering: 150, throttle: 200);
    expect(frame.length, 7);
    expect(frame[0], 0xAA);
    expect(frame[1], 0x55);
    expect(frame[2], RcFrameType.control);
  });

  test('帧往返解析正确', () {
    final frame = controlFrame(steering: 150, throttle: 200);
    final parsed = parseFrame(frame);
    expect(parsed, isNotNull);
    expect(parsed!.type, RcFrameType.control);
    expect(parsed.d0, 150);
    expect(parsed.d1, 200);
    expect(parsed.d2, 0);
  });

  test('损坏的校验位被拒绝', () {
    final frame = controlFrame(steering: 150, throttle: 200);
    frame[6] = frame[6] ^ 0xFF;
    expect(parseFrame(frame), isNull);
  });

  test('错误的帧头被拒绝', () {
    final frame = controlFrame(steering: 150, throttle: 200);
    frame[0] = 0xBB;
    expect(parseFrame(frame), isNull);
  });

  test('长度不对被拒绝', () {
    final frame = controlFrame(steering: 150, throttle: 200);
    expect(parseFrame(frame.sublist(0, 5)), isNull);
  });

  test('状态帧编解码（电量 87% / 电压 3700mV）', () {
    final frame = statusFrame(87, 3700);
    final parsed = parseFrame(frame)!;
    expect(parsed.type, RcFrameType.status);
    expect(parsed.d0, 87);
    expect((parsed.d1 << 8) | parsed.d2, 3700);
  });

  test('配置帧与命令帧类型正确', () {
    expect(
      parseFrame(configFrame(RcParamId.speedLimit, 60))!.type,
      RcFrameType.config,
    );
    expect(
      parseFrame(commandFrame(RcCommandId.stop))!.type,
      RcFrameType.command,
    );
    expect(parseFrame(commandFrame(RcCommandId.stop))!.d0, RcCommandId.stop);
  });
}
