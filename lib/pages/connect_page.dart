import 'package:flutter/material.dart';

import 'provision_wifi_page.dart';
import 'device_selection_page.dart';

import '../app_state.dart';
import 'control_page.dart';
import 'recharge_page.dart';

/// 连接首页只展示教程；配网和车辆选择使用独立页面。
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, this.state});

  final AppState? state;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  AppState get state => widget.state ?? appState;

  @override
  void initState() {
    super.initState();
    state.startDiscovery();
  }

  Future<void> _openProvisioning({bool restart = false}) async {
    if (restart) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重新配网前，请手动重启小车'),
          content: const Text(
            '请先将小车断电再上电，然后在手机 Wi‑Fi 设置中连接 RC-CAR-XXXX 热点。'
            '\n若小车仍连接旧 Wi‑Fi、没有出现热点，请先在车辆选择页删除小车，清除旧配网信息。'
            '\n确认手机已连接小车热点后，再继续。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('我已重启并连接热点'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ProvisionWifiPage(state: state)));
  }

  Future<void> _connectMock() async {
    await state.connectMock();
    if (!mounted) return;
    if (state.isConnected) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ControlPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: state,
          builder: (context, _) {
            final st = state;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAccountBar(),
                  const Center(
                    child: Image(
                      image: AssetImage('assets/logo.png'),
                      width: 96,
                      height: 96,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('WiFi 连接'),
                        icon: Icon(Icons.wifi),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('模拟模式'),
                        icon: Icon(Icons.science_outlined),
                      ),
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
                      child: Text(
                        st.errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.red.shade300,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Expanded(
                    child: st.simulateMode
                        ? _buildMockPanel()
                        : _buildWifiPanel(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAccountBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.account_circle, size: 20, color: Colors.white70),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              state.user?.username ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.timer_outlined, size: 16, color: Colors.cyan.shade200),
          const SizedBox(width: 3),
          Text(
            state.user?.unlimited == true
                ? '∞'
                : '${state.user?.credits ?? 0}s',
            style: TextStyle(
              color: Colors.cyan.shade200,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const RechargePage())),
            icon: const Icon(
              Icons.add_circle_outline,
              size: 16,
              color: Colors.greenAccent,
            ),
            label: const Text(
              '充值',
              style: TextStyle(fontSize: 12, color: Colors.greenAccent),
            ),
          ),
          TextButton.icon(
            onPressed: () async => state.logout(),
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('登出', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildWifiPanel() {
    return ListView(
      children: [
        _hintCard(
          '首次使用：先配网',
          '1. 在手机 Wi‑Fi 设置中连接小车热点 RC-CAR-XXXX（密码 12345678）。\n'
              '2. 点击下方“我已连接”，在下一页填写家庭 Wi‑Fi。\n'
              '3. 发送配网后，按提示将手机切回家庭 Wi‑Fi，再选择车辆连接。',
        ),
        const SizedBox(height: 12),
        if (!state.provisioningCompleted)
          FilledButton(
            onPressed: () => _openProvisioning(),
            child: const Text('我已连接'),
          )
        else ...[
          const Text('已完成配网引导。请连接家庭 Wi‑Fi 后选择车辆。'),
          OutlinedButton(
            onPressed: () => _openProvisioning(restart: true),
            child: const Text('重新配网'),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DeviceSelectionPage(state: state),
            ),
          ),
          icon: const Icon(Icons.directions_car),
          label: const Text('选择车辆'),
        ),
      ],
    );
  }

  Widget _buildMockPanel() {
    return ListView(
      children: [
        _card('模拟设备（开发用）', [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bluetooth_connected, color: Colors.cyan),
            title: const Text(
              'RC-CAR-MOCK1',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('虚拟 ESP32 · 模拟连接'),
            trailing: FilledButton(
              onPressed: _connectMock,
              child: const Text('连接'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _hintCard(String title, String text) {
    return Card(
      color: Colors.white.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
