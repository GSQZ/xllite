import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';

/// The emphasized panel used once per screen (course card, GPA, next exam,
/// balance): primary gradient, soft corner light and a coloured shadow.
class AccentPanel extends StatelessWidget {
  const AccentPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl - 4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(scheme.primary, Colors.white, 0.14)!,
            scheme.primary,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Stack(
          children: [
            Positioned(
              top: -60,
              right: -40,
              child: IgnorePointer(
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        scheme.onPrimary.withValues(alpha: 0.16),
                        scheme.onPrimary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// Text style on an [AccentPanel], at [alpha] of onPrimary.
TextStyle? onAccent(
  BuildContext context,
  TextStyle? style, [
  double alpha = 1,
]) => style?.copyWith(
  color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: alpha),
);

/// Small label + value pair used along the bottom of an accent panel.
class AccentStat extends StatelessWidget {
  const AccentStat({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: onAccent(context, theme.textTheme.bodySmall, 0.78)),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value,
                style: onAccent(context, theme.textTheme.titleMedium)?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: ' $unit',
                  style: onAccent(context, theme.textTheme.bodySmall, 0.78),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
