import 'dart:async';

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
  Timer? _billingTimer;
  int _videoEpoch = 0; // 递增以重建 MjpegView，实现"重连视频"

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 付费计时：每秒扣 1 秒；余额耗尽强制断开
    _billingTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onBillingTick());
  }

  void _onBillingTick() {
    if (!appState.tickBilling()) {
      // 余额耗尽
      _billingTimer?.cancel();
      appState.disconnect();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('余额已用完，请充值后继续')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _billingTimer?.cancel();
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
              // 重连视频按钮（右下角悬浮）
              Positioned(
                right: 16,
                bottom: 140,
                child: _buildReconnectVideoButton(),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 全屏视频：未连接摄像头显示提示
  Widget _buildVideoBackground(AppState st) {
    if (st.carHost != null && !st.simulateMode) {
      // ValueKey 递增即可重建并重新连接视频流
      return MjpegView(key: ValueKey('mjpeg-$_videoEpoch'), url: 'http://${st.carHost}:81/stream', fit: BoxFit.cover);
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

  /// 顶部状态栏：纯图标（无底），自动/手动 + 重连按钮加大
  Widget _buildStatusBar(BuildContext context, AppState st) {
    final isWifi = !st.simulateMode;
    final remain = st.billingCountdown;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Icon(isWifi ? Icons.wifi : Icons.science, size: 18, color: Colors.lightBlueAccent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(st.deviceName,
                style: const TextStyle(fontSize: 12, color: Colors.white),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 10),
          Icon(Icons.timer_outlined, size: 16, color: Colors.cyan.shade200),
          const SizedBox(width: 3),
          Text(remain > 0 ? '${remain}s' : '∞',
              style: TextStyle(fontSize: 12, color: Colors.cyan.shade200, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          _BatteryIndicator(percent: st.batteryPercent),
          const SizedBox(width: 8),
          _ModeToggleButton(
            autoReconnect: st.autoReconnect,
            onTap: () => appState.setAutoReconnect(!st.autoReconnect),
          ),
          const SizedBox(width: 6),
          _BigIconButton(
            icon: Icons.refresh,
            tooltip: '重连车辆',
            onTap: () async {
              final host = appState.carHost;
              if (host == null) return;
              await appState.disconnect();
              await appState.connectWifi(host);
            },
          ),
          const SizedBox(width: 6),
          _BigIconButton(
            icon: Icons.settings,
            tooltip: '设置',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
          const SizedBox(width: 6),
          _BigIconButton(
            icon: Icons.link_off,
            tooltip: '断开',
            onTap: () async {
              await appState.disconnect();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  /// 重连视频信号按钮：透明悬浮
  Widget _buildReconnectVideoButton() {
    return GestureDetector(
      onTap: () => setState(() => _videoEpoch++),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white30),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.videocam, size: 15, color: Colors.white),
          SizedBox(width: 5),
          Text('重连视频', style: TextStyle(fontSize: 12, color: Colors.white)),
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
        width: 55,
        height: 55,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (stopped ? Colors.red : Colors.red.withValues(alpha: 0.45)),
          border: Border.all(color: Colors.red.shade400, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stop, color: Colors.white, size: 20),
            Text(stopped ? '急停中' : 'STOP', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 1)),
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

/// 自动/手动重连切换（大按钮）
class _ModeToggleButton extends StatelessWidget {
  final bool autoReconnect;
  final VoidCallback onTap;
  const _ModeToggleButton({required this.autoReconnect, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = autoReconnect ? Colors.cyan : Colors.orange;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(autoReconnect ? Icons.autorenew : Icons.touch_app, size: 18, color: color),
          const SizedBox(width: 5),
          Text(
            autoReconnect ? '自动' : '手动',
            style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ]),
      ),
    );
  }
}

/// 大号图标按钮（状态栏操作）
class _BigIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _BigIconButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 26, color: Colors.white),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        padding: const EdgeInsets.all(10),
        minimumSize: const Size(46, 46),
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