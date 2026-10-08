import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/campus/presentation/theme_sheet.dart';
import 'package:xinli_lite/shared/theme/app_theme.dart';
import 'package:xinli_lite/shared/theme/theme_settings.dart';

import '../support/campus_fakes.dart';
import '../support/fakes.dart';

Future<TestApp> _signedIn(WidgetTester tester, {ThemeSettings? theme}) =>
    pumpTestApp(
      tester,
      repository: FakeAuthRepository(stored: testSession()),
      themeSettings: theme,
    );

/// The live MaterialApp, so the test reads the theme it actually built.
MaterialApp _app(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp));

/// The 我的 page's own list (the sheet and pills have scrollables too).
Finder get _mineScroll => find
    .descendant(
      of: find.byKey(const Key('mine.scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

/// Opens 我的 and taps the 主题与外观 row, scrolling it into view first.
Future<void> _openSheet(WidgetTester tester) async {
  await openTab(tester, '我的');
  final row = find.byKey(const Key('mine.theme'));
  if (!tester.any(find.byKey(const Key('theme.skin.campusBlue')))) {
    await tester.scrollUntilVisible(row, 160, scrollable: _mineScroll);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
  }
}

void main() {
  group('ThemeSettings.load', () {
    test('falls back to 校园蓝 and following the system', () async {
      final settings = await ThemeSettings.load(MemoryThemeStore());
      expect(settings.skin, ThemeSkin.campusBlue);
      expect(settings.mode, ThemeMode.system);
    });

    test('reads a saved choice back', () async {
      final settings = await ThemeSettings.load(
        MemoryThemeStore('{"skin":"lakeTeal","mode":"dark"}'),
      );
      expect(settings.skin, ThemeSkin.lakeTeal);
      expect(settings.mode, ThemeMode.dark);
    });

    test('a corrupt or unknown value never blocks launch', () async {
      for (final raw in ['not json at all', '{}', '{"skin":"neon"}', '[]']) {
        final settings = await ThemeSettings.load(MemoryThemeStore(raw));
        expect(settings.skin, ThemeSkin.campusBlue, reason: raw);
        expect(settings.mode, ThemeMode.system, reason: raw);
      }
    });

    test('writes the choice as it changes', () async {
      final store = MemoryThemeStore();
      final settings = await ThemeSettings.load(store);
      settings.setSkin(ThemeSkin.ink);
      await Future<void>.delayed(Duration.zero);
      expect(await store.read(), '{"skin":"ink","mode":"system"}');
    });

    test('every skin is distinct, labelled, and readable on white', () {
      final colours = ThemeSkin.values.map((s) => s.color).toSet();
      expect(colours.length, ThemeSkin.values.length);
      for (final skin in ThemeSkin.values) {
        expect(skin.label.trim(), isNotEmpty);
        // Button labels are 16sp semibold, so the large-text rule applies:
        // white on the light primary clears 3:1 for every skin.
        expect(
          _contrast(skin.color, Colors.white),
          greaterThanOrEqualTo(3),
          reason: skin.name,
        );
      }
      expect(ThemeSkin.campusBlue.color, AppColors.seed);
    });
  });

  testWidgets('默认跟随系统，用校园蓝', (tester) async {
    await _signedIn(tester);
    final app = _app(tester);
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme!.colorScheme.primary, ThemeSkin.campusBlue.color);
  });

  testWidgets('我的 shows the skin name and opens the picker', (tester) async {
    await _signedIn(tester);
    await openTab(tester, '我的');
    expect(find.text('主题与外观'), findsOneWidget);
    expect(find.text('校园蓝'), findsOneWidget);

    await _openSheet(tester);
    for (final skin in ThemeSkin.values) {
      expect(
        find.byKey(Key('theme.skin.${skin.name}')),
        findsOneWidget,
        reason: skin.name,
      );
    }
    // The mode switch stays out of the UI.
    expect(find.text('跟随系统'), findsNothing);
    expect(find.text('深色'), findsNothing);
  });

  testWidgets('picking a skin repaints the app and persists', (tester) async {
    final store = MemoryThemeStore();
    final theme = ThemeSettings(store);
    await _signedIn(tester, theme: theme);
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('theme.skin.rouge')));
    await tester.pumpAndSettle();

    expect(theme.skin, ThemeSkin.rouge);
    expect(_app(tester).theme!.colorScheme.primary, ThemeSkin.rouge.color);
    expect(store.value, '{"skin":"rouge","mode":"system"}');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the preview redraws in the chosen skin', (tester) async {
    await _signedIn(tester);
    await _openSheet(tester);
    expect(find.byType(SkinPreview), findsOneWidget);

    Color primaryInPreview() {
      final swatch = find
          .descendant(
            of: find.byType(SkinPreview),
            matching: find.byKey(const Key('skinned.primary')),
          )
          .first;
      final box = tester.widget<Container>(
        find.descendant(of: swatch, matching: find.byType(Container)).first,
      );
      return (box.decoration as BoxDecoration).color!;
    }

    expect(primaryInPreview(), ThemeSkin.campusBlue.color);
    await tester.tap(find.byKey(const Key('theme.skin.ink')));
    await tester.pumpAndSettle();
    expect(primaryInPreview(), ThemeSkin.ink.color);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stored skin survives a restart', (tester) async {
    final theme = await ThemeSettings.load(
      MemoryThemeStore('{"skin":"pineGreen","mode":"light"}'),
    );
    await _signedIn(tester, theme: theme);

    expect(_app(tester).themeMode, ThemeMode.light);
    expect(_app(tester).theme!.colorScheme.primary, ThemeSkin.pineGreen.color);
    await openTab(tester, '我的');
    expect(find.text('松绿'), findsOneWidget);
  });

  testWidgets('恢复默认皮肤 returns to 校园蓝', (tester) async {
    final store = MemoryThemeStore('{"skin":"coffee","mode":"system"}');
    final theme = await ThemeSettings.load(store);
    await _signedIn(tester, theme: theme);
    await _openSheet(tester);

    // Start from a different skin so the reset actually changes something.
    await tester.tap(find.byKey(const Key('theme.skin.ink')));
    await tester.pumpAndSettle();
    expect(theme.skin, ThemeSkin.ink);

    final reset = find.byKey(const Key('theme.reset'));
    await tester.scrollUntilVisible(reset, 160, scrollable: pageScrollable);
    await tester.tap(reset);
    await tester.pumpAndSettle();

    expect(theme.skin, ThemeSkin.campusBlue);
    expect(store.value, '{"skin":"campusBlue","mode":"system"}');
  });

  testWidgets('the picker fits a small phone at 2× text', (tester) async {
    useSmallScreen(tester, textScale: 2);
    await _signedIn(tester);
    await _openSheet(tester);
    expect(tester.takeException(), isNull);

    final ember = find.byKey(const Key('theme.skin.ember'));
    await tester.scrollUntilVisible(ember, 160, scrollable: pageScrollable);
    await tester.pumpAndSettle();
    await tester.tap(ember);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

/// WCAG relative-luminance contrast ratio.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
