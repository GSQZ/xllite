import 'dart:ui' show ImageFilter;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/frosted.dart';
import '../../../shared/widgets/soft_backdrop.dart';

/// Frame for feature pages opened from home: a compact centred title bar
/// over the same soft backdrop as home, pull-to-refresh and a readable
/// column. The bar is see-through at rest and gains a surface and hairline
/// only once content scrolls under it.
class FeaturePage extends StatefulWidget {
  const FeaturePage({
    super.key,
    required this.title,
    required this.children,
    this.onRefresh,
    this.onNearEnd,
    this.scrollKey,
  });

  final String title;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  /// Called when the user scrolls close to the bottom (infinite lists).
  final VoidCallback? onNearEnd;
  final Key? scrollKey;

  @override
  State<FeaturePage> createState() => _FeaturePageState();
}

class _FeaturePageState extends State<FeaturePage> {
  /// 0 at rest → 1 once content has scrolled ~28px under the title bar.
  var _glass = 0.0;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final glass = (notification.metrics.pixels / 28).clamp(0.0, 1.0);
    if ((glass - _glass).abs() > 0.02 || (glass != _glass && glass % 1 == 0)) {
      setState(() => _glass = glass);
    }
    if (widget.onNearEnd != null && notification.metrics.extentAfter < 480) {
      widget.onNearEnd!();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(AppSpacing.gutterFor(width), (width - 600) / 2);

    Widget scroll = CustomScrollView(
      key: widget.scrollKey,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          pinned: true,
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          backgroundColor: Colors.transparent,
          // Glass grows in with the scroll instead of snapping on.
          flexibleSpace: _GlassBar(strength: _glass),
          leading: IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(widget.title),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            side,
            AppSpacing.sm,
            side,
            AppSpacing.xxl + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverList.list(children: widget.children),
        ),
      ],
    );

    scroll = NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: scroll,
    );
    if (widget.onRefresh != null) {
      scroll = RefreshIndicator(
        onRefresh: widget.onRefresh!,
        edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
        child: scroll,
      );
    }
    return ColoredBox(
      color: scheme.surface,
      child: SoftBackdrop(
        // Cards on this page share one blurred snapshot.
        child: BackdropGroup(
          child: Scaffold(backgroundColor: Colors.transparent, body: scroll),
        ),
      ),
    );
  }
}

/// Frosted title-bar background whose blur, fill and hairline scale with
/// [strength] (0 = invisible, 1 = full glass).
class _GlassBar extends StatelessWidget {
  const _GlassBar({required this.strength});

  final double strength;

  @override
  Widget build(BuildContext context) {
    if (strength <= 0) return const SizedBox.expand();
    final t = Curves.easeOut.transform(strength);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: glassSigma * t,
          sigmaY: glassSigma * t,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: glassFill(context, t),
            border: Border(bottom: BorderSide(color: glassEdge(context, t))),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Rounded group that holds list rows separated by inset hairlines.
class RowGroup extends StatelessWidget {
  const RowGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Frosted glass; a real Material inside so row ink stays visible.
    return FrostedCard(
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                indent: AppSpacing.lg,
                endIndent: AppSpacing.lg,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Small rounded label (e.g. 未通过, 毕业审核, 退款).
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Horizontally scrolling single-choice pills (terms, date ranges).
class ChoicePills<T> extends StatelessWidget {
  const ChoicePills({
    super.key,
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<T> options;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final option in options) ...[
            Semantics(
              selected: option == selected,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () => onSelected(option),
                child: AnimatedContainer(
                  duration: AppMotion.medium,
                  curve: AppMotion.curve,
                  constraints: const BoxConstraints(minHeight: 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: option == selected
                        ? scheme.primary
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: AppMotion.medium,
                    style: theme.textTheme.labelLarge!.copyWith(
                      fontSize: 13.5,
                      color: option == selected
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                    ),
                    child: Text(label(option)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}
