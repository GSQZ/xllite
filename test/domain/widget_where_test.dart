import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/campus/campus.dart';

void main() {
  group('WidgetSnapshotBuilder.widgetWhere', () {
    test('turns the school\'s bracket groups into a readable line', () {
      const cases = {
        '【10号实验楼】软件开发实验室【101】': '10号实验楼 · 软件开发实验室 · 101',
        '【10号实验楼】软件开发实验室【101】教室': '10号实验楼 · 软件开发实验室 · 101',
        '【1号教学楼】机房【A301】': '1号教学楼 · 机房 · A301',
        '【工科实训楼】实训室【C204】【C204】': '工科实训楼 · 实训室 · C204',
      };
      cases.forEach((raw, want) {
        expect(WidgetSnapshotBuilder.widgetWhere(raw), want, reason: raw);
      });
    });

    test('leaves a plain room alone', () {
      for (final raw in const ['教3-201', '9#312', 'A305', '101']) {
        expect(WidgetSnapshotBuilder.widgetWhere(raw), raw);
      }
    });

    test('handles empty and whitespace', () {
      expect(WidgetSnapshotBuilder.widgetWhere(''), '');
      expect(WidgetSnapshotBuilder.widgetWhere('   '), '');
      expect(WidgetSnapshotBuilder.widgetWhere('  教1-105  '), '教1-105');
    });

    test('a building with no room keeps its name', () {
      expect(WidgetSnapshotBuilder.widgetWhere('【10号实验楼】'), '10号实验楼');
      expect(
        WidgetSnapshotBuilder.widgetWhere('【10号实验楼】实验室'),
        '10号实验楼 · 实验室',
      );
    });

    test('sheds the middle when the line would not fit', () {
      final long = WidgetSnapshotBuilder.widgetWhere(
        '【3号实验楼】计算机科学与技术学院软件工程专业实验室【B区305】',
        maxRoomChars: 16,
      );
      // Building and room survive; only the middle name is dropped.
      expect(long, '3号实验楼 · B区305');
      expect(long.runes.length, lessThanOrEqualTo(16));
    });
  });
}
