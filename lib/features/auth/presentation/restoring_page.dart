import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/brand_mark.dart';

/// Shown for [AuthPhase.idle] / [AuthPhase.restoring] while the saved session
/// is read and, if needed, renewed.
///
/// The brand appears at once; the progress hint only fades in after a short
/// delay so a fast restore never flashes a spinner.
class RestoringPage extends StatefulWidget {
  const RestoringPage({super.key});

  @override
  State<RestoringPage> createState() => _RestoringPageState();
}

class _RestoringPageState extends State<RestoringPage>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isDismissed) {
      if (AppMotion.reduced(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = _controller.drive(
      CurveTween(curve: const Interval(0, 0.45, curve: AppMotion.curve)),
    );
    final hint = _controller.drive(
      CurveTween(curve: const Interval(0.55, 1, curve: AppMotion.curve)),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: brand,
                  child: ScaleTransition(
                    scale: brand.drive(Tween(begin: 0.92, end: 1.0)),
                    child: const BrandHeader(center: true),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                FadeTransition(
                  opacity: hint,
                  child: Column(
                    children: [
                      const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          '正在恢复登录状态…',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
