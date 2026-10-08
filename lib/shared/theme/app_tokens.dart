import 'package:flutter/material.dart';

/// 4pt spacing scale. Use these instead of ad-hoc numbers.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Horizontal page padding; narrower phones get a tighter gutter.
  static double gutterFor(double width) => width < 360 ? lg : xl;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;

  /// Text fields and full-width buttons.
  static const double control = 14;
  static const double lg = 16;
  static const double xl = 24;
}

abstract final class AppSizes {
  /// Height of primary form controls (text fields and full-width buttons).
  static const double control = 54;

  /// Minimum interactive area for icon buttons and text actions.
  static const double touchTarget = 48;

  /// Readable column width for forms on tablets and landscape phones.
  static const double contentMaxWidth = 440;
}

/// Motion tokens. Every animation in the app picks from these.
abstract final class AppMotion {
  /// Micro feedback: press scale, icon swaps, color changes.
  static const Duration short = Duration(milliseconds: 150);

  /// Component state changes: banners, button content, size changes.
  static const Duration medium = Duration(milliseconds: 250);

  /// Screen-level changes: gate switches, overlays.
  static const Duration long = Duration(milliseconds: 400);

  /// Staggered entrance of a whole screen.
  static const Duration entrance = Duration(milliseconds: 700);

  /// Screen hand-off in the auth gate. The outgoing screen recedes during
  /// the first [handoffExitFraction]; the rest only keeps it mounted.
  static const Duration handoff = Duration(milliseconds: 420);
  static const double handoffExitFraction = 0.5;

  /// How long an incoming screen waits before its own entrance, so it
  /// overlaps the tail of the previous screen's exit without a blank gap.
  static const Duration entranceDelay = Duration(milliseconds: 120);

  /// Home entrance (more sections than the login screen).
  static const Duration homeEntrance = Duration(milliseconds: 820);

  /// Bottom-tab fade-through.
  static const Duration tabSwitch = Duration(milliseconds: 300);

  /// Numbers counting up to their value (balance, electricity).
  static const Duration countUp = Duration(milliseconds: 900);

  /// Error shake on the login form.
  static const Duration shake = Duration(milliseconds: 420);

  /// Things that appear.
  static const Curve curve = Curves.easeOutCubic;

  /// Things that leave.
  static const Curve exit = Curves.easeInCubic;

  /// Things that move or change size while staying on screen.
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// Small celebratory pop (success badge only).
  static const Curve pop = Curves.easeOutBack;

  /// Honors the system "reduce motion" / "remove animations" setting.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Brand and status colors not covered by [ColorScheme].
abstract final class AppColors {
  /// Campus blue: calm, legible in both themes, not tied to any official mark.
  static const Color seed = Color(0xFF1D6FD8);
}

/// Hues for feature entry icons, so the quick-entry grid scans at a glance.
/// Used only as icon tint + 12% (dark 22%) tinted backdrop, never for text.
enum EntryHue {
  blue(Color(0xFF1D6FD8), Color(0xFF8AB4FF)),
  indigo(Color(0xFF5B5BD6), Color(0xFFB2B0FF)),
  teal(Color(0xFF0B8586), Color(0xFF6FD6D2)),
  amber(Color(0xFFB86E00), Color(0xFFFFC266));

  const EntryHue(this.light, this.dark);
  final Color light, dark;

  Color of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Warning/success tones for banners, kept alongside the Material scheme.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
  });

  static const light = StatusColors(
    warning: Color(0xFF8A5A00),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFFF1D1),
    onWarningContainer: Color(0xFF4A3000),
    success: Color(0xFF1B7F4B),
    successContainer: Color(0xFFD9F5E3),
    onSuccessContainer: Color(0xFF00391D),
  );

  static const dark = StatusColors(
    warning: Color(0xFFFFC65C),
    onWarning: Color(0xFF462B00),
    warningContainer: Color(0xFF4A3410),
    onWarningContainer: Color(0xFFFFE2A8),
    success: Color(0xFF7DDBA3),
    successContainer: Color(0xFF0F4D2C),
    onSuccessContainer: Color(0xFFB9F2CD),
  );

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;

  static StatusColors of(BuildContext context) =>
      Theme.of(context).extension<StatusColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  StatusColors copyWith({
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
  }) => StatusColors(
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    success: success ?? this.success,
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
  );

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    return StatusColors(
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
    );
  }
}
