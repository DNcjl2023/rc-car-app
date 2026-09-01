import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

/// 认证服务：先本地模拟（admin/1990 测试账号 + 本地注册），
/// 后续对接线上成熟认证方案（Firebase Auth / Supabase / 自建后端）。
/// Google 登录、邮箱验证码登录已在接口预留（TODO 对接）。
abstract class AuthService {
  Future<User?> login(String username, String password);
  Future<String?> register(String username, String password, String email); // null=成功
  Future<void> logout();
  Future<User?> restoreSession();
}

/// 本地模拟实现：
/// - 内置测试账号 admin / 1990（无限额度管理员）
/// - 注册用户持久化到 shared_preferences（仅本机，后续换真实后端）
class LocalAuthService implements AuthService {
  static const _kUsers = 'auth_users_v1';
  static const _kSession = 'auth_session_v1';

  @override
  Future<User?> login(String username, String password) async {
    // 内置管理员测试账号
    if (username == 'admin' && password == '1990') {
      final admin = const User(username: 'admin', email: 'admin@rc.local', credits: -1, isAdmin: true);
      await _saveSession(admin);
      return admin;
    }
    // 本地注册用户
    final users = await _loadUsers();
    final u = users[username];
    if (u != null && u['pass'] == password) {
      final user = User(
        username: username,
        email: u['email'] as String? ?? '',
        credits: (u['credits'] as num?)?.toInt() ?? 0,
      );
      await _saveSession(user);
      return user;
    }
    return null;
  }

  @override
  Future<String?> register(String username, String password, String email) async {
    if (username.isEmpty || password.length < 4) {
      return '用户名不能为空，密码至少 4 位';
    }
    final users = await _loadUsers();
    if (users.containsKey(username) || username == 'admin') {
      return '用户名已存在';
    }
    users[username] = {'pass': password, 'email': email, 'credits': 300}; // 新用户赠送 5 分钟
    await _saveUsers(users);
    return null;
  }

  @override
  Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSession);
  }

  @override
  Future<User?> restoreSession() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kSession);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return User(
        username: m['username'] as String,
        email: m['email'] as String? ?? '',
        credits: (m['credits'] as num?)?.toInt() ?? 0,
        isAdmin: m['isAdmin'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Google / 邮箱登录（预埋接口，TODO 对接线上认证）
  Future<User?> googleLogin() async {
    // TODO: 集成 google_sign_in / firebase_auth
    return null;
  }

  Future<void> _saveSession(User u) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSession, jsonEncode({
      'username': u.username,
      'email': u.email,
      'credits': u.credits,
      'isAdmin': u.isAdmin,
    }));
  }

  Future<Map<String, Map<String, Object>>> _loadUsers() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kUsers);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as Map).cast<String, Object>()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveUsers(Map<String, Map<String, Object>> users) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUsers, jsonEncode(users));
  }
}

/// 全局单例（后续可替换为 FirebaseAuthService 等）
final AuthService authService = LocalAuthService();
