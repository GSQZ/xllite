import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'theme_skin.dart';

export 'theme_skin.dart';

/// Where the choice is kept between launches.
abstract interface class ThemeStore {
  Future<String?> read();
  Future<void> write(String value);
}

/// Device storage (the platform keystore the app already uses).
class SecureThemeStore implements ThemeStore {
  const SecureThemeStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _key = 'xinli.theme.v1';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

/// In-memory store for tests and previews.
class MemoryThemeStore implements ThemeStore {
  MemoryThemeStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

/// The user's skin, and the light/dark mode the app follows it in.
///
/// Changes apply at once and are saved in the background; a failed save
/// never undoes the choice on screen.
class ThemeSettings extends ChangeNotifier {
  ThemeSettings(this._store, {this.skin = defaultSkin, this.mode = ThemeMode.system});

  final ThemeStore _store;

  /// The chosen skin.
  ThemeSkin skin;

  /// Light or dark. There is no in-app switch: the app follows the system.
  ThemeMode mode;

  /// Reads the saved choice; anything missing or unreadable falls back to
  /// the defaults, so launch is never blocked by storage.
  static Future<ThemeSettings> load(ThemeStore store) async {
    final settings = ThemeSettings(store);
    try {
      final raw = await store.read();
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        settings.skin = ThemeSkin.values.firstWhere(
          (s) => s.name == json['skin'],
          orElse: () => defaultSkin,
        );
        settings.mode = ThemeMode.values.firstWhere(
          (m) => m.name == json['mode'],
          orElse: () => ThemeMode.system,
        );
      }
    } catch (_) {
      /* Defaults. */
    }
    return settings;
  }

  void setSkin(ThemeSkin value) {
    if (value == skin) return;
    skin = value;
    notifyListeners();
    _save();
  }

  void _save() => _store
      .write(jsonEncode({'skin': skin.name, 'mode': mode.name}))
      .catchError((Object _) {});

  /// Kept for a future 跟随系统 / 浅色 / 深色 switch; nothing calls it yet.
  void setMode(ThemeMode value) {
    if (value == mode) return;
    mode = value;
    notifyListeners();
    _save();
  }
}

/// Gives descendants the app's [ThemeSettings].
class ThemeScope extends InheritedNotifier<ThemeSettings> {
  const ThemeScope({
    super.key,
    required ThemeSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static ThemeSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()!.notifier!;

  static ThemeSettings? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.notifier;
}
