import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Blur strength for every frosted surface. One value everywhere keeps
/// grouped backdrops shareable (and cheap).
const double glassSigma = 18;

/// Translucent fill laid over the blur.
Color glassFill(BuildContext context, [double strength = 1]) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  return (dark ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest)
      .withValues(alpha: (dark ? 0.62 : 0.68) * strength);
}

/// Fine light edge that makes glass read as a separate layer.
Color glassEdge(BuildContext context, [double strength = 1]) {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  return (dark ? Colors.white : theme.colorScheme.outlineVariant).withValues(
    alpha: (dark ? 0.08 : 0.55) * strength,
  );
}

/// Frosted-glass card: blurs whatever is behind it, then lets [child]
/// paint a translucent fill on top (see [glassFill]).
///
/// Cards use the grouped backdrop by default: all cards inside one
/// [BackdropGroup] (one per screen or sheet) share a single snapshot, which
/// keeps many blurred cards affordable on low-end phones. Chrome that floats
/// over scrolling content (bars, sheets) passes `grouped: false`.
class Frosted extends StatelessWidget {
  const Frosted({
    super.key,
    required this.child,
    this.radius = AppRadius.lg + 4,
    this.grouped = true,
    this.sigma = glassSigma,
  });

  final Widget child;
  final double radius;
  final bool grouped;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    final filter = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: grouped
          ? BackdropFilter.grouped(filter: filter, child: child)
          : BackdropFilter(filter: filter, child: child),
    );
  }
}

/// A [Material] card on frosted glass, so ink splashes stay visible.
class FrostedCard extends StatelessWidget {
  const FrostedCard({
    super.key,
    required this.child,
    this.radius = AppRadius.lg + 4,
    this.edge,
    this.fill,
  });

  final Widget child;
  final double radius;

  /// Overrides the hairline (e.g. a selected or current state).
  final BorderSide? edge;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    return Frosted(
      radius: radius,
      child: Material(
        color: fill ?? glassFill(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: edge ?? BorderSide(color: glassEdge(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
