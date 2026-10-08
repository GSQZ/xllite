import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Scrollable, width-limited page body for forms.
///
/// Fills at least the viewport: [header] sits at the top, [footer] at the
/// bottom and [child] is centered between them. When the keyboard or a large
/// font makes the content taller than the viewport, it scrolls instead of
/// overflowing.
class AdaptivePageBody extends StatelessWidget {
  const AdaptivePageBody({
    super.key,
    required this.child,
    this.header,
    this.footer,
    this.maxWidth = AppSizes.contentMaxWidth,
  });

  final Widget child;
  final Widget? header;
  final Widget? footer;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = AppSpacing.gutterFor(constraints.maxWidth);
        final horizontal = math.max(
          gutter,
          (constraints.maxWidth - maxWidth) / 2 + gutter,
        );
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            horizontal,
            AppSpacing.xl,
            horizontal,
            AppSpacing.lg,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(
                0,
                constraints.maxHeight - AppSpacing.xl - AppSpacing.lg,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header ?? const SizedBox.shrink(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: child,
                ),
                footer ?? const SizedBox.shrink(),
              ],
            ),
          ),
        );
      },
    );
  }
}
