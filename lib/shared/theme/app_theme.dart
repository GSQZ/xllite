import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'soft_input_border.dart';

export 'app_tokens.dart';

abstract final class AppTheme {
  static ThemeData light({Color seed = AppColors.seed}) =>
      _build(Brightness.light, seed);
  static ThemeData dark({Color seed = AppColors.seed}) =>
      _build(Brightness.dark, seed);

  static ThemeData _build(Brightness brightness, Color seed) {
    final generated = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    // The generated light primary runs heavy; the seed itself is friendlier
    // and every offered seed passes 4.5:1 with white text.
    final scheme = brightness == Brightness.light
        ? generated.copyWith(primary: seed)
        : generated;
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = _textTheme(base.textTheme);
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
    );
    const controlPadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.xl,
      vertical: AppSpacing.md,
    );

    InputBorder border(Color color, [double width = 1]) => SoftInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
      borderSide: color == Colors.transparent
          ? BorderSide.none
          : BorderSide(color: color, width: width),
    );

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [
        brightness == Brightness.dark ? StatusColors.dark : StatusColors.light,
      ],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: text.titleMedium?.copyWith(color: scheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Soft, borderless fields; a ring appears only on focus or error.
        fillColor: brightness == Brightness.light
            ? scheme.surfaceContainerHigh.withValues(alpha: 0.72)
            : scheme.surfaceContainerHigh,
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm + 1,
          AppSpacing.lg,
          AppSpacing.sm + 1,
        ),
        border: border(Colors.transparent),
        enabledBorder: border(Colors.transparent),
        focusedBorder: border(scheme.primary, 1.6),
        errorBorder: border(scheme.error.withValues(alpha: 0.7), 1.2),
        focusedErrorBorder: border(scheme.error, 1.6),
        disabledBorder: border(Colors.transparent),
        prefixIconColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.error)) return scheme.error;
          if (states.contains(WidgetState.focused)) return scheme.primary;
          return scheme.onSurfaceVariant;
        }),
        suffixIconColor: scheme.onSurfaceVariant,
        labelStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
          final color = states.contains(WidgetState.error)
              ? scheme.error
              : states.contains(WidgetState.focused)
              ? scheme.primary
              : scheme.onSurfaceVariant;
          return TextStyle(color: color);
        }),
        errorStyle: text.bodySmall?.copyWith(color: scheme.error),
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, AppSizes.control),
          padding: controlPadding,
          shape: controlShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, AppSizes.control),
          padding: controlPadding,
          shape: controlShape,
          textStyle: text.labelLarge,
          // Secondary actions read as neutral surfaces, not a second accent.
          foregroundColor: scheme.onSurface,
          backgroundColor: brightness == Brightness.light
              ? scheme.surfaceContainerLowest
              : scheme.surfaceContainerLow,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(AppSizes.touchTarget, AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppSizes.touchTarget, AppSizes.touchTarget),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) => base.copyWith(
    headlineSmall: base.headlineSmall?.copyWith(
      fontSize: 26,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.35,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),
    titleSmall: base.titleSmall?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
    bodySmall: base.bodySmall?.copyWith(fontSize: 12, height: 1.5),
    labelLarge: base.labelLarge?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.25,
    ),
  );
}
