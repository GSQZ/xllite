import 'package:flutter/material.dart';

/// Fully rounded border for filled fields.
///
/// Reports itself as non-outline so the floating label stays inside the
/// filled box (like the Material "filled" style) instead of cutting a notch
/// into the top edge, while still drawing a rounded ring on focus or error.
class SoftInputBorder extends InputBorder {
  const SoftInputBorder({
    super.borderSide = BorderSide.none,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  final BorderRadius borderRadius;

  @override
  bool get isOutline => false;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  SoftInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
  }) => SoftInputBorder(
    borderSide: borderSide ?? this.borderSide,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  @override
  SoftInputBorder scale(double t) => SoftInputBorder(
    borderSide: borderSide.scale(t),
    borderRadius: borderRadius * t,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is SoftInputBorder) {
      return SoftInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is SoftInputBorder) {
      return SoftInputBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(
        borderRadius
            .resolve(textDirection)
            .toRRect(rect)
            .deflate(borderSide.strokeInset),
      );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.resolve(textDirection).toRRect(rect));

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) {
    if (borderSide.style == BorderStyle.none || borderSide.width == 0) return;
    final rrect = borderRadius
        .resolve(textDirection)
        .toRRect(rect)
        .deflate(borderSide.strokeInset);
    canvas.drawRRect(rrect, borderSide.toPaint());
  }

  @override
  bool operator ==(Object other) =>
      other is SoftInputBorder &&
      other.borderSide == borderSide &&
      other.borderRadius == borderRadius;

  @override
  int get hashCode => Object.hash(borderSide, borderRadius);
}
