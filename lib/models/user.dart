/// 用户模型：账户 + 余额（credits 单位：秒，用于付费计时控制）
class User {
  final String username;
  final String email;
  final int credits; // 剩余可控制秒数（-1 = 无限/管理员）
  final bool isAdmin;

  const User({
    required this.username,
    required this.email,
    required this.credits,
    this.isAdmin = false,
  });

  bool get unlimited => credits < 0;

  User copyWith({int? credits}) => User(
        username: username,
        email: email,
        credits: credits ?? this.credits,
        isAdmin: isAdmin,
      );
}
