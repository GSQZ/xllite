import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Original Xinli Lite mark, shared with the launcher icon.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(size * 0.3);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.10),
              blurRadius: size * 0.4,
              offset: Offset(0, size * 0.14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Image.asset(
            'assets/branding/xinli_lite_app_icon_1024.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}

/// Mark + app name, used on the login and restoring screens.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.subtitle, this.center = false});

  final String? subtitle;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final align = center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            '新理Lite',
            style: theme.textTheme.headlineSmall,
            textAlign: textAlign,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: textAlign,
          ),
        ],
      ],
    );
  }
}
