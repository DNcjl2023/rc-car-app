import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../widgets/joystick.dart';
import '../widgets/mjpeg_view.dart';
import 'settings_page.dart';

/// 控制页（横屏）：全屏视频 + 透明悬浮控件（游戏化界面）
class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _setJoystick(double steering, double throttle) {
    appState.controller?.setJoystick(steering, throttle);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: appState,
        builder: (context, _) {
          final st = appState;
          return Stack(
            children: [
              // 全屏视频背景
              Positioned.fill(child: _buildVideoBackground(st)),
              // 顶部状态栏（半透明悬浮）
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: _buildStatusBar(context, st),
                ),
              ),
              // 底部摇杆区（透明悬浮控件）
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: _buildControls(st),
                ),
              ),
              // 直播切换按钮（右下角悬浮）
              Positioned(
                right: 16,
                bottom: 140,
                child: _buildLiveButton(st),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 全屏视频：直播中显示占位；未连接摄像头显示提示
  Widget _buildVideoBackground(AppState st) {
    if (st.liveMode) {
      return const _VideoPlaceholder(
        icon: Icons.live_tv,
        title: '直播中 · 画面已移交抖音',
        subtitle: '全屏画面由抖音接管',
        color: Colors.redAccent,
      );
    }
    if (st.carHost != null && !st.simulateMode) {
      return MjpegView(url: 'http://${st.carHost}:81/stream', fit: BoxFit.cover);
    }
    return const _VideoPlaceholder(
      icon: Icons.videocam_off,
      title: '摄像头画面',
      subtitle: '连接 WiFi 后显示实时画面',
      color: Colors.blueGrey,
    );
  }
  /// 底部摇杆区：转向 | STOP | 油门（透明悬浮）
  Widget _buildControls(AppState st) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Joystick(
                label: 'L',
                size: 150,
                onChanged: (o) => _setJoystick(0, o.dy),
                child: const Icon(Icons.arrow_upward, color: Colors.white70, size: 24),
              ),
            ),
          ),
          Expanded(child: Center(child: _buildStopButton())),
          Expanded(
            child: Center(
              child: Joystick(
                label: 'R',
                size: 150,
                onChanged: (o) => _setJoystick(o.dx, 0),
                child: const Icon(Icons.sync_alt, color: Colors.white70, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部状态栏：半透明悬浮
  Widget _buildStatusBar(BuildContext context, AppState st) {
    final limit = st.controller?.speedLimitPercent ?? 80;
    final isWifi = !st.simulateMode;
    return Container(
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(isWifi ? Icons.wifi : Icons.science, size: 15, color: Colors.lightBlueAccent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              st.deviceName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('限速 $limit%', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(width: 10),
          _BatteryIndicator(percent: st.batteryPercent),
          const SizedBox(width: 6),
          IconButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
            icon: const Icon(Icons.settings, size: 17, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          // 重连模式切换：自动（断开自动重连）/ 手动（点重连按钮）
          GestureDetector(
            onTap: () => appState.setAutoReconnect(!st.autoReconnect),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: (st.autoReconnect ? Colors.cyan : Colors.orange).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                st.autoReconnect ? '自动' : '手动',
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ),
          IconButton(
            onPressed: () async {
              // 重新连接：断开后重连同 IP（手动模式用）
              final host = appState.carHost;
              if (host == null) return;
              await appState.disconnect();
              await appState.connectWifi(host);
            },
            icon: const Icon(Icons.refresh, size: 17, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            onPressed: () async {
              await appState.disconnect();
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.link_off, size: 17, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  /// 直播切换按钮：透明悬浮
  Widget _buildLiveButton(AppState st) {
    return GestureDetector(
      onTap: () => appState.setLiveMode(!st.liveMode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (st.liveMode ? Colors.red : Colors.black).withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white30),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(st.liveMode ? Icons.videocam : Icons.videocam_outlined, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(st.liveMode ? '退出直播' : '直播', style: const TextStyle(fontSize: 12, color: Colors.white)),
        ]),
      ),
    );
  }

  Widget _buildStopButton() {
    final stopped = appState.controller?.isStopPressed ?? false;
    return GestureDetector(
      onTap: () {
        appState.controller?.toggleStop();
        appState.controlChanged();
      },
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (stopped ? Colors.red : Colors.red.withValues(alpha: 0.45)),
          border: Border.all(color: Colors.red.shade400, width: 3),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stop, color: Colors.white, size: 40),
            Text(stopped ? '急停中' : 'STOP', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 2)),
          ],
        ),
      ),
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  const _VideoPlaceholder({required this.icon, required this.title, required this.subtitle, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E1116),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ],
      ),
    );
  }
}

class _BatteryIndicator extends StatelessWidget {
  final int percent;
  const _BatteryIndicator({required this.percent});

  @override
  Widget build(BuildContext context) {
    if (percent < 0) {
      return const Row(children: [
        Icon(Icons.battery_unknown, color: Colors.white54, size: 15),
        SizedBox(width: 3),
        Text('--', style: TextStyle(color: Colors.white54, fontSize: 11)),
      ]);
    }
    final color = percent < 20 ? Colors.red : (percent < 50 ? Colors.orange : Colors.green);
    return Row(children: [
      Icon(Icons.battery_full, color: color, size: 15),
      const SizedBox(width: 3),
      Text('$percent%', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
    ]);
  }
}