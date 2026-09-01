import 'package:flutter/material.dart';

import '../app_state.dart';
import 'control_page.dart';

/// 连接页：WiFi 连接（主）+ 配网 + 模拟模式（开发用）
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  // 默认 IP 可用 --dart-define=DEFAULT_IP=xxx 覆盖（测试/联调用），默认 192.168.4.1（AP 配网模式）
  static const _defaultIp = String.fromEnvironment('DEFAULT_IP', defaultValue: '192.168.4.1');
  final _ipCtrl = TextEditingController(text: _defaultIp);
  final _apIpCtrl = TextEditingController(text: '192.168.4.1');
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void dispose() {
    _ipCtrl.dispose();
    _apIpCtrl.dispose();
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _connectWifi() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) {
      _toast('请输入 IP');
      return;
    }
    await appState.connectWifi(ip);
    if (!mounted) return;
    if (appState.isConnected) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ControlPage()));
    }
  }

  Future<void> _connectMock() async {
    await appState.connectMock();
    if (!mounted) return;
    if (appState.isConnected) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ControlPage()));
    }
  }

  Future<void> _provision() async {
    final ssid = _ssidCtrl.text.trim();
    final pass = _passCtrl.text;
    if (ssid.isEmpty) {
      _toast('请输入 WiFi 名称');
      return;
    }
    final ok = await appState.provisionWifi(_apIpCtrl.text.trim(), ssid, pass);
    if (!mounted) return;
    _toast(ok ? '配网成功！车已保存 WiFi 并重启，请把手机连回 $ssid' : '配网失败，请检查后重试');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: appState,
          builder: (context, _) {
            final st = appState;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 账户行：用户名 + 余额 + 登出
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.account_circle, size: 20, color: Colors.white70),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            appState.user?.username ?? '',
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.timer_outlined, size: 16, color: Colors.cyan.shade200),
                        const SizedBox(width: 3),
                        Text(
                          appState.user?.unlimited == true ? '∞' : '${appState.user?.credits ?? 0}s',
                          style: TextStyle(color: Colors.cyan.shade200, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 10),
                        TextButton.icon(
                          onPressed: () async {
                            await appState.logout();
                            if (context.mounted) Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.logout, size: 16),
                          label: const Text('登出', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.sports_motorsports, size: 60, color: Colors.cyan),
                  const Text('蓝牙遥控车', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  // 模式切换
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('WiFi 主'), icon: Icon(Icons.wifi)),
                      ButtonSegment(value: true, label: Text('模拟模式'), icon: Icon(Icons.science_outlined)),
                    ],
                    selected: {st.simulateMode},
                    onSelectionChanged: (s) => st.setSimulateMode(s.first),
                  ),
                  const SizedBox(height: 8),
                  if (st.phase == AppPhase.connecting)
                    const LinearProgressIndicator(),
                  if (st.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(st.errorMessage!, textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red.shade300, fontSize: 12)),
                    ),
                  Expanded(
                    child: st.simulateMode ? _buildMockPanel() : _buildWifiPanel(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
  /// WiFi 面板：连接 + 配网
  Widget _buildWifiPanel() {
    return ListView(
      children: [
        _hintCard('配网说明',
            '首次使用：手机连接热点 RC-CAR-29E0（密码 12345678），IP 填 192.168.4.1，先"发送配网"把家里 WiFi 告诉车；配好后车自动连家里 WiFi，IP 填车在局域网里的地址。'),
        const SizedBox(height: 10),
        _card('连接车辆', [
          _label('车 IP 地址'),
          Row(children: [
            Expanded(child: TextField(controller: _ipCtrl, decoration: const InputDecoration(hintText: '192.168.4.1'))),
            const SizedBox(width: 8),
            FilledButton(onPressed: _connectWifi, child: const Text('连接')),
          ]),
        ]),
        const SizedBox(height: 10),
        _card('配网（设置 WiFi）', [
          _label('热点 IP'),
          TextField(controller: _apIpCtrl, decoration: const InputDecoration(hintText: '192.168.4.1')),
          const SizedBox(height: 8),
          _label('家里 WiFi 名称'),
          TextField(controller: _ssidCtrl, decoration: const InputDecoration(hintText: '输入 WiFi 名称')),
          const SizedBox(height: 8),
          _label('WiFi 密码'),
          TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(hintText: '输入密码')),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _provision,
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('发送配网（车将保存并重启）'),
          ),
        ]),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildMockPanel() {
    return ListView(children: [
      _card('模拟设备（开发用）', [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bluetooth_connected, color: Colors.cyan),
          title: const Text('RC-CAR-MOCK1', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('虚拟 ESP32 · 模拟连接'),
          trailing: FilledButton(onPressed: _connectMock, child: const Text('连接')),
        ),
      ]),
    ]);
  }

  Widget _hintCard(String title, String text) {
    return Card(
      color: Colors.white.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(text, style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.5)),
        ]),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...children,
        ]),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(s, style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
      );
}