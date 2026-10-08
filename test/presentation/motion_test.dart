import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/shared/widgets/motion.dart';

import '../support/fakes.dart';

double _shakeOffset(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find
        .descendant(
          of: find.byType(ShakeTransition),
          matching: find.byType(Transform),
        )
        .first,
  );
  return transform.transform.getTranslation().x;
}

List<String> _recordHaptics(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

Future<void> _failSignIn(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login.username')), '20230001');
  await tester.enterText(find.byKey(const Key('login.password')), 'wrong');
  await tester.tap(find.byKey(const Key('login.submit')));
  await tester.pump();
  await tester.pump();
}

FakeAuthRepository _rejecting() =>
    FakeAuthRepository()
      ..onSignIn = (_) async =>
          throw const AuthFailure(AuthFailureKind.rejected, '学号或密码错误');

void main() {
  testWidgets('rejected sign-in shakes the form and settles at rest', (
    tester,
  ) async {
    final haptics = _recordHaptics(tester);
    await pumpTestApp(tester, repository: _rejecting());

    await _failSignIn(tester);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_shakeOffset(tester).abs(), greaterThan(1));
    expect(haptics, contains('HapticFeedbackType.mediumImpact'));

    await tester.pumpAndSettle();
    expect(_shakeOffset(tester), moreOrLessEquals(0, epsilon: 0.01));
  });

  testWidgets('empty submit also shakes', (tester) async {
    await pumpTestApp(tester);
    final submit = find.byKey(const Key('login.submit'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pump(); // first tick only records the start time
    await tester.pump(const Duration(milliseconds: 60));
    expect(_shakeOffset(tester).abs(), greaterThan(1));
    await tester.pumpAndSettle();
  });

  testWidgets('reduce motion: no entrance delay, no shake, haptic kept', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final haptics = _recordHaptics(tester);

    final app = TestApp(_rejecting());
    await tester.pumpWidget(app.build());
    await tester.pump();
    await tester.pump();

    // Every staggered section is fully visible on the first frames.
    final fades = tester.widgetList<FadeTransition>(
      find.descendant(
        of: find.byType(StaggeredReveal),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fades, isNotEmpty);
    expect(fades.every((f) => f.opacity.value == 1), isTrue);

    await _failSignIn(tester);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_shakeOffset(tester), 0);
    expect(haptics, contains('HapticFeedbackType.mediumImpact'));
  });
}
