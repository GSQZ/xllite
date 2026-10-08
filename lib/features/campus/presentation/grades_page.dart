import 'package:flutter/material.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/state_panel.dart';
import 'accent_panel.dart';
import 'campus_format.dart';
import 'detail_sheet.dart';
import 'feature_page.dart';
import 'section_parts.dart';
import 'signed_in_memo.dart';

/// Grades for every term from one request. Choosing a term only filters on
/// screen; its GPA comes from the backend's per-term summary, never from a
/// local calculation. Text grades ("优秀", "缓考") are shown as written.
class GradesPage extends StatefulWidget {
  const GradesPage({super.key, required this.auth, required this.campus});

  final AuthController auth;
  final CampusController campus;

  @override
  State<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> {
  late final Listenable _listenable = Listenable.merge([
    widget.auth,
    widget.campus.grades,
  ]);
  final _memo = SignedInMemo<ResourceState<Grades>>();

  /// Null shows all terms.
  String? _term;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.campus.loadGrades();
    });
  }

  Future<void> _refresh() => widget.campus.loadGrades(refresh: true);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _listenable,
      builder: (context, _) {
        final state = _memo.read(
          signedIn: widget.auth.state.isAuthenticated,
          live: () => widget.campus.grades.state,
        );
        return FeaturePage(
          title: '成绩',
          scrollKey: const Key('grades.scroll'),
          onRefresh: _refresh,
          children: _content(context, state),
        );
      },
    );
  }

  List<Widget> _content(BuildContext context, ResourceState<Grades> state) {
    final grades = state.data;
    if (grades == null) {
      final failure = state.failure;
      if (failure != null && !state.isLoading) {
        return [
          const SizedBox(height: AppSpacing.xxl),
          StatePanel(
            icon: Icons.cloud_off_rounded,
            tone: PanelTone.error,
            title: '成绩加载失败',
            message: failure.message,
            actions: [
              FilledButton(
                onPressed: () => widget.campus.loadGrades(),
                child: const Text('重试'),
              ),
            ],
          ),
        ];
      }
      return const [_GradesSkeleton()];
    }

    final terms = [...grades.terms]..sort((a, b) => b.term.compareTo(a.term));
    final term = terms.any((t) => t.term == _term) ? _term : null;
    final summary = term == null
        ? grades.summary
        : terms.firstWhere((t) => t.term == term);
    bool inTerm(Grade g) =>
        term == null || g.term == term || g.makeupTerm == term;
    final failedKeys = {for (final g in grades.failedCourses) _key(g)};
    final normal = grades.normalGrades.where(inTerm).toList();
    final makeup = grades.makeupGrades.where(inTerm).toList();
    final failed = grades.failedCourses.where(inTerm).toList();
    final audit = grades.sourceSummary.addedFromGraduationAuditCount;

    return [
      _SummaryPanel(summary: summary, term: term),
      if (state.isStale) ...[
        const SizedBox(height: AppSpacing.md),
        StaleNote(
          text: '${updatedText(state.updatedAt, DateTime.now())} · 刷新失败，下拉重试',
        ),
      ],
      if (terms.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xl),
        ChoicePills<String?>(
          key: const Key('grades.terms'),
          options: [null, ...terms.map((t) => t.term)],
          selected: term,
          label: (t) => t == null ? '全部学期' : termText(t),
          onSelected: (t) => setState(() => _term = t),
        ),
      ],
      if (audit > 0) ...[
        const SizedBox(height: AppSpacing.md),
        _Note(text: '其中 $audit 门成绩来自毕业审核表，可能比教务成绩表更新得早。'),
      ],
      const SizedBox(height: AppSpacing.lg),
      AnimatedSwitcher(
        duration: AppMotion.long,
        switchInCurve: AppMotion.curve,
        switchOutCurve: AppMotion.exit,
        transitionBuilder: fadeThroughTransition,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: Column(
          key: ValueKey(term),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (normal.isEmpty && makeup.isEmpty && failed.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.xxl),
                child: StatePanel(icon: Icons.inbox_outlined, title: '暂无成绩'),
              ),
            if (term == null)
              ..._byTerm(normal, terms, failedKeys)
            else if (normal.isNotEmpty)
              _GradeGroup(grades: normal, failedKeys: failedKeys),
            if (makeup.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: '补考与重修'),
              const SizedBox(height: AppSpacing.sm),
              _GradeGroup(
                grades: makeup,
                failedKeys: failedKeys,
                showTerm: true,
              ),
            ],
            if (failed.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: '未通过课程', trailing: '${failed.length} 门'),
              const SizedBox(height: AppSpacing.sm),
              _GradeGroup(
                grades: failed,
                failedKeys: failedKeys,
                showTerm: true,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      const _Note(
        text: '绩点按课程取最高成绩汇总，由服务端计算。"优秀""缓考"等等级成绩按原文显示，不折算为分数。成绩以教务系统为准。',
      ),
    ];
  }

  List<Widget> _byTerm(
    List<Grade> grades,
    List<GradeSummary> terms,
    Set<String> failedKeys,
  ) {
    final byTerm = <String, List<Grade>>{};
    for (final g in grades) {
      byTerm.putIfAbsent(g.term, () => []).add(g);
    }
    final order = [
      ...terms.map((t) => t.term).where(byTerm.containsKey),
      ...(byTerm.keys.where((k) => !terms.any((t) => t.term == k)).toList()
        ..sort((a, b) => b.compareTo(a))),
    ];
    return [
      for (final key in order) ...[
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.md,
            bottom: AppSpacing.sm,
          ),
          child: SectionHeader(
            title: key.isEmpty ? '未标注学期' : termText(key),
            trailing: _termTrailing(
              terms.where((t) => t.term == key).firstOrNull,
            ),
          ),
        ),
        _GradeGroup(grades: byTerm[key]!, failedKeys: failedKeys),
      ],
    ];
  }

  static String? _termTrailing(GradeSummary? s) {
    if (s == null) return null;
    final gp = s.weightedGradePoint;
    return joinMeta([
      if (gp != null) '绩点 ${gp.toStringAsFixed(2)}',
      '${compactNumber(s.totalCredits)} 学分',
    ]);
  }
}

