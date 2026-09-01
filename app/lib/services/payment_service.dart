/// 支付方式
enum PaymentMethod { paypal, creditCard }

/// 支付结果
class PaymentResult {
  final bool success;
  final String message;
  final String? transactionId;
  final int credits; // 购买的秒数
  const PaymentResult({required this.success, required this.message, this.transactionId, this.credits = 0});
}

/// 支付服务：预埋 PayPal / 信用卡支付接口（占位），
/// 正式上线需对接线上成熟项目（flutter_paypal / credit_card_payment 等）。
/// 支付资质由客户方处理，本端只负责发起支付与回调确认。
abstract class PaymentService {
  Future<PaymentResult> purchase(int seconds, PaymentMethod method);
}

/// 模拟实现：不真正扣款，直接成功（开发/联调用）。
/// TODO: 对接 PayPal REST API / Stripe / 信用卡网关。
class MockPaymentService implements PaymentService {
  int _txn = 0;

  @override
  Future<PaymentResult> purchase(int seconds, PaymentMethod method) async {
    _txn++;
    return PaymentResult(
      success: true,
      message: '模拟支付成功（${method.name}）',
      transactionId: 'MOCK-$_txn',
      credits: seconds,
    );
  }
}

final PaymentService paymentService = MockPaymentService();
