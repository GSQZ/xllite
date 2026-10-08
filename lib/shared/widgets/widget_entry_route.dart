import 'package:flutter/services.dart';

/// The tab a launch asked for, e.g. tapping the timetable widget.
///
/// Read once and forgotten: opening the app from the launcher afterwards
/// must not jump to the same tab again.
abstract final class WidgetEntryRoute {
  static const _channel = MethodChannel('xinli_lite/widgets');

  static VoidCallback? onAvailable;
  static bool _listening = false;

  static void listen(VoidCallback callback) {
    onAvailable = callback;
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'routeAvailable') onAvailable?.call();
    });
  }

  static Future<String?> take() async {
    try {
      final route = await _channel.invokeMethod<String>('initialRoute');
      return (route == null || route.isEmpty) ? null : route;
    } on Object {
      return null;
    }
  }
}