String _key(Grade g) => g.courseCode.isNotEmpty ? g.courseCode : g.courseName;

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.summary, required this.term});

  final GradeSummary summary;
  final String? term;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gp = summary.weightedGradePoint;
    return AccentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: AppMotion.medium,
            child: Text(
              term == null ? '加权平均绩点 · 全部学期' : '${termText(term!)} · 绩点',
              key: ValueKey(term),
              style: onAccent(context, theme.textTheme.bodyMedium, 0.85),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          CountUpText(
            key: const Key('grades.gpa'),
            value: gp,
            fallback: '—',
            style: onAccent(
              context,
              theme.textTheme.displaySmall,
            )?.copyWith(fontWeight: FontWeight.w700, height: 1.1),
          ),
          if (gp == null)
            Text(
              '暂无可计算绩点的课程',
              style: onAccent(context, theme.textTheme.bodySmall, 0.8),
            ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AccentStat(
                  label: '课程',
                  value: '${summary.courseCount}',
                  unit: '门',
                ),
              ),
              Expanded(
                child: AccentStat(
                  label: '学分',
                  value: compactNumber(summary.totalCredits),
                ),
              ),
              Expanded(
                child: AccentStat(
                  label: '未通过',
                  value: '${summary.failedCourseCount}',
                  unit: '门',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GradeGroup extends StatelessWidget {
  const _GradeGroup({
    required this.grades,
    required this.failedKeys,
    this.showTerm = false,
  });

  final List<Grade> grades;
  final Set<String> failedKeys;
  final bool showTerm;

  @override
  Widget build(BuildContext context) {
    return RowGroup(
      children: [
        for (final g in grades)
          _GradeRow(
            grade: g,
            failed: failedKeys.contains(_key(g)),
            showTerm: showTerm,
          ),
      ],
    );
  }
}

class _GradeRow extends StatelessWidget {
  const _GradeRow({
    required this.grade,
    required this.failed,
    required this.showTerm,
  });

  final Grade grade;
  final bool failed;
  final bool showTerm;

  void _details(BuildContext context) {
    showDetailSheet(
      context,
      title: grade.courseName,
      highlightLabel: '成绩',
      highlight: grade.score.isEmpty ? '—' : grade.score,
      rows: [
        ('学期', termText(grade.term)),
        ('学分', grade.credit),
        ('绩点', grade.gradePoint),
        ('考试性质', grade.examNature),
        ('成绩标识', grade.scoreFlag),
        ('补重学期', termText(grade.makeupTerm)),
        ('课程编号', grade.courseCode),
        ('数据来源', grade.source == 'graduationAudit' ? '毕业审核表' : '教务成绩表'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = joinMeta([
      if (showTerm) termText(grade.term),
      if (grade.credit.isNotEmpty) '${grade.credit} 学分',
      grade.examNature,
    ]);
    return InkWell(
      onTap: () => _details(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(grade.courseName, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (meta.isNotEmpty)
                        Text(
                          meta,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      if (failed) TagChip(label: '未通过', color: scheme.error),
                      if (grade.source == 'graduationAudit')
                        TagChip(label: '毕业审核', color: scheme.primary),
                      if (grade.scoreFlag.isNotEmpty)
                        TagChip(
                          label: grade.scoreFlag,
                          color: StatusColors.of(context).warning,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  grade.score.isEmpty ? '—' : grade.score,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: failed ? scheme.error : scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (grade.gradePoint.isNotEmpty)
                  Text(
                    '绩点 ${grade.gradePoint}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _GradesSkeleton extends StatelessWidget {
  const _GradesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '正在加载成绩',
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Skeleton(height: 168, radius: AppRadius.xl),
          SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Skeleton(width: 84, height: 36, radius: 99),
              SizedBox(width: AppSpacing.sm),
              Skeleton(width: 140, height: 36, radius: 99),
            ],
          ),
          SizedBox(height: AppSpacing.xl),
          Skeleton(height: 64, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.sm),
          Skeleton(height: 64, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.sm),
          Skeleton(height: 64, radius: AppRadius.lg),
        ],
      ),
    );
  }
}
