import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../card/card_page.dart';
import '../home/home_page.dart';
import '../schedule/schedule_page.dart';
import '../settings/settings_page.dart';
import '../../ui/xl_widgets.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _pages = [
    HomePage(),
    SchedulePage(),
    CardPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: XLBottomNav(
        currentIndex: _index,
        onSelected: (index) => setState(() => _index = index),
        items: const [
          XLBottomNavItem(
            icon: LucideIcons.house,
            activeIcon: LucideIcons.house500,
            label: '首页',
          ),
          XLBottomNavItem(
            icon: LucideIcons.calendarDays,
            activeIcon: LucideIcons.calendarDays500,
            label: '课表',
          ),
          XLBottomNavItem(
            icon: LucideIcons.creditCard,
            activeIcon: LucideIcons.creditCard500,
            label: '校园卡',
          ),
          XLBottomNavItem(
            icon: LucideIcons.userRound,
            activeIcon: LucideIcons.userRound500,
            label: '我的',
          ),
        ],
      ),
    );
  }
}
