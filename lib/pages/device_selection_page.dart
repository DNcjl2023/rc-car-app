import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/discovered_car.dart';
import 'control_page.dart';

class DeviceSelectionPage extends StatefulWidget {
  const DeviceSelectionPage({super.key, required this.state});

  final AppState state;

  @override
  State<DeviceSelectionPage> createState() => _DeviceSelectionPageState();
}

class _DeviceSelectionPageState extends State<DeviceSelectionPage> {
  String? _selectedId;
  bool _busy = false;
  bool _scanning = false;
  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    await state.startDiscovery();
    // 固件每 10 秒广播，至少覆盖一个完整广播周期。
    await Future<void>.delayed(const Duration(seconds: 12));
    if (!mounted) return;
    setState(() => _scanning = false);
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _connect() async {
    final cars = state.discoveredCars.where(
      (car) => car.deviceId == _selectedId,
    );
    if (cars.isEmpty || _busy) return;
    // 按 ID 查最新发现结果，不使用用户点选时缓存的旧 IP。
    final car = cars.first;
    setState(() => _busy = true);
    await state.connectWifi(car.ip, name: car.displayName);
    if (!mounted) return;
    if (!state.isConnected) {
      setState(() => _busy = false);
      _message(state.errorMessage ?? '连接失败，请重试');
      return;
    }
    await _nameCar(car);
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ControlPage()));
  }

  Future<void> _nameCar(DiscoveredCar car) async {
    String name = car.alias ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(car.alias == null ? '给这辆车命名' : '修改车辆名称'),
        content: TextFormField(
          initialValue: car.alias ?? '',
          autofocus: true,
          onChanged: (value) => name = value,
          decoration: const InputDecoration(hintText: '例如：rccar'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('跳过'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, name),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      try {
        await state.setDeviceAlias(car.deviceId, result);
      } catch (_) {
        if (mounted) _message('名称保存失败，请稍后重试');
      }
    }
  }

  Future<void> _delete(DiscoveredCar car) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除小车并清除配网？'),
        content: Text(
          '将向「${car.displayName}」发送清除 Wi‑Fi 名称和密码的指令，'
          '并删除本机保存的车辆名称。之后需要重新配网。\n'
          '请保持手机与小车在同一网络。小车离线时无法清除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除并清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await state.deleteCar(car.deviceId);
      if (!mounted) return;
      setState(() => _selectedId = null);
      _message('清除指令已发送，本机记录已删除。固件无成功回执；请检查热点，必要时手动重启小车。');
    } catch (_) {
      if (mounted) _message('删除未完成，请确认小车在线后重试；无法确认配网信息已清除。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('选择车辆')),
        body: AnimatedBuilder(
          animation: state,
          builder: (context, _) {
            final cars = state.discoveredCars;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('请让手机和小车连接同一家庭 Wi‑Fi。发现广播约每 10 秒一次。'),
                OutlinedButton.icon(
                  onPressed: _scanning || _busy ? null : _scan,
                  icon: const Icon(Icons.radar),
                  label: Text(_scanning ? '正在扫描…' : '重新扫描'),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (cars.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      _scanning ? '正在等待小车广播…' : '暂未发现小车，请检查网络和本地网络权限后重试。',
                    ),
                  ),
                ...cars.map(
                  (car) => Card(
                    child: ListTile(
                      selected: _selectedId == car.deviceId,
                      onTap: _busy
                          ? null
                          : () => setState(() => _selectedId = car.deviceId),
                      leading: Icon(
                        _selectedId == car.deviceId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(car.displayName),
                      subtitle: Text('${car.ip} · ID ${car.deviceId}'),
                      trailing: IconButton(
                        tooltip: '删除小车',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy ? null : () => _delete(car),
                      ),
                    ),
                  ),
                ),
                FilledButton(
                  onPressed:
                      !_busy && cars.any((car) => car.deviceId == _selectedId)
                      ? _connect
                      : null,
                  child: const Text('连接所选车辆'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
