import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_state.dart';

class ProvisionWifiPage extends StatefulWidget {
  const ProvisionWifiPage({super.key, required this.state});

  final AppState state;

  @override
  State<ProvisionWifiPage> createState() => _ProvisionWifiPageState();
}

class _ProvisionWifiPageState extends State<ProvisionWifiPage> {
  final _formKey = GlobalKey<FormState>();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.state.provisionWifi(
      '192.168.4.1',
      _ssid.text.trim(),
      _password.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = ok;
      if (!ok) _error = '发送失败，请确认手机已连接小车热点后重试。';
    });
    if (ok) _password.clear();
  }

  Future<void> _complete() async {
    setState(() => _busy = true);
    try {
      await widget.state.completeProvisioning();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '无法保存配网进度，请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_sent ? '切回家庭 Wi‑Fi' : '家庭 Wi‑Fi'),
          leading: IconButton(
            tooltip: '关闭配网',
            onPressed: _busy ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_sent) ...[
              const Icon(Icons.wifi, size: 56),
              const SizedBox(height: 20),
              const Text('配网指令已发送', style: TextStyle(fontSize: 22)),
              const SizedBox(height: 12),
              Text(
                '请打开手机 Wi‑Fi 设置，连接回「${_ssid.text.trim()}」。\n'
                '小车联网可能需要一些时间；返回后点击“完成”，再从首页选择车辆。',
              ),
              const SizedBox(height: 12),
              const Text('发送成功不代表密码已验证；是否联网成功，以车辆发现结果为准。'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _complete,
                child: const Text('完成'),
              ),
            ] else
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('请保持手机连接小车热点，填写小车要连接的家庭 Wi‑Fi。'),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _ssid,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: '家庭 Wi‑Fi 名称',
                      ),
                      validator: (value) {
                        final length = utf8.encode(value?.trim() ?? '').length;
                        return length == 0 || length > 32
                            ? '请输入 1–32 字节的 Wi‑Fi 名称'
                            : null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(labelText: 'Wi‑Fi 密码'),
                      validator: (value) => utf8.encode(value ?? '').length > 64
                          ? 'Wi‑Fi 密码不能超过 64 字节'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: const Text('发送配网信息'),
                    ),
                  ],
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
