import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Fades and lifts [child] in as [animation] runs, staggered by [step].
///
/// Drive several of these from one controller to build a screen entrance.
class StaggeredReveal extends StatelessWidget {
  const StaggeredReveal({
    super.key,
    required this.animation,
    required this.step,
    required this.child,
    this.offset = 14,
    this.scaleFrom = 1,
    this.delay = 0,
    this.stepFraction = 0.1,
    this.window = 0.5,
  });

  final Animation<double> animation;
  final int step;

  /// Upward travel in logical pixels.
  final double offset;

  /// Starting scale; < 1 gives the focal element a slight "settle".
  final double scaleFrom;

  /// Fraction of the controller to wait before the first step.
  final double delay;

  /// Delay between consecutive steps, as a fraction of the controller.
  final double stepFraction;

  /// Length of each step's own animation, as a fraction of the controller.
  final double window;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (delay + step * stepFraction).clamp(0.0, 1 - window);
    final progress = animation.drive(
      CurveTween(
        curve: Interval(start, start + window, curve: AppMotion.curve),
      ),
    );
    return FadeTransition(
      opacity: progress,
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, child) {
          final t = progress.value;
          final scale = scaleFrom + (1 - scaleFrom) * t;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.translationValues(0, offset * (1 - t), 0)
              ..scaleByDouble(scale, scale, 1, 1),
            child: child,
          );
        },
        child: child,
      ),
    );
  }
}

/// Horizontal "no" shake for rejected input. Run [animation] from 0 to 1.
class ShakeTransition extends StatelessWidget {
  const ShakeTransition({
    super.key,
    required this.animation,
    required this.child,
    this.amplitude = 8,
  });

  final Animation<double> animation;
  final double amplitude;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        // Three decaying oscillations; settles exactly at 0.
        final dx = math.sin(t * math.pi * 6) * amplitude * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: child,
    );
  }
}

/// Fade + slight scale swap, used for whole-screen and overlay changes.
Widget fadeThroughTransition(Widget child, Animation<double> animation) {
  final curved = animation.drive(CurveTween(curve: AppMotion.curve));
  return FadeTransition(
    opacity: curved,
    child: ScaleTransition(
      scale: curved.drive(Tween(begin: 0.985, end: 1.0)),
      child: child,
    ),
  );
}

/// Screen hand-off for the auth gate.
///
/// Only the outgoing screen is animated here: it recedes (fades out with a
/// slight shrink, accelerating) during the first half of the hand-off. The
/// incoming screen is shown at once and plays its own entrance after
/// [AppMotion.entranceDelay], so nothing is faded twice and there is never
/// a blank gap between screens. The widget structure is identical for both
/// directions, so a screen keeps its state if the hand-off is interrupted.
Widget handoffTransition(Widget child, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final leaving =
          animation.status == AnimationStatus.reverse ||
          animation.status == AnimationStatus.dismissed;
      // Outgoing value runs 1 → 0; map the first part of that to 0 → 1.
      final t = leaving
          ? ((1 - animation.value) / AppMotion.handoffExitFraction).clamp(
              0.0,
              1.0,
            )
          : 0.0;
      final exit = Curves.easeIn.transform(t);
      return Opacity(
        opacity: 1 - exit,
        child: Transform.scale(scale: 1 - 0.025 * exit, child: child),
      );
    },
  );
}

/// Shrinks slightly while pressed. Wrap custom tappable surfaces with it;
/// [AppButton] has the same behavior built in.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.97,
  });

  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  var _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final active = _pressed && widget.enabled && !AppMotion.reduced(context);
    return Listener(
      onPointerDown: widget.enabled ? (_) => _set(true) : null,
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: active ? widget.scale : 1,
        duration: AppMotion.short,
        curve: AppMotion.curve,
        child: widget.child,
      ),
    );
  }
}

