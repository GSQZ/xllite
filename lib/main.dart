import 'package:flutter/widgets.dart';

import 'app.dart';
import 'shared/theme/theme_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read before the first frame so the app never flashes the default colour.
  final theme = await ThemeSettings.load(const SecureThemeStore());
  runApp(XinliApp(themeSettings: theme));
}
