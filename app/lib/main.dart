import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'pages/connect_page.dart';
import 'pages/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 恢复登录会话（admin/1990 测试账号或本地注册用户）
  await appState.restoreSession();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const RcCarApp());
}

class RcCarApp extends StatelessWidget {
  const RcCarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RC Car',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0E1116),
      ),
      routes: {
        '/connect': (_) => const ConnectPage(),
      },
      home: AnimatedBuilder(
        animation: appState,
        builder: (context, _) => appState.isLoggedIn ? const ConnectPage() : const LoginPage(),
      ),
    );
  }
}
