import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Opens a page by growing it out of the element that was tapped, and
/// shrinks it back into that element when closed (a "container transform").
///
/// The tapped element is rebuilt inside the expanding container and fades
/// out while the destination page fades in, laid out at full size and scaled
/// to the container's width, so neither ever stretches. While the page is
/// open the original element is hidden, so nothing is drawn twice.
class ExpandOnTap extends StatefulWidget {
  const ExpandOnTap({
    super.key,
    required this.closedBuilder,
    required this.openBuilder,
    this.closedRadius = AppRadius.lg + 4,
    this.closedColor,
    this.onOpen,
    this.onClosed,
  });

  /// The resting element. Call `open` from its tap handler.
  final Widget Function(BuildContext context, VoidCallback open) closedBuilder;
  final WidgetBuilder openBuilder;
  final double closedRadius;

  /// Fill of the resting element; the container fades from it to the page.
  final Color? closedColor;

  /// Called as the page starts opening / once it has fully closed.
  final VoidCallback? onOpen;
  final VoidCallback? onClosed;

  @override
  State<ExpandOnTap> createState() => _ExpandOnTapState();
}

class _ExpandOnTapState extends State<ExpandOnTap> {
  var _hidden = false;

  Rect? _sourceRect() {
    if (!mounted) return null;
    final box = context.findRenderObject();
    final navigator = Navigator.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        navigator is! RenderBox) {
      return null;
    }
    return box.localToGlobal(Offset.zero, ancestor: navigator) & box.size;
  }

  Future<void> _open() async {
    if (_hidden) return;
    final navigator = Navigator.of(context);
    final scheme = Theme.of(context).colorScheme;
    final route = ExpandRoute<void>(
      builder: widget.openBuilder,
      sourceRect: _sourceRect,
      sourceRadius: widget.closedRadius,
      sourceColor: widget.closedColor ?? scheme.surfaceContainerLowest,
      sourceBuilder: (context) => widget.closedBuilder(context, () {}),
    );
    setState(() => _hidden = true);
    widget.onOpen?.call();
    navigator.push(route);
    await route.completed;
    if (!mounted) return;
    setState(() => _hidden = false);
    widget.onClosed?.call();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the element laid out (its rect is the route's anchor) but invisible.
    return Opacity(
      opacity: _hidden ? 0 : 1,
      child: IgnorePointer(
        ignoring: _hidden,
        child: widget.closedBuilder(context, _open),
      ),
    );
  }
}

/// The page route behind [ExpandOnTap]. Usable directly with any rect source.
class ExpandRoute<T> extends PageRoute<T> {
  ExpandRoute({
    required this.builder,
    required this.sourceRect,
    required this.sourceColor,
    this.sourceRadius = AppRadius.lg + 4,
    this.sourceBuilder,
    super.settings,
  });

  final WidgetBuilder builder;

  /// Looked up every frame, so closing returns to where the element is now.
  final Rect? Function() sourceRect;
  final Color sourceColor;
  final double sourceRadius;
  final WidgetBuilder? sourceBuilder;

  Rect? _lastRect;
  bool _gesture = false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 500);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 420);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    return _ExpandTransition(route: this, animation: animation, child: child);
  }

  Rect _currentSource(Size screen) {
    final rect = sourceRect();
    if (rect != null && !rect.isEmpty) _lastRect = rect;
    // Without an anchor (it was disposed), collapse toward the centre.
    return _lastRect ??
        Rect.fromCenter(
          center: screen.center(Offset.zero),
          width: screen.width * 0.6,
          height: screen.height * 0.4,
        );
  }

  // ---- edge-swipe back (iOS) -------------------------------------------

  void _gestureStart() {
    _gesture = true;
    navigator?.didStartUserGesture();
  }

  void _gestureUpdate(double delta, double width) {
    final c = controller;
    if (c == null) return;
    c.value = (c.value - delta / width).clamp(0.0, 1.0);
  }

  void _gestureEnd(double velocity, double width) {
    final c = controller;
    final nav = navigator;
    if (c == null || nav == null) return;
    final fling = velocity / width;
    final stay = fling < -0.8 || (fling.abs() < 0.8 && c.value > 0.6);
    if (stay) {
      c.animateTo(
        1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    } else {
      nav.pop();
    }
    void done() {
      _gesture = false;
      nav.didStopUserGesture();
    }

    if (c.isAnimating) {
      late final AnimationStatusListener listener;
      listener = (status) {
        if (status.isAnimating) return;
        c.removeStatusListener(listener);
        done();
      };
      c.addStatusListener(listener);
    } else {
      done();
    }
  }
}

class _ExpandTransition extends StatelessWidget {
  const _ExpandTransition({
    required this.route,
    required this.animation,
    required this.child,
  });

  final ExpandRoute<dynamic> route;
  final Animation<double> animation;
  final Widget child;

  static const _curve = Curves.easeInOutCubicEmphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final full = Offset.zero & size;
    final platform = Theme.of(context).platform;
    final swipeBack =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, page) {
        final v = animation.value;
        // Finger-driven while swiping; eased otherwise. Closing decelerates
        // into the element (the opening curve, mirrored).
        final t = route._gesture
            ? v
            : animation.status == AnimationStatus.reverse
            ? _curve.flipped.transform(v)
            : _curve.transform(v);
        final source = route._currentSource(size);
        final rect = Rect.lerp(source, full, t)!;
        final radius = lerpDouble(route.sourceRadius, 0, t)!;
        final settled = animation.status == AnimationStatus.completed;

        // Content swap happens early, while the container is still small.
        double band(double from, double to) =>
            ((v - from) / (to - from)).clamp(0.0, 1.0);
        final sourceOpacity = 1 - band(0, 0.22);
        final pageOpacity = Curves.easeOut.transform(band(0.12, 0.55));
        final lift = math.sin(math.pi * t); // shadow peaks mid-flight

        return Stack(
          children: [
            // Dim what stays behind, so the growing page reads as "on top".
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.16 * t),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: rect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18 * lift),
                      blurRadius: 32,
                      offset: Offset(0, 14 * lift),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  clipBehavior: settled ? Clip.none : Clip.antiAlias,
                  child: ColoredBox(
                    color: Color.lerp(route.sourceColor, scheme.surface, t)!,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (route.sourceBuilder != null && sourceOpacity > 0)
                          Positioned(
                            key: const ValueKey('source'),
                            left: 0,
                            top: 0,
                            width: source.width,
                            height: source.height,
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: sourceOpacity,
                                child: route.sourceBuilder!(context),
                              ),
                            ),
                          ),
                        IgnorePointer(
                          key: const ValueKey('page'),
                          ignoring: !settled,
                          child: Opacity(
                            opacity: pageOpacity,
                            child: FittedBox(
                              fit: BoxFit.fitWidth,
                              alignment: Alignment.topCenter,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox.fromSize(size: size, child: page),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Stays mounted for the whole swipe, which unsettles the route.
            if (swipeBack && (settled || route._gesture))
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 20,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) => route._gestureStart(),
                  onHorizontalDragUpdate: (d) =>
                      route._gestureUpdate(d.delta.dx, size.width),
                  onHorizontalDragEnd: (d) => route._gestureEnd(
                    d.velocity.pixelsPerSecond.dx,
                    size.width,
                  ),
                  onHorizontalDragCancel: () =>
                      route._gestureEnd(0, size.width),
                ),
              ),
          ],
        );
      },
    );
  }
}
