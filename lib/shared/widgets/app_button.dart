import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppButtonVariant { filled, outlined }

/// Full-width action button with a built-in loading state.
///
/// While [loading] the button is disabled but keeps its normal colors, so it
/// reads as "working" rather than "unavailable". Pressing gives a subtle
/// scale-down; label/loading swaps cross-fade.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconColor,
    this.loading = false,
    this.loadingLabel,
    this.variant = AppButtonVariant.filled,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Overrides the icon tint, e.g. to hint at a third-party service.
  final Color? iconColor;
  final bool loading;
  final String? loadingLabel;
  final AppButtonVariant variant;
  final bool destructive;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filled = widget.variant == AppButtonVariant.filled;
    final loading = widget.loading;
    final accent = widget.destructive ? scheme.error : scheme.primary;
    final onAccent = widget.destructive ? scheme.onError : scheme.onPrimary;
    final enabled = widget.onPressed != null && !loading;

    final ButtonStyle style;
    if (filled) {
      style = FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        disabledBackgroundColor: loading
            ? accent.withValues(alpha: 0.78)
            : null,
        disabledForegroundColor: loading ? onAccent : null,
      );
    } else {
      style = OutlinedButton.styleFrom(
        foregroundColor: widget.destructive ? scheme.error : null,
        disabledForegroundColor: loading ? accent : null,
        side: widget.destructive
            ? BorderSide(color: scheme.error.withValues(alpha: 0.5))
            : null,
      );
    }

    final spinnerColor = filled ? onAccent : accent;
    final Widget content;
    if (loading) {
      content = _ButtonContent(
        key: const ValueKey('loading'),
        leading: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: spinnerColor,
          ),
        ),
        label: widget.loadingLabel ?? widget.label,
      );
    } else if (widget.icon != null) {
      content = _ButtonContent(
        key: const ValueKey('idle'),
        leading: Icon(
          widget.icon,
          size: 20,
          color: widget.onPressed == null ? null : widget.iconColor,
        ),
        label: widget.label,
      );
    } else {
      content = Text(
        widget.label,
        key: const ValueKey('idle'),
        textAlign: TextAlign.center,
      );
    }

    final reduced = AppMotion.reduced(context);
    final animatedContent = AnimatedSwitcher(
      duration: reduced ? Duration.zero : AppMotion.medium,
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: content,
    );

    final effectiveOnPressed = loading ? null : widget.onPressed;
    // Colored lift for the primary action only while it can be (or is being)
    // used; a locked button sits flat. Pressing pushes it closer.
    final lifted = filled && (widget.onPressed != null || loading);
    final pressed = _pressed && enabled;
    return Listener(
      onPointerDown: enabled ? (_) => _setPressed(true) : null,
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: pressed && !reduced ? 0.98 : 1,
        duration: AppMotion.short,
        curve: AppMotion.curve,
        child: AnimatedContainer(
          duration: AppMotion.medium,
          curve: AppMotion.curve,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(
                  alpha: !lifted ? 0 : (pressed ? 0.18 : 0.26),
                ),
                blurRadius: pressed ? 10 : 18,
                offset: Offset(0, pressed ? 3 : 6),
              ),
            ],
          ),
          child: filled
              ? FilledButton(
                  style: style,
                  onPressed: effectiveOnPressed,
                  child: animatedContent,
                )
              : OutlinedButton(
                  style: style,
                  onPressed: effectiveOnPressed,
                  child: animatedContent,
                ),
        ),
      ),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({super.key, required this.leading, required this.label});

  final Widget leading;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        const SizedBox(width: AppSpacing.sm + 2),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
  }
}
