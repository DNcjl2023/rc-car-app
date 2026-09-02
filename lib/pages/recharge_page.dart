import 'package:flutter/material.dart';
import '../app_state.dart';
import '../services/payment_service.dart';

/// 充值页面：选时长 + 选支付方式（PayPal/信用卡）→ 模拟支付到账
/// 正式上线时对接线上成熟支付项目（flutter_paypal / Stripe 等），支付资质由客户方处理
class RechargePage extends StatefulWidget {
  const RechargePage({super.key});

  @override
  State<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends State<RechargePage> {
  int _minutes = 5; // 默认 5 分钟
  PaymentMethod _method = PaymentMethod.paypal;
  bool _busy = false;

  // 简单定价（模拟）：1/5/10/30 分钟
  static const _price = {1: 2, 5: 8, 10: 15, 30: 40};
  static const _options = [1, 5, 10, 30];

  Future<void> _pay() async {
    setState(() => _busy = true);
    final seconds = _minutes * 60;
    final result = await paymentService.purchase(seconds, _method);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.success) {
      appState.addCredits(result.credits);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('支付成功！已到账 ${result.credits ~/ 60} 分钟（${result.transactionId}）')),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('支付失败：${result.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = appState.user;
    return Scaffold(
      appBar: AppBar(title: const Text('充值')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 当前余额
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: Colors.cyan),
                  const SizedBox(width: 10),
                  Text('当前余额',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                  const Spacer(),
                  Text(
                    user?.unlimited == true ? '无限时长（管理员）' : '${user?.credits ?? 0} 秒',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('选择时长', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _options.map((m) {
                final selected = _minutes == m;
                return ChoiceChip(
                  label: Text('$m 分钟 · ¥${_price[m]}'),
                  selected: selected,
                  selectedColor: Colors.cyan.withValues(alpha: 0.35),
                  onSelected: (_) => setState(() => _minutes = m),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            const Text('支付方式', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            SegmentedButton<PaymentMethod>(
              segments: const [
                ButtonSegment(
                  value: PaymentMethod.paypal,
                  label: Text('PayPal'),
                  icon: Icon(Icons.payment),
                ),
                ButtonSegment(
                  value: PaymentMethod.creditCard,
                  label: Text('信用卡'),
                  icon: Icon(Icons.credit_card),
                ),
              ],
              selected: {_method},
              onSelectionChanged: (s) => setState(() => _method = s.first),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _busy ? null : _pay,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.verified_user),
              label: Text(_busy ? '支付中...' : '确认支付 ¥${_price[_minutes]}'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: 12),
            Text(
              '当前为模拟支付（开发联调用）。正式上线将对接 PayPal / 信用卡网关，支付资质由运营方处理。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
