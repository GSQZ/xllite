import 'package:flutter/material.dart';

import '../../../shared/widgets/state_panel.dart';

/// Honest stand-in for feature screens that are not built yet, so no entry
/// on the home screen is a dead button.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.title, this.message});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: StatePanel(
          icon: Icons.construction_rounded,
          title: '页面开发中',
          message: message ?? '「$title」即将上线，敬请期待。',
        ),
      ),
    );
  }
}
