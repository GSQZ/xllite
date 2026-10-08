import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/frosted.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/widget_entry_route.dart';
import 'coming_soon_page.dart';
import 'home_tab.dart';
import 'mine_tab.dart';
import 'electricity_sheet.dart';
import 'schedule_tab.dart';

/// Signed-in shell: 首页 / 课表 / 我的.
///
/// Owns the entrance choreography (content reveals top-down while the
/// navigation bar rises), keeps each tab's state, and tells the home
/// controller when its clock should tick: only while the home tab is
/// selected, uncovered and the app is in the foreground.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.auth, required this.campus});

  final AuthController auth;
  final CampusController campus;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final _entrance = AnimationController(
    vsync: this,
    duration: AppMotion.homeEntrance,
  );
  var _tab = 0;
  final _visited = <int>{0};
  var _foreground = true;
  var _covered = false;

  CampusController get _campus => widget.campus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    // Load after the first frame: never during build, and never notifying
    // listeners while the gate is still assembling this screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _campus.home.load();
      _campus.loadBalance();
      _campus.restorePreferences();
      _syncActive();
    });
    WidgetEntryRoute.listen(_takeWidgetRoute);
    _takeWidgetRoute();
  }

  void _takeWidgetRoute() {
    WidgetEntryRoute.take().then((route) {
      if (!mounted || route == null) return;
      if (route == 'schedule') _selectTab(1);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entrance.isDismissed) {
      if (AppMotion.reduced(context)) {
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _takeWidgetRoute();
    if (_foreground && widget.auth.state.isAuthenticated) {
      _campus.home.load();
      _campus.loadBalance();
      final room = _campus.roomQuery;
      if (room != null) _campus.loadElectricity(room);
    }
    _syncActive();
  }

  @override
  void dispose() {
    WidgetEntryRoute.onAvailable = null;
    WidgetsBinding.instance.removeObserver(this);
    _campus.home.setActive(false);
    _entrance.dispose();
    super.dispose();
  }

  void _syncActive() {
    _campus.home.setActive(
      _foreground &&
          !_covered &&
          _tab == 0 &&
          widget.auth.state.isAuthenticated,
    );
  }

  void _selectTab(int index) {
    if (index == _tab) return;
    HapticFeedback.selectionClick();
    _visited.add(index);
    setState(() => _tab = index);
    if (index == 1) {
      _campus.loadSchedule(term: _campus.selectedTerm);
    }
    if (index == 2) _campus.loadProfile();
    _syncActive();
  }

  void _setCovered(bool covered) {
    _covered = covered;
    _syncActive();
  }

  Future<void> _push(Widget page) async {
    _setCovered(true);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) _setCovered(false);
  }

  void _openFeature(String title) => _push(ComingSoonPage(title: title));

  /// First-time room setup; once set, the tile opens the electricity page.
  /// Electricity sheet: reading, room change and top-up in one place.
  Future<void> _setRoom() =>
      showElectricitySheet(context, campus: _campus, auth: widget.auth);

  Future<void> _refreshHome() {
    final room = _campus.roomQuery;
    return Future.wait([
      _campus.home.load(refresh: true),
      _campus.loadBalance(refresh: true),
      if (room != null) _campus.loadElectricity(room, refresh: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // Chrome stays put: the navigation bar only fades in, early, while the
    // content does the moving.
    final navOpacity = _entrance.drive(
      CurveTween(curve: const Interval(0.1, 0.5, curve: AppMotion.curve)),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Content scrolls under the glass navigation bar.
      extendBody: true,
      body: BackdropGroup(
        child: FadeIndexedStack(
          index: _tab,
          children: [
            HomeTab(
              auth: widget.auth,
              campus: _campus,
              entrance: _entrance,
              onRefresh: _refreshHome,
              onOpenSchedule: () => _selectTab(1),
              onCovered: _setCovered,
              onSetRoom: _setRoom,
            ),
            if (_visited.contains(1))
              ScheduleTab(auth: widget.auth, campus: _campus)
            else
              const SizedBox.shrink(),
            if (_visited.contains(2))
              MineTab(
                auth: widget.auth,
                campus: _campus,
                onOpenFeature: _openFeature,
              )
            else
              const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: FadeTransition(
        opacity: navOpacity,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: glassSigma, sigmaY: glassSigma),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: glassFill(context, 1.15),
                border: Border(top: BorderSide(color: glassEdge(context))),
              ),
              child: NavigationBar(
                backgroundColor: Colors.transparent,
                key: const Key('home.nav'),
                selectedIndex: _tab,
                onDestinationSelected: _selectTab,
                animationDuration: AppMotion.long,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: '首页',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    selectedIcon: Icon(Icons.calendar_month_rounded),
                    label: '课表',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: '我的',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
