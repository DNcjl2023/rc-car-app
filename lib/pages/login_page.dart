import 'package:flutter/material.dart';
import '../app_state.dart';

/// 登录/注册页（简洁）：登录成功进入连接页
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final String? err;
    if (_registerMode) {
      err = await appState.register(_userCtrl.text, _passCtrl.text, _emailCtrl.text);
    } else {
      err = await appState.login(_userCtrl.text, _passCtrl.text);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    // 登录成功：home 根路由的 AnimatedBuilder 会自动切换到连接页（无需手动导航）
    // 登出同理自动回到登录页，避免路由栈空导致黑屏
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.sports_motorsports, size: 64, color: Colors.cyan),
                  const SizedBox(height: 8),
                  Text(
                    _registerMode ? '注册账号' : '登录',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_outline, size: 20),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: '密码',
                      prefixIcon: Icon(Icons.lock_outline, size: 20),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_registerMode) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: '邮箱（可选）',
                        prefixIcon: Icon(Icons.mail_outline, size: 20),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade300, fontSize: 12)),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text(_busy ? '请稍候...' : (_registerMode ? '注册并登录' : '登 录')),
                  ),
                  const SizedBox(height: 8),
                  // Google 登录（预埋：TODO 对接 google_sign_in / firebase_auth）
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Google 登录即将支持（接口已预留）')),
                      );
                    },
                    icon: const Icon(Icons.g_mobiledata, size: 22),
                    label: const Text('使用 Google 登录'),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => setState(() {
                      _registerMode = !_registerMode;
                      _error = null;
                    }),
                    child: Text(_registerMode ? '已有账号？返回登录' : '没有账号？注册'),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '测试账号：admin / 1990',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
