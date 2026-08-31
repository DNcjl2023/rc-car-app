import 'package:flutter/material.dart';

import '../app_state.dart';
import '../protocol/rc_protocol.dart';

/// 设置页：限速 / 转向灵敏度 / 死区（协议 4.3 Type 0x02）
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = appState.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), backgroundColor: const Color(0xFF0E1116)),
      body: AnimatedBuilder(
        animation: appState,
        builder: (context, _) {
          if (controller == null) {
            return const Center(
              child: Text('连接车辆后可调整设置', style: TextStyle(color: Colors.white54)),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SliderTile(
                icon: Icons.speed,
                label: '油门限速',
                value: controller.speedLimitPercent,
                min: 10,
                max: 100,
                divisions: 18,
                format: (v) => '$v%',
                onChanged: (v) => controller.speedLimitPercent = v,
              ),
              _SliderTile(
                icon: Icons.tune,
                label: '转向灵敏度',
                value: controller.steeringCurve,
                min: 50,
                max: 200,
                divisions: 15,
                format: (v) => v == 128 ? '标准' : (v < 128 ? '灵敏' : '平缓'),
                onChanged: (v) => controller.steeringCurve = v,
              ),
              _SliderTile(
                icon: Icons.gps_fixed,
                label: '摇杆死区',
                value: controller.deadzone,
                min: 0,
                max: 50,
                divisions: 10,
                format: (v) => '±$v',
                onChanged: (v) => controller.deadzone = v,
              ),
              Card(
                color: Colors.red.withValues(alpha: 0.06),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.red.withValues(alpha: 0.3))),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('隐私保护', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('转交小车前，清除芯片里保存的 WiFi 信息（车将重启回热点模式）', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('清除 WiFi 配置？'),
                              content: const Text('将删除芯片里保存的 WiFi 名称和密码，车重启后回到热点模式。'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清除')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            appState.transport?.send(commandFrame(RcCommandId.clearWifi));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已发送清除指令，车将重启回热点模式')));
                          }
                        },
                        icon: const Icon(Icons.delete_sweep, size: 18),
                        label: const Text('清除 WiFi 配置'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                color: Colors.white.withValues(alpha: 0.05),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '说明：限速在固件侧强制生效，即使 App 异常，车速也不会超过设定上限。转向灵敏度 1.0 为线性，越小越灵敏，越大越平缓。',
                    style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final int min;
  final int max;
  final int divisions;
  final String Function(int) format;
  final ValueChanged<int> onChanged;

  const _SliderTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.cyan.shade300, size: 20),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(format(value), style: TextStyle(color: Colors.cyan.shade300, fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: divisions,
              activeColor: Colors.cyan,
              onChanged: (v) => onChanged(v.round()),
            ),
          ],
        ),
      ),
    );
  }
}