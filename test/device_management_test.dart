import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rc_car_app/app_state.dart';
import 'package:rc_car_app/protocol/rc_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  late RawDatagramSocket sender;
  const id = '8CAAB5ABCDEF';

  Future<void> discover(String ip) async {
    final arrived = Completer<void>();
    void changed() {
      if (state.discoveredCars.any(
            (car) => car.deviceId == id && car.ip == ip,
          ) &&
          !arrived.isCompleted) {
        arrived.complete();
      }
    }

    state.addListener(changed);
    try {
      sender.send(
        utf8.encode('RC-DISCOVER $id $ip'),
        InternetAddress.loopbackIPv4,
        AppState.discoveryPort,
      );
      await arrived.future.timeout(const Duration(seconds: 2));
    } finally {
      state.removeListener(changed);
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'device_aliases_v1': jsonEncode({id: 'rccar'}),
      'provisioning_completed_v1': true,
    });
    state = AppState();
    await state.startDiscovery();
    sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    sender.close();
    await state.stopDiscovery();
    await state.disconnect();
    state.dispose();
  });

  test('恢复配网进度，广播按 ID 更新 IP 并保留名称', () async {
    expect(state.provisioningCompleted, true);
    await discover('127.0.0.2');
    await discover('127.0.0.1');
    expect(state.discoveredCars, hasLength(1));
    expect(state.discoveredCars.single.ip, '127.0.0.1');
    expect(state.discoveredCars.single.alias, 'rccar');
  });

  test('删除使用最新 IP 发送 STOP 和 clearWifi，随后清理本机记录', () async {
    final received = <int>[];
    final done = Completer<void>();
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 3333);
    final clients = <Socket>[];
    final subscription = server.listen((client) {
      clients.add(client);
      client.listen((data) {
        received.addAll(data);
        if (received.length >= 14 && !done.isCompleted) done.complete();
      });
    });
    try {
      await discover('127.0.0.2');
      await discover('127.0.0.1');
      await state.deleteCar(id);
      await done.future.timeout(const Duration(seconds: 2));
      expect(received, [
        ...commandFrame(RcCommandId.stop),
        ...commandFrame(RcCommandId.clearWifi),
      ]);
      expect(state.discoveredCars, isEmpty);
      expect(state.provisioningCompleted, false);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('device_aliases_v1')!), isEmpty);
      expect(prefs.getBool('provisioning_completed_v1'), false);
      sender.send(
        utf8.encode('RC-DISCOVER $id 127.0.0.1'),
        InternetAddress.loopbackIPv4,
        AppState.discoveryPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(state.discoveredCars, isEmpty);
      await state.completeProvisioning();
      await discover('127.0.0.1');
      expect(state.discoveredCars.single.alias, isNull);
    } finally {
      for (final client in clients) {
        client.destroy();
      }
      await subscription.cancel();
      await server.close();
    }
  });

  test('车辆无法连接时保留别名、配网进度和列表', () async {
    await discover('127.0.0.1');
    await expectLater(state.deleteCar(id), throwsA(isA<SocketException>()));
    expect(state.discoveredCars.single.alias, 'rccar');
    expect(state.provisioningCompleted, true);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('device_aliases_v1')!)[id], 'rccar');
  });
}
