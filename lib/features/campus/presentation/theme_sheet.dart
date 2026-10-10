import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/theme_settings.dart';
import '../../../shared/widgets/frosted.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/segmented.dart';
import '../../../shared/widgets/top_sheet.dart';
import 'section_parts.dart';

/// Skin picker, dropped from the top like the other sheets.
Future<void> showThemeSheet(BuildContext context) => showTopSheet<void>(
  context,
  barrierLabel: '关闭主题设置',
  builder: (context) => const ThemeSheet(),
);

class ThemeSheet extends StatelessWidget {
  const ThemeSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ThemeScope.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(title: '主题与外观'),
          const SizedBox(height: AppSpacing.md),
          const SkinPreview(),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.md,
            children: [
              for (final skin in ThemeSkin.values)
                LayoutBuilder(
                  builder: (context, _) => SkinSwatch(
                    skin: skin,
                    selected: skin == settings.skin,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      settings.setSkin(skin);
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const _AppearanceModeField(),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '皮肤会同时套用到首页底色、按钮、选中状态和图标。'
                  '外观默认为跟随系统，也可固定为浅色或深色。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              key: const Key('theme.reset'),
              onPressed: settings.skin == defaultSkin
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      settings.setSkin(defaultSkin);
                    },
              child: const Text('恢复默认皮肤'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Design size of the preview stage: it is drawn once at this size and
/// scaled to the sheet's width, so it looks the same on every phone.
const double _previewWidth = 340;
const double _previewHeight = 156;

/// Follow the system, or pin the app to light / dark.
///
/// The choice lives in the same [ThemeSettings] as the skin, so both are
/// restored together on the next launch.
class _AppearanceModeField extends StatelessWidget {
  const _AppearanceModeField();

  static const List<String> _labels = ['跟随系统', '浅色', '深色'];
  static const List<ThemeMode> _modes = [
    ThemeMode.system,
    ThemeMode.light,
    ThemeMode.dark,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('外观', style: theme.textTheme.titleSmall),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppSegmented(
          key: const Key('theme.mode'),
          labels: _labels,
          index: _modes.indexOf(settings.mode),
          onChanged: (index) {
            if (_modes[index] == settings.mode) return;
            HapticFeedback.selectionClick();
            settings.setMode(_modes[index]);
          },
        ),
      ],
    );
  }
}

/// A miniature of the app in the current skin — wash, figure, buttons —
/// so the choice is judged the way it will actually look.
class SkinPreview extends StatelessWidget {
  const SkinPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = ThemeScope.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = AppTheme.light(seed: settings.skin.color).colorScheme;
    final colors = dark
        ? AppTheme.dark(seed: settings.skin.color).colorScheme
        : scheme;
    final glow = settings.skin.glow(Theme.of(context).brightness);

    return AspectRatio(
      aspectRatio: _previewWidth / _previewHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.center,
          child: SizedBox(
            width: _previewWidth,
            height: _previewHeight,
            // The stage is a fixed drawing scaled to the sheet's width, so it
            // renders at its own text scale rather than the system one.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1,
              child: _PreviewStage(colors: colors, glow: glow, dark: dark),
            ),
          ),
        ),
      ),
    );
  }
}

/// The preview's fixed-size drawing.
class _PreviewStage extends StatelessWidget {
  const _PreviewStage({
    required this.colors,
    required this.glow,
    required this.dark,
  });

  final ColorScheme colors;
  final Color glow;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.surface),
      child: Stack(
        children: [
          Positioned(
            top: -70,
            right: -50,
            child: _Glow(color: glow, dark: dark),
          ),
          Positioned(
            bottom: -80,
            left: -60,
            child: _Glow(color: glow, dark: dark, opacity: 0.5),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '下午好，同学',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '¥ 128.50',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Pill(color: colors, label: '校园卡'),
                    const SizedBox(width: 8),
                    _Pill(color: colors, label: '宿舍电量'),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    _Pill(
                      key: const Key('skinned.primary'),
                      color: colors,
                      background: colors.primary,
                      foreground: colors.onPrimary,
                      label: '充值',
                    ),
                    const SizedBox(width: 8),
                    _Pill(
                      color: colors,
                      background: colors.primaryContainer,
                      foreground: colors.onPrimaryContainer,
                      label: '校园码',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.dark, this.opacity = 1});

  final Color color;
  final bool dark;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final c = color.withValues(alpha: (dark ? 0.22 : 0.18) * opacity);
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)]),
      ),
    );
  }
}

/// A chip in the preview. Every one is the same height, so the rows line up.
class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.color,
    required this.label,
    this.background,
    this.foreground,
  });

  final ColorScheme color;
  final String label;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background ?? color.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: background == null ? FontWeight.w500 : FontWeight.w600,
        height: 1,
        color: foreground ?? color.onSurfaceVariant,
      ),
    ),
  );
}

/// One skin: a disc of its colour, ticked when chosen, named underneath.
class SkinSwatch extends StatelessWidget {
  const SkinSwatch({
    super.key,
    required this.skin,
    required this.selected,
    required this.onTap,
  });

  final ThemeSkin skin;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: skin.label,
      child: PressScale(
        scale: 0.93,
        child: InkWell(
          key: Key('theme.skin.${skin.name}'),
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: AppMotion.medium,
                  curve: AppMotion.curve,
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: skin.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? scheme.onSurface : Colors.transparent,
                      width: 2.5,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: skin.color.withValues(alpha: 0.45),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: AnimatedScale(
                    duration: AppMotion.medium,
                    curve: AppMotion.pop,
                    scale: selected ? 1 : 0,
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  skin.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The current skin's name and colour, shown in the 「我的」row.
class ThemeSummary extends StatelessWidget {
  const ThemeSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = ThemeScope.maybeOf(context);
    if (settings == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '当前皮肤 ${settings.skin.label}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              settings.skin.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: settings.skin.color,
              shape: BoxShape.circle,
              border: Border.all(color: glassEdge(context), width: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
