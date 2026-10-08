import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum PanelTone { neutral, error }

/// Centered full-area state: loading, empty or recoverable failure.
class StatePanel extends StatelessWidget {
  const StatePanel({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.loading = false,
    this.tone = PanelTone.neutral,
    this.actions = const [],
  });

  final String title;
  final String? message;
  final IconData? icon;
  final bool loading;
  final PanelTone tone;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = switch (tone) {
      PanelTone.neutral => (scheme.primaryContainer, scheme.onPrimaryContainer),
      PanelTone.error => (scheme.errorContainer, scheme.onErrorContainer),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        // Inside a scrolling list there is no height to fill: lay out inline.
        if (!constraints.hasBoundedHeight) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: _content(context, background, foreground)),
          );
        }
        final gutter = AppSpacing.gutterFor(constraints.maxWidth);
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: gutter,
            vertical: AppSpacing.xl,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - AppSpacing.xl * 2).clamp(
                0,
                double.infinity,
              ),
            ),
            child: Center(child: _content(context, background, foreground)),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context, Color background, Color foreground) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox.square(
              dimension: 40,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          else if (icon != null)
            ExcludeSemantics(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: foreground),
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          Semantics(
            liveRegion: true,
            child: Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              actions[i],
            ],
          ],
        ],
      ),
    );
  }
}
