import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';

final appThemeControllerProvider =
    AsyncNotifierProvider<AppThemeController, AppThemeSettings>(
      AppThemeController.new,
    );

enum AppThemeModeChoice {
  system('跟随系统', ThemeMode.system),
  light('浅色', ThemeMode.light),
  dark('深色', ThemeMode.dark);

  const AppThemeModeChoice(this.label, this.themeMode);

  final String label;
  final ThemeMode themeMode;
}

enum AppThemeColorChoice {
  teal('青绿', Color(0xFF0F766E)),
  blue('蓝色', Color(0xFF2563EB)),
  violet('紫色', Color(0xFF7C3AED)),
  rose('玫红', Color(0xFFE11D48)),
  orange('橙色', Color(0xFFD97706));

  const AppThemeColorChoice(this.label, this.color);

  final String label;
  final Color color;
}

class AppThemeSettings {
  const AppThemeSettings({required this.mode, required this.color});

  static const defaults = AppThemeSettings(
    mode: AppThemeModeChoice.system,
    color: AppThemeColorChoice.teal,
  );

  final AppThemeModeChoice mode;
  final AppThemeColorChoice color;

  ThemeMode get themeMode => mode.themeMode;
  Color get seedColor => color.color;

  AppThemeSettings copyWith({
    AppThemeModeChoice? mode,
    AppThemeColorChoice? color,
  }) {
    return AppThemeSettings(
      mode: mode ?? this.mode,
      color: color ?? this.color,
    );
  }
}

class AppThemeController extends AsyncNotifier<AppThemeSettings> {
  static const _modeKey = 'theme_mode';
  static const _colorKey = 'theme_color';

  @override
  Future<AppThemeSettings> build() async {
    final storage = ref.watch(secureStorageProvider);
    final modeName = await storage.read(key: _modeKey);
    final colorName = await storage.read(key: _colorKey);

    return AppThemeSettings(
      mode: AppThemeModeChoice.values.firstWhere(
        (item) => item.name == modeName,
        orElse: () => AppThemeSettings.defaults.mode,
      ),
      color: AppThemeColorChoice.values.firstWhere(
        (item) => item.name == colorName,
        orElse: () => AppThemeSettings.defaults.color,
      ),
    );
  }

  Future<void> setMode(AppThemeModeChoice mode) async {
    final current = state.maybeWhen(
      data: (value) => value,
      orElse: () => AppThemeSettings.defaults,
    );
    final next = current.copyWith(mode: mode);
    state = AsyncData(next);
    await ref
        .read(secureStorageProvider)
        .write(key: _modeKey, value: mode.name);
  }

  Future<void> setColor(AppThemeColorChoice color) async {
    final current = state.maybeWhen(
      data: (value) => value,
      orElse: () => AppThemeSettings.defaults,
    );
    final next = current.copyWith(color: color);
    state = AsyncData(next);
    await ref
        .read(secureStorageProvider)
        .write(key: _colorKey, value: color.name);
  }
}
