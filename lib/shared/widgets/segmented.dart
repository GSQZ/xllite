import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// iOS-style segmented control with a sliding thumb.
class AppSegmented extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: dark ? 1 : 0.85),
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth / labels.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: AppMotion.long,
                curve: AppMotion.emphasized,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    color: dark
                        ? scheme.surfaceContainerHighest
                        : scheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md - 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: dark ? 0.3 : 0.08,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == index,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          onTap: () => onChanged(i),
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: AppMotion.medium,
                              style: theme.textTheme.labelLarge!.copyWith(
                                fontSize: 14,
                                color: i == index
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                                fontWeight: i == index
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                              child: Text(labels[i]),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
