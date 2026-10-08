import 'package:flutter/material.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/frosted.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/motion.dart';
import 'section_parts.dart';
import 'theme_sheet.dart';
import 'signed_in_memo.dart';

class MineTab extends StatefulWidget {
  const MineTab({
    super.key,
    required this.auth,
    required this.campus,
    required this.onOpenFeature,
  });

  final AuthController auth;
  final CampusController campus;
  final void Function(String title) onOpenFeature;

  @override
  State<MineTab> createState() => _MineTabState();
}

class _MineTabState extends State<MineTab> {
  late final Listenable _listenable = Listenable.merge([
    widget.auth,
    widget.campus.profile,
  ]);
  final _memo = SignedInMemo<ResourceState<StudentProfile>>();

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('将清除本机保存的登录令牌，下次使用需要重新登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('signOut.confirm'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.auth.signOut();
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于新理Lite'),
        content: const Text(
          '面向新疆理工学院学生的民间校园服务应用。\n\n'
          '民间开发版本，不代表学校官方应用。数据来自学校相关系统，请以学校官方系统为准。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _listenable,
      builder: (context, _) {
        final profile = _memo.read(
          signedIn: widget.auth.state.isAuthenticated,
          live: () => widget.campus.profile.state,
        );
        return _build(context, profile);
      },
    );
  }

  Widget _build(BuildContext context, ResourceState<StudentProfile> state) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final top = MediaQuery.paddingOf(context).top;
    final gutter = AppSpacing.gutterFor(MediaQuery.sizeOf(context).width);
    final signingOut = widget.auth.state.phase == AuthPhase.signingOut;
    final profile = state.data;
    final username = widget.auth.state.session?.username ?? '';

    return ListView(
      key: const Key('mine.scroll'),
      padding: EdgeInsets.fromLTRB(
        gutter,
        top + AppSpacing.xl,
        gutter,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProfileHeader(state: state, fallbackId: username),
                if (profile == null &&
                    state.failure != null &&
                    !state.isLoading) ...[
                  const SizedBox(height: AppSpacing.lg),
                  InlineFailure(
                    message: state.failure!.message,
                    onRetry: () => widget.campus.loadProfile(),
                  ),
                ],
                if (profile != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _Group(
                    children: [
                      _InfoRow(label: '学院', value: profile.college),
                      _InfoRow(label: '专业', value: profile.major),
                      _InfoRow(label: '班级', value: profile.className),
                      _InfoRow(label: '年级', value: profile.grade),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _Group(
                  children: [
                    _LinkRow(
                      icon: Icons.workspace_premium_outlined,
                      label: '毕业情况',
                      onTap: () => widget.onOpenFeature('毕业情况'),
                    ),
                    _LinkRow(
                      key: const Key('mine.theme'),
                      icon: Icons.palette_outlined,
                      label: '主题与外观',
                      trailing: const ThemeSummary(),
                      onTap: () => showThemeSheet(context),
                    ),
                    _LinkRow(
                      icon: Icons.info_outline_rounded,
                      label: '关于新理Lite',
                      onTap: _showAbout,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                AppButton(
                  key: const Key('mine.signOut'),
                  variant: AppButtonVariant.outlined,
                  destructive: true,
                  icon: Icons.logout_rounded,
                  label: '退出登录',
                  loading: signingOut,
                  loadingLabel: '正在退出…',
                  onPressed: signingOut ? null : _confirmSignOut,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '民间开发版本，不代表学校官方应用',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.state, required this.fallbackId});

  final ResourceState<StudentProfile> state;
  final String fallbackId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = state.data;
    final name = profile?.name ?? '';
    final id = profile?.studentId ?? fallbackId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (profile == null && state.failure == null)
          const Skeleton(width: 96, height: 28)
        else
          Semantics(
            header: true,
            child: Text(
              name.isEmpty ? '同学' : name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        if (id.isNotEmpty)
          Text(
            '学号 $id',
            key: const Key('mine.studentId'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = children
        .where((c) => c is! _InfoRow || c.value.isNotEmpty)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return FrostedCard(
      child: Column(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0)
              Divider(
                indent: AppSpacing.lg,
                endIndent: AppSpacing.lg,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            visible[i],
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md + 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Shown just before the chevron, e.g. the current theme.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              Icon(icon, size: 22, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              // The label absorbs the slack, so whatever sits next to the
              // chevron stays hard against the right edge.
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              if (trailing != null) ...[
                trailing!,
                const SizedBox(width: AppSpacing.xs),
              ],
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
