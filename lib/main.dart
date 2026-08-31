import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/connect_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const ConnectPage(),
    );
  }
}