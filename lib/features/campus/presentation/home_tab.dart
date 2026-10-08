import 'package:flutter/material.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/status_banner.dart';
import 'campus_format.dart';
import 'card_page.dart';
import 'course_card.dart';
import 'exams_page.dart';
import 'grades_page.dart';
import 'quick_entries.dart';
import 'section_parts.dart';
import 'signed_in_memo.dart';
import 'today_timeline.dart';

/// Everything the home tab reads, captured in one consistent frame.
class _HomeView {
  const _HomeView({
    required this.home,
    required this.balance,
    required this.electricity,
    required this.room,
  });

  final HomeSnapshot home;
  final ResourceState<List<CardAccount>> balance;
  final ResourceState<ElectricityAccount> electricity;
  final String? room;
}

class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.auth,
    required this.campus,
    required this.entrance,
    required this.onRefresh,
    required this.onOpenSchedule,
    required this.onCovered,
    required this.onSetRoom,
  });

  final AuthController auth;
  final CampusController campus;

  /// Drives the staggered entrance; owned by the shell.
  final Animation<double> entrance;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenSchedule;

  /// A feature page opened over (true) or closed from (false) the home tab.
  final ValueChanged<bool> onCovered;
  final VoidCallback onSetRoom;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late final Listenable _listenable;
  final _memo = SignedInMemo<_HomeView>();

  CampusController get _campus => widget.campus;

  @override
  void initState() {
    super.initState();
    _listenable = Listenable.merge([
      widget.auth,
      _campus.home,
      _campus.balance,
      _campus.electricity,
    ]);
  }

  _HomeView _read() => _memo.read(
    signedIn: widget.auth.state.isAuthenticated,
    live: () => _HomeView(
      home: _campus.home.state,
      balance: _campus.balance.state,
      electricity: _campus.electricity.state,
      room: _campus.roomQuery,
    ),
  );

  /// Entrance: starts as the previous screen is mostly gone, then reveals
  /// top-down 45ms apart, each section rising 12px over ~370ms.
  Widget _reveal(int step, Widget child, {double scaleFrom = 1}) =>
      StaggeredReveal(
        animation: widget.entrance,
        step: step,
        delay:
            AppMotion.entranceDelay.inMilliseconds /
            AppMotion.homeEntrance.inMilliseconds,
        stepFraction: 0.055,
        window: 0.45,
        offset: 12,
        scaleFrom: scaleFrom,
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _listenable,
      builder: (context, _) => _build(context, _read()),
    );
  }

  Widget _build(BuildContext context, _HomeView view) {
    final home = view.home;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = AppSpacing.gutterFor(width);
    final authFailure = widget.auth.state.isAuthenticated
        ? widget.auth.state.failure
        : null;

    final children = <Widget>[
      _reveal(0, _Header(snapshot: home)),
      if (authFailure != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: StatusBanner(
            tone: StatusTone.warning,
            title: '登录状态暂未刷新',
            message: '${authFailure.message}\n当前登录仍然有效，可继续使用。',
            onDismiss: widget.auth.clearFailure,
          ),
        ),
      const SizedBox(height: AppSpacing.xl),
      _reveal(
        1,
        scaleFrom: 0.98,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CourseCard(
              snapshot: home,
              onRetry: _campus.home.load,
              onOpenSchedule: widget.onOpenSchedule,
            ),
            if (home.schedule.isStale)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.md,
                  left: AppSpacing.xs,
                ),
                child: StaleNote(
                  text:
                      '${updatedText(home.schedule.updatedAt, home.now)} · 刷新失败，下拉重试',
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      QuickEntries(
        data: QuickEntryData(
          exams: home.exams,
          upcomingExamCount: home.upcomingExams.length,
          undatedExamCount: home.undatedExams.length,
          balance: view.balance,
          electricity: view.electricity,
          room: view.room,
        ),
        gradesPage: (_) => GradesPage(auth: widget.auth, campus: _campus),
        examsPage: (_) => ExamsPage(auth: widget.auth, campus: _campus),
        cardPage: (_) => CardPage(auth: widget.auth, campus: _campus),
        onPageOpen: () => widget.onCovered(true),
        onPageClosed: () => widget.onCovered(false),
        onElectricity: widget.onSetRoom,
        wrap: (index, tile) => _reveal(2 + index, tile),
      ),
      if (hasTimeline(home.day)) ...[
        const SizedBox(height: AppSpacing.xxl),
        _reveal(6, TodayTimeline(day: home.day!, now: home.now)),
      ],
      const SizedBox(height: AppSpacing.xxl),
    ];

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      edgeOffset: MediaQuery.paddingOf(context).top,
      child: ListView(
        key: const Key('home.scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          gutter,
          MediaQuery.paddingOf(context).top + AppSpacing.lg,
          gutter,
          // Clears the glass navigation bar the content scrolls under.
          AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.snapshot});

  final HomeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fullName = snapshot.profile.data?.name.trim() ?? '';
    final name = fullName.isEmpty ? '' : '${fullName.characters.first}同学';
    final greeting = greetingFor(snapshot.now);
    final titleStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          label: name.isEmpty ? greeting : '$greeting，$name',
          excludeSemantics: true,
          child: AnimatedSwitcher(
            duration: AppMotion.medium,
            layoutBuilder: (current, previous) => Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [...previous, ?current],
            ),
            // Wrap units: a narrow screen breaks after the comma, never
            // inside the name.
            child: Wrap(
              key: ValueKey(name),
              children: [
                Text(name.isEmpty ? greeting : '$greeting，', style: titleStyle),
                if (name.isNotEmpty) Text(name, style: titleStyle),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          dateLine(snapshot.now, week: snapshot.day?.week),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
