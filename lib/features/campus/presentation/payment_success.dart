import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_theme.dart';
import 'payment_watch.dart';

/// The "paid" moment shown in place of the code: a green disc pops in, a
/// tick draws itself, two rings and a burst of sparks spread out, then the
/// amount counts up and the merchant settles in. One controller, ~1.6 s.
class PaymentSuccess extends StatefulWidget {
  const PaymentSuccess({
    super.key,
    required this.payment,
    required this.onDone,
    this.title = '支付成功',
    this.amountPrefix = '-¥',
    this.detail,
  });

  final DetectedPayment payment;
  final VoidCallback onDone;
  final String title;

  /// '-¥' for money that left the card, '¥' for a top-up.
  final String amountPrefix;

  /// Replaces the default "merchant · 余额" line.
  final String? detail;

  @override
  State<PaymentSuccess> createState() => _PaymentSuccessState();
}

class _PaymentSuccessState extends State<PaymentSuccess>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  var _tickHaptic = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _c.addListener(() {
      if (!_tickHaptic && _c.value > 0.42) {
        _tickHaptic = true;
        HapticFeedback.lightImpact();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isDismissed) {
      if (AppMotion.reduced(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Animation<double> _band(double a, double b, [Curve curve = Curves.easeOut]) =>
      _c.drive(CurveTween(curve: Interval(a, b, curve: curve)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final green = StatusColors.of(context).success;
    final p = widget.payment;

    final disc = _band(0.0, 0.32, Curves.easeOutBack);
    final tick = _band(0.22, 0.48, Curves.easeInOutCubic);
    final burst = _band(0.12, 0.62, Curves.easeOutCubic);
    final title = _band(0.40, 0.62, Curves.easeOutCubic);
    final amount = _band(0.48, 0.92, Curves.easeOutQuart);
    final meta = _band(0.64, 0.88, Curves.easeOutCubic);
    final button = _band(0.74, 1.0, Curves.easeOutCubic);

    Widget rise(Animation<double> a, Widget child, [double dy = 10]) =>
        AnimatedBuilder(
          animation: a,
          child: child,
          builder: (context, child) => Opacity(
            opacity: a.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, dy * (1 - a.value)),
              child: child,
            ),
          ),
        );

    return Semantics(
      liveRegion: true,
      label:
          '${widget.title}，金额 ${p.amount.toStringAsFixed(2)} 元'
          '${p.merchant.isEmpty ? '' : '，${p.merchant}'}',
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 132,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _BurstPainter(
                    color: green,
                    disc: disc.value,
                    tick: tick.value,
                    burst: burst.value,
                    onDisc: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            rise(
              title,
              ExcludeSemantics(
                child: Text(
                  widget.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            rise(
              amount,
              ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: amount,
                  builder: (context, _) => Text(
                    '${widget.amountPrefix}${(p.amount * amount.value).toStringAsFixed(2)}',
                    key: const Key('paid.amount'),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
            rise(
              meta,
              ExcludeSemantics(
                child: AnimatedSwitcher(
                  duration: AppMotion.medium,
                  child: Text(
                    widget.detail ??
                        [
                          if (p.merchant.isNotEmpty) p.merchant,
                          '余额 ¥${p.balance.toStringAsFixed(2)}',
                        ].join(' · '),
                    key: ValueKey(p.merchant),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            rise(
              button,
              FilledButton(
                key: const Key('paid.done'),
                style: FilledButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(160, AppSizes.touchTarget),
                  shape: const StadiumBorder(),
                ),
                onPressed: widget.onDone,
                child: const Text('完成'),
              ),
              6,
            ),
          ],
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.color,
    required this.onDisc,
    required this.disc,
    required this.tick,
    required this.burst,
  });

  final Color color, onDisc;
  final double disc, tick, burst;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = 34.0;

    // Two rings breathing out from the disc.
    for (final (delay, strength) in [(0.0, 0.5), (0.25, 0.3)]) {
      final t = ((burst - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (t <= 0 || t >= 1) continue;
      canvas.drawCircle(
        c,
        r + 30 * t,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - t)
          ..color = color.withValues(alpha: strength * (1 - t)),
      );
    }

    // Sparks: twelve short dashes flying out and fading.
    if (burst > 0 && burst < 1) {
      final spark = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3 * (1 - burst)
        ..color = color.withValues(alpha: 0.9 * (1 - burst));
      for (var i = 0; i < 12; i++) {
        final a = i * math.pi / 6 + (i.isEven ? 0 : 0.18);
        final dir = Offset(math.cos(a), math.sin(a));
        final reach = i.isEven ? 1.0 : 0.78;
        final from = r + 6 + 22 * burst * reach;
        final to = from + 7 * (1 - burst);
        canvas.drawLine(c + dir * from, c + dir * to, spark);
      }
    }

    // Soft glow + disc.
    final s = disc.clamp(0.0, 1.2);
    if (s > 0) {
      canvas.drawCircle(
        c,
        r * s + 6,
        Paint()
          ..color = color.withValues(alpha: 0.16 * disc.clamp(0.0, 1.0))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(c, r * s, Paint()..color = color);
    }

    // The tick draws itself.
    if (tick > 0) {
      final path = Path()
        ..moveTo(c.dx - 13, c.dy + 1)
        ..lineTo(c.dx - 4, c.dy + 10)
        ..lineTo(c.dx + 14, c.dy - 9);
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * tick),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = onDisc,
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.disc != disc || old.tick != tick || old.burst != burst;
}
