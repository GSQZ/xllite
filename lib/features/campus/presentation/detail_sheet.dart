import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';

/// Read-only detail sheet: a title, an optional emphasized value and
/// label/value rows. Rows with empty values are left out.
Future<void> showDetailSheet(
  BuildContext context, {
  required String title,
  String? highlight,
  String? highlightLabel,
  required List<(String, String)> rows,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final visible = rows.where((r) => r.$2.trim().isNotEmpty).toList();
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
            if (highlight != null) ...[
              const SizedBox(height: AppSpacing.md),
              if (highlightLabel != null)
                Text(
                  highlightLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              Text(
                highlight,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            for (final (label, value) in visible)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 76,
                      child: Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        value,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
