import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'xl_theme.dart';

class XLCard extends StatelessWidget {
  const XLCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.radius = 18,
    this.color = XLColors.surface,
    this.borderColor = XLColors.line,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    return Material(
      type: MaterialType.transparency,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
          border: Border.all(color: borderColor),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class XLIconBox extends StatelessWidget {
  const XLIconBox({
    super.key,
    required this.icon,
    this.size = 44,
    this.iconSize = 22,
    this.color = XLColors.brandSoft,
    this.iconColor = XLColors.brand,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: iconSize, color: iconColor),
      ),
    );
  }
}

class XLIconButton extends StatelessWidget {
  const XLIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 40,
    this.iconSize = 21,
    this.background = XLColors.surfaceMuted,
    this.foreground = XLColors.inkSecondary,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.34);
    final button = Material(
      type: MaterialType.transparency,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(color: background, borderRadius: radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: iconSize, color: foreground),
          ),
        ),
      ),
    );

    if (tooltip == null) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
  }
}

class XLChoicePill extends StatelessWidget {
  const XLChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Widget label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? XLColors.brandSoft : XLColors.surface,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? XLColors.brand.withValues(alpha: 0.18)
                  : XLColors.line,
              width: 1.1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(LucideIcons.check, size: 16, color: XLColors.brand),
                const SizedBox(width: 7),
              ],
              DefaultTextStyle.merge(
                style: TextStyle(
                  color: selected ? XLColors.ink : XLColors.inkSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
                child: label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class XLSheetErrorBanner extends StatelessWidget {
  const XLSheetErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: XLColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: XLColors.danger.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              LucideIcons.circleAlert,
              size: 18,
              color: XLColors.danger,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: XLColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class XLSectionHeader extends StatelessWidget {
  const XLSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: XLColors.ink,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class XLBottomNavItem {
  const XLBottomNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class XLBottomNav extends StatelessWidget {
  const XLBottomNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onSelected,
  });

  final int currentIndex;
  final List<XLBottomNavItem> items;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF2F4FA),
        border: Border(top: BorderSide(color: XLColors.line, width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(8, 7, 8, 7),
        child: SizedBox(
          height: 66,
          child: Row(
            children: List.generate(items.length, (index) {
              return Expanded(
                child: _XLBottomNavButton(
                  item: items[index],
                  selected: currentIndex == index,
                  onTap: () => onSelected(index),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _XLBottomNavButton extends StatelessWidget {
  const _XLBottomNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final XLBottomNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? XLColors.brand : XLColors.inkSecondary;
    final textColor = selected ? XLColors.ink : XLColors.inkSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            width: selected ? 64 : 44,
            height: 34,
            decoration: BoxDecoration(
              color: selected ? XLColors.brandSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              selected ? item.activeIcon : item.icon,
              size: 23,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
