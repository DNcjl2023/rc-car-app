import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rc_car_app/car/car_controller.dart';
import 'package:rc_car_app/protocol/rc_protocol.dart';
import 'package:rc_car_app/transport/mock_transport.dart';

void main() {
  test('限速 60% 时满油门不超过 203（127+76）', () {
    fakeAsync((async) {
      final t = MockTransport(name: 'T');
      final c = CarController(t);
      t.connect();
      async.elapse(const Duration(milliseconds: 700)); // 连接完成（600ms）

      c.setJoystick(0, 1.0); // 满油门前进
      async.elapse(const Duration(milliseconds: 80)); // 2 个 40ms tick

      final controlLogs = t.log.where((l) => l.startsWith('control')).toList();
      expect(controlLogs, isNotEmpty);
      final last = controlLogs.last;
      final throttle = int.parse(RegExp(r'T=(\d+)').firstMatch(last)!.group(1)!);
      expect(throttle, lessThanOrEqualTo(203));
      expect(throttle, greaterThan(127));

      c.dispose();
      t.dispose();
    });
  });

  test('摇杆回中后发送中位帧且停止重复发送', () {
    fakeAsync((async) {
      final t = MockTransport(name: 'T');
      final c = CarController(t);
      t.connect();
      async.elapse(const Duration(milliseconds: 700));

      c.setJoystick(0, 1.0);
      async.elapse(const Duration(milliseconds: 80));
      final before = t.log.where((l) => l.startsWith('control')).length;

      c.setJoystick(0, 0.0); // 回中
      async.elapse(const Duration(milliseconds: 80));
      final after = t.log.where((l) => l.startsWith('control')).length;
      expect(after, greaterThan(before)); // 回中发了一次

      final idle = after; // 静止
      async.elapse(const Duration(milliseconds: 200)); // 5 个 tick
      expect(t.log.where((l) => l.startsWith('control')).length, idle); // 不再发送

      c.dispose();
      t.dispose();
    });
  });

  test('急停立即发送 STOP 命令帧', () {
    fakeAsync((async) {
      final t = MockTransport(name: 'T');
      final c = CarController(t);
      t.connect();
      async.elapse(const Duration(milliseconds: 700));

      c.setStop(true);
      expect(t.log.any((l) => l == 'command id=1'), isTrue);

      c.setStop(false);
      expect(t.log.any((l) => l == 'command id=2'), isTrue);

      c.dispose();
      t.dispose();
    });
  });

  test('模拟外设连接后上报电量状态帧', () {
    fakeAsync((async) {
      final t = MockTransport(name: 'T');
      List<int>? received;
      t.frames.listen((f) => received = f);
      t.connect();
      async.elapse(const Duration(milliseconds: 700));
      expect(t.isConnected, isTrue);
      expect(received, isNotNull);
      final parsed = parseFrame(received!);
      expect(parsed!.type, RcFrameType.status);
      expect(parsed.d0, 87); // 初始电量
      t.dispose();
    });
  });
}