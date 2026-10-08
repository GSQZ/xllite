import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class XLColors {
  const XLColors._();

  static const page = Color(0xFFF7F8FB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF0F2F7);
  static const ink = Color(0xFF141821);
  static const inkSecondary = Color(0xFF596170);
  static const inkTertiary = Color(0xFF8B93A1);
  static const line = Color(0xFFE1E5EC);
  static const brand = Color(0xFF3467F6);
  static const brandSoft = Color(0xFFE9EEFF);
  static const success = Color(0xFF12A66A);
  static const warning = Color(0xFFD8831B);
  static const danger = Color(0xFFD92D3A);
}

class XLTheme {
  const XLTheme._();

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: false);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: XLColors.brand,
          brightness: Brightness.light,
        ).copyWith(
          primary: XLColors.brand,
          secondary: XLColors.brand,
          surface: XLColors.surface,
          error: XLColors.danger,
          onPrimary: Colors.white,
          onSurface: XLColors.ink,
          onSurfaceVariant: XLColors.inkSecondary,
          outline: XLColors.inkTertiary,
          outlineVariant: XLColors.line,
        );

    final textTheme = base.textTheme.apply(
      bodyColor: XLColors.ink,
      displayColor: XLColors.ink,
      fontFamilyFallback: const [
        'PingFang SC',
        'Hiragino Sans GB',
        'Helvetica Neue',
      ],
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: XLColors.page,
      canvasColor: XLColors.page,
      primaryColor: XLColors.brand,
      splashColor: XLColors.brand.withValues(alpha: 0.06),
      highlightColor: XLColors.brand.withValues(alpha: 0.04),
      iconTheme: const IconThemeData(color: XLColors.inkSecondary, size: 22),
      appBarTheme: const AppBarTheme(
        backgroundColor: XLColors.page,
        foregroundColor: XLColors.ink,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleSpacing: 22,
        titleTextStyle: TextStyle(
          color: XLColors.ink,
          fontSize: 24,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
      textTheme: textTheme.copyWith(
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(
          height: 1.35,
          letterSpacing: 0,
        ),
        bodySmall: textTheme.bodySmall?.copyWith(
          height: 1.35,
          letterSpacing: 0,
        ),
        labelLarge: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      dividerTheme: const DividerThemeData(
        color: XLColors.line,
        thickness: 0.6,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return XLColors.inkTertiary.withValues(alpha: 0.28);
            }
            return XLColors.brand;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: XLColors.brand,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          foregroundColor: const WidgetStatePropertyAll(XLColors.ink),
          side: const WidgetStatePropertyAll(
            BorderSide(color: XLColors.line, width: 1.1),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: XLColors.inkSecondary,
          splashFactory: InkRipple.splashFactory,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: XLColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: const TextStyle(color: XLColors.inkSecondary),
        hintStyle: const TextStyle(color: XLColors.inkTertiary),
        prefixIconColor: XLColors.inkSecondary,
        suffixIconColor: XLColors.inkSecondary,
        border: _inputBorder(XLColors.line),
        enabledBorder: _inputBorder(XLColors.line),
        focusedBorder: _inputBorder(XLColors.brand),
        errorBorder: _inputBorder(XLColors.danger),
        focusedErrorBorder: _inputBorder(XLColors.danger),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: XLColors.page,
        modalBackgroundColor: XLColors.page,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: 1),
    );
  }
}