/// A number that counts up from 0 the first time it appears and glides to
/// new values afterwards. Falls back to [fallback] text when not numeric.
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.value,
    required this.fallback,
    this.decimals = 2,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.suffixStyle,
  });

  final double? value;
  final String fallback;
  final int decimals;
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final TextStyle? suffixStyle;

  @override
  Widget build(BuildContext context) {
    final target = value;
    if (target == null) {
      return Text('$prefix$fallback$suffix', style: style);
    }
    final reduced = AppMotion.reduced(context);
    return Semantics(
      label: '$prefix${target.toStringAsFixed(decimals)}$suffix',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduced ? target : 0, end: target),
        duration: reduced ? Duration.zero : AppMotion.countUp,
        curve: Curves.easeOutQuart,
        builder: (context, v, _) => Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$prefix${v.toStringAsFixed(decimals)}'),
              if (suffix.isNotEmpty) TextSpan(text: suffix, style: suffixStyle),
            ],
          ),
          style: style?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Placeholder block for loading content. Breathes gently unless the user
/// asked for reduced motion; pauses automatically when offstage (TickerMode).
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = AppRadius.sm,
    this.color,
  });

  final double? width;
  final double height;
  final double radius;

  /// Defaults to 8% of onSurface; pass a tint for colored surfaces.
  final Color? color;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    lowerBound: 0.45,
    upperBound: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _pulse.stop();
      _pulse.value = 0.7;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.08);
    return FadeTransition(
      opacity: _pulse,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Like [IndexedStack], with a fade-through between pages: the old page
/// fades out quickly, then the new one fades in while rising a few pixels.
/// The two are never fully visible at the same time.
///
/// Every page keeps its state. Hidden pages ignore input, are hidden from
/// accessibility services and have their own animations paused.
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: AppMotion.tabSwitch,
    value: 1,
  );
  int? _previous;

  @override
  void didUpdateWidget(FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    if (AppMotion.reduced(context)) {
      _previous = null;
      _controller.value = 1;
      return;
    }
    _previous = oldWidget.index;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Old page: gone within the first 35%. New page: from 25% to the end.
    final fadeOut = _controller.drive(
      CurveTween(curve: const Interval(0, 0.35, curve: Curves.easeIn)),
    );
    final fadeIn = _controller.drive(
      CurveTween(curve: const Interval(0.25, 1, curve: AppMotion.curve)),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _TabPage(
            key: ValueKey(i),
            active: i == widget.index,
            opacity: i == widget.index
                ? fadeIn
                : i == _previous
                ? ReverseAnimation(fadeOut)
                : kAlwaysDismissedAnimation,
            rise: i == widget.index ? fadeIn : kAlwaysCompleteAnimation,
            child: widget.children[i],
          ),
      ],
    );
  }
}

class _TabPage extends StatelessWidget {
  const _TabPage({
    super.key,
    required this.active,
    required this.opacity,
    required this.rise,
    required this.child,
  });

  final bool active;
  final Animation<double> opacity;
  final Animation<double> rise;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !active,
      child: ExcludeSemantics(
        excluding: !active,
        child: FadeTransition(
          opacity: opacity,
          child: AnimatedBuilder(
            animation: rise,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, 8 * (1 - rise.value)),
              child: child,
            ),
            child: TickerMode(enabled: active, child: child),
          ),
        ),
      ),
    );
  }
}

/// Sequential view change for an [AnimatedSwitcher]: the old view fades out
/// completely in the first 35%, then the new one fades in (sliding
/// [distance] px from the side given by [direction]; 0 = no slide). The
/// two are never visible together, so nothing ghosts through.
///
/// Listens to [animation]; an AnimatedSwitcher builds each transition only
/// once, so reading the animation's value directly would freeze the view at
/// whatever opacity it had when it was first built.
Widget sequentialTransition(
  Widget child,
  Animation<double> animation, {
  int direction = 0,
  double distance = 24,
}) {
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final v = animation.value;
      final entering = animation.status != AnimationStatus.reverse;
      final t = ((v - 0.35) / 0.65).clamp(0.0, 1.0);
      final opacity = entering
          ? Curves.easeOut.transform(t)
          : ((v - 0.65) / 0.35).clamp(0.0, 1.0);
      final dx = entering && direction != 0
          ? distance * direction * (1 - Curves.easeOutCubic.transform(t))
          : 0.0;
      return Opacity(
        opacity: opacity,
        child: Transform.translate(offset: Offset(dx, 0), child: child),
      );
    },
  );
}
