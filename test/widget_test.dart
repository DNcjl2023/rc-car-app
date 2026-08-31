import 'package:flutter_test/flutter_test.dart';
import 'package:rc_car_app/main.dart';

void main() {
  testWidgets('App 能正常启动并显示连接页', (WidgetTester tester) async {
    await tester.pumpWidget(const RcCarApp());
    expect(find.text('蓝牙遥控车'), findsOneWidget);
  });
}