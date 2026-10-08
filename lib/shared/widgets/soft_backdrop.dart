import 'package:flutter/material.dart';

import '../theme/theme_settings.dart';

/// Quiet tinted wash behind entry screens, tinted by the chosen skin.
/// Purely decorative: it ignores pointers and is hidden from
/// accessibility services.
class SoftBackdrop extends StatelessWidget {
  const SoftBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final skin = ThemeScope.maybeOf(context)?.skin;
    final accent = skin?.glow(theme.brightness) ?? theme.colorScheme.primary;
    final wash = accent.withValues(alpha: dark ? 0.14 : 0.11);

    Widget glow(Color color, double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: const Alignment(0, 0.15),
                    colors: [wash, wash.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: -140,
          right: -120,
          child: IgnorePointer(
            child: glow(accent.withValues(alpha: dark ? 0.2 : 0.16), 360),
          ),
        ),
        Positioned(
          top: 40,
          left: -160,
          child: IgnorePointer(
            child: glow(accent.withValues(alpha: dark ? 0.08 : 0.06), 320),
          ),
        ),
        child,
      ],
    );
  }
}
