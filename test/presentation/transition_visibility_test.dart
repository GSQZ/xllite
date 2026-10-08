import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/campus_fakes.dart';
import '../support/fakes.dart';

/// Product of every Opacity above [finder]: what the user actually sees.
double visibleOpacity(WidgetTester tester, Finder finder) {
  var value = 1.0;
  for (final o in tester.widgetList<Opacity>(
    find.ancestor(of: finder, matching: find.byType(Opacity)),
  )) {
    value *= o.opacity;
  }
  return value;
}

void main() {
  testWidgets('electricity sheet: a switched-in view ends fully visible', (
    tester,
  ) async {
    final app = await pumpTestApp(
      tester,
      repository: FakeAuthRepository(stored: testSession()),
    );
    unawaited(app.campus.loadElectricity('9#312'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entry.electricity')));
    await tester.pumpAndSettle();
    expect(
      visibleOpacity(tester, find.byKey(const Key('electricity.room'))),
      1,
    );

    await tester.tap(find.byKey(const Key('electricity.room')));
    await tester.pumpAndSettle();
    // Nothing else rebuilds the sheet: the new view must still reach 1.
    expect(visibleOpacity(tester, find.byKey(const Key('room.input'))), 1);
  });

  testWidgets('schedule: switching day and view leaves content visible', (
    tester,
  ) async {
    final repo = UiCampusRepository()
      ..onSchedule = (_) async => testCalendarSchedule();
    await pumpTestApp(
      tester,
      repository: FakeAuthRepository(stored: testSession()),
      campusRepository: repo,
    );
    await openTab(tester, '课表');
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();
    expect(visibleOpacity(tester, find.byKey(const Key('schedule.grid'))), 1);
    await tester.tap(find.text('当日'));
    await tester.pumpAndSettle();
    expect(
      visibleOpacity(tester, find.byKey(const Key('schedule.dayList'))),
      1,
    );
  });
}
