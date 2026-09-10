import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rc_car_app/app_state.dart';
import 'package:rc_car_app/models/discovered_car.dart';
import 'package:rc_car_app/pages/connect_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestState extends AppState {
  bool sendSucceeds = true;
  bool deleteSucceeds = true;
  int provisions = 0;
  int deletions = 0;
  List<DiscoveredCar> cars = [];

  @override
  Future<void> startDiscovery() async {}

  @override
  List<DiscoveredCar> get discoveredCars => cars;

  @override
  Future<bool> provisionWifi(String host, String ssid, String pass) async {
    expect(host, '192.168.4.1');
    expect(ssid, 'HomeWiFi');
    provisions++;
    return sendSucceeds;
  }

  @override
  Future<void> deleteCar(String deviceId) async {
    deletions++;
    if (!deleteSucceeds) throw StateError('offline');
    cars.removeWhere((car) => car.deviceId == deviceId);
    notifyListeners();
  }
}

void main() {
  late TestState state;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = TestState();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: ConnectPage(state: state)));
    await tester.pumpAndSettle();
  }

  Future<void> fillWifi(WidgetTester tester) async {
    await tester.tap(find.text('我已连接'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'HomeWiFi');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
  }

  testWidgets('首页只显示教程和入口，输入页关闭后返回首页', (tester) async {
    await open(tester);
    expect(find.text('首次使用：先配网'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('连接所选车辆'), findsNothing);
    expect(find.textContaining('RC-CAR-29E0'), findsNothing);
    await tester.tap(find.text('我已连接'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.tap(find.byTooltip('关闭配网'));
    await tester.pumpAndSettle();
    expect(find.text('首次使用：先配网'), findsOneWidget);
    expect(state.provisions, 0);
    expect(state.provisioningCompleted, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('发送后先提醒切回 WiFi，完成后返回首页并提供重新配网', (tester) async {
    await open(tester);
    await fillWifi(tester);
    await tester.tap(find.text('发送配网信息'));
    await tester.pumpAndSettle();
    expect(find.text('切回家庭 Wi‑Fi'), findsOneWidget);
    expect(find.textContaining('HomeWiFi'), findsOneWidget);
    expect(state.provisioningCompleted, false);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('首次使用：先配网'), findsOneWidget);
    expect(find.text('重新配网'), findsOneWidget);
    expect(state.provisioningCompleted, true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('provisioning_completed_v1'), true);
    expect(prefs.getKeys(), {'provisioning_completed_v1'});
    await tester.tap(find.text('重新配网'));
    await tester.pumpAndSettle();
    expect(find.text('重新配网前，请手动重启小车'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('重新配网'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('配网发送失败保留表单，不推进完成状态', (tester) async {
    state.sendSucceeds = false;
    await open(tester);
    await fillWifi(tester);
    await tester.tap(find.text('发送配网信息'));
    await tester.pumpAndSettle();
    expect(find.textContaining('发送失败'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(state.provisioningCompleted, false);
    expect(find.text('完成'), findsNothing);
  });

  testWidgets('空 WiFi 不发送，关闭不会保存输入', (tester) async {
    await open(tester);
    await tester.tap(find.text('我已连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发送配网信息'));
    await tester.pumpAndSettle();
    expect(state.provisions, 0);
    expect(find.textContaining('1–32'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭配网'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已连接'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      '',
    );
  });

  testWidgets('车辆独立页面允许跳过配网，删除需确认且失败保留车辆', (tester) async {
    state.cars = [
      DiscoveredCar(
        deviceId: '8CAAB5ABCDEF',
        ip: '192.168.0.108',
        lastSeen: DateTime.now(),
        alias: 'rccar',
      ),
    ];
    await open(tester);
    expect(find.text('rccar'), findsNothing);
    await tester.tap(find.text('选择车辆'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(find.text('rccar'), findsOneWidget);
    await tester.tap(find.byTooltip('删除小车'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(state.deletions, 0);
    state.deleteSucceeds = false;
    await tester.tap(find.byTooltip('删除小车'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除并清除'));
    await tester.pumpAndSettle();
    expect(find.text('rccar'), findsOneWidget);
    expect(find.textContaining('删除未完成'), findsOneWidget);
    state.deleteSucceeds = true;
    await tester.tap(find.byTooltip('删除小车'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除并清除'));
    await tester.pumpAndSettle();
    expect(find.text('rccar'), findsNothing);
    expect(state.deletions, 2);
    expect(tester.takeException(), isNull);
  });
}
