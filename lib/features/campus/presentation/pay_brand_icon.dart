import 'package:flutter/material.dart';
import 'package:xinli_lite/features/campus/campus.dart';

/// Which payment brand a school pay method belongs to.
enum PayBrand { wechat, alipay, card, other }

PayBrand payBrandOf(PayMethod method) {
  final name = method.name;
  if (name.contains('微信') || name.toLowerCase().contains('wechat')) {
    return PayBrand.wechat;
  }
  if (name.contains('支付宝') || name.toLowerCase().contains('alipay')) {
    return PayBrand.alipay;
  }
  if (method.code == '06' || name.contains('余额') || name.contains('校园卡')) {
    return PayBrand.card;
  }
  return PayBrand.other;
}

/// Payment brand mark, drawn as vectors so no icon package is needed:
/// WeChat's double speech bubble on its green, Alipay's "支" on its blue,
/// and a wallet for campus-card balance.
class PayBrandIcon extends StatelessWidget {
  const PayBrandIcon({super.key, required this.brand, this.size = 36});

  final PayBrand brand;
  final double size;

  static const wechatGreen = Color(0xFF07C160);
  static const alipayBlue = Color(0xFF1677FF);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(size * 0.26);
    final Widget mark = switch (brand) {
      PayBrand.wechat => Container(
        decoration: BoxDecoration(color: wechatGreen, borderRadius: radius),
        child: CustomPaint(painter: _WeChatPainter()),
      ),
      PayBrand.alipay => Container(
        decoration: BoxDecoration(color: alipayBlue, borderRadius: radius),
        alignment: Alignment.center,
        child: Text(
          '支',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.6,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
      PayBrand.card => Container(
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: radius,
        ),
        child: Icon(
          Icons.account_balance_wallet_rounded,
          size: size * 0.56,
          color: scheme.primary,
        ),
      ),
      PayBrand.other => Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: radius,
        ),
        child: Icon(
          Icons.credit_card_rounded,
          size: size * 0.56,
          color: scheme.onSurfaceVariant,
        ),
      ),
    };
    return ExcludeSemantics(
      child: SizedBox.square(dimension: size, child: mark),
    );
  }
}

/// Two overlapping speech bubbles with eyes, in white.
class _WeChatPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final white = Paint()..color = Colors.white;
    final green = Paint()..color = PayBrandIcon.wechatGreen;

    // Back (larger) bubble, upper left, with a tail at the bottom left.
    final big = Rect.fromLTWH(s * 0.14, s * 0.2, s * 0.5, s * 0.42);
    canvas.drawOval(big, white);
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.22, s * 0.52)
        ..lineTo(s * 0.19, s * 0.66)
        ..lineTo(s * 0.33, s * 0.58)
        ..close(),
      white,
    );
    canvas.drawCircle(Offset(s * 0.31, s * 0.37), s * 0.035, green);
    canvas.drawCircle(Offset(s * 0.47, s * 0.37), s * 0.035, green);

    // Front (smaller) bubble, lower right, separated by a green rim.
    final small = Rect.fromLTWH(s * 0.42, s * 0.42, s * 0.44, s * 0.36);
    canvas.drawOval(small.inflate(s * 0.035), green);
    canvas.drawOval(small, white);
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.76, s * 0.72)
        ..lineTo(s * 0.8, s * 0.84)
        ..lineTo(s * 0.68, s * 0.76)
        ..close(),
      white,
    );
    canvas.drawCircle(Offset(s * 0.57, s * 0.57), s * 0.03, green);
    canvas.drawCircle(Offset(s * 0.71, s * 0.57), s * 0.03, green);
  }

  @override
  bool shouldRepaint(_WeChatPainter oldDelegate) => false;
}
