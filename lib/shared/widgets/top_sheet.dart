import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'frosted.dart';

/// Shows [builder] in a sheet that drops down from the top of the screen.
///
/// It closes on system back, a tap outside it, or an upward swipe on its
/// grab handle; the sheet follows the finger and springs back if the swipe
/// is short.
Future<T?> showTopSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String barrierLabel = '关闭',
}) => Navigator.of(
  context,
).push(TopSheetRoute<T>(builder: builder, barrierLabel: barrierLabel));

class TopSheetRoute<T> extends PopupRoute<T> {
  TopSheetRoute({
    required this.builder,
    required this.barrierLabel,
    super.settings,
  });

  final WidgetBuilder builder;

  @override
  final String barrierLabel;

  @override
  Color get barrierColor => const Color(0x73000000);

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 460);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 280);

  bool _dragging = false;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _TopSheetFrame(route: this, animation: animation, child: builder);

  void _dragStart() {
    _dragging = true;
    navigator?.didStartUserGesture();
  }

  void _dragUpdate(double delta, double height) {
    final c = controller;
    if (c == null || height <= 0) return;
    c.value = (c.value + delta / height).clamp(0.0, 1.0);
  }

  void _dragEnd(double velocity) {
    final c = controller;
    final nav = navigator;
    if (c == null || nav == null) return;
    final close = velocity < -600 || (velocity < 600 && c.value < 0.65);
    void springBack() => c.animateTo(
      1,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
    if (close) {
      // maybePop honours PopScope (e.g. while a charge is submitting).
      nav.maybePop().then((popped) {
        if (!popped && c.value < 1) springBack();
      });
    } else {
      springBack();
    }
    void done() {
      _dragging = false;
      nav.didStopUserGesture();
    }

    if (!c.isAnimating) return done();
    late final AnimationStatusListener listener;
    listener = (status) {
      if (status.isAnimating) return;
      c.removeStatusListener(listener);
      done();
    };
    c.addStatusListener(listener);
  }
}

class _TopSheetFrame extends StatefulWidget {
  const _TopSheetFrame({
    required this.route,
    required this.animation,
    required this.child,
  });

  final TopSheetRoute<dynamic> route;
  final Animation<double> animation;
  final WidgetBuilder child;

  @override
  State<_TopSheetFrame> createState() => _TopSheetFrameState();
}

class _TopSheetFrameState extends State<_TopSheetFrame> {
  final _sheetKey = GlobalKey();

  double get _height =>
      (_sheetKey.currentContext?.findRenderObject() as RenderBox?)
          ?.size
          .height ??
      1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduced = AppMotion.reduced(context);
    final route = widget.route;
    final padding = MediaQuery.paddingOf(context);
    final radius = const BorderRadius.vertical(
      bottom: Radius.circular(AppRadius.xl + 4),
    );

    // Above the keyboard when a field is focused.
    final available =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final sheet = Container(
      key: _sheetKey,
      constraints: BoxConstraints(maxWidth: 560, maxHeight: available * 0.94),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 40,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        // Frosted glass over the page; cards inside share their own blur.
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: glassSigma * 1.6,
            sigmaY: glassSigma * 1.6,
          ),
          child: BackdropGroup(
            child: ColoredBox(
              color: Color.alphaBlend(
                glassFill(context, 1.3),
                scheme.surface.withValues(alpha: 0.35),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: EdgeInsets.only(top: padding.top),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(child: Builder(builder: widget.child)),
                      // Grab handle: swipe up to put the sheet away.
                      Semantics(
                        label: '向上滑动收起',
                        child: GestureDetector(
                          key: const Key('topSheet.handle'),
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragStart: (_) => route._dragStart(),
                          onVerticalDragUpdate: (d) =>
                              route._dragUpdate(d.primaryDelta ?? 0, _height),
                          onVerticalDragEnd: (d) =>
                              route._dragEnd(d.primaryVelocity ?? 0),
                          onVerticalDragCancel: () => route._dragEnd(0),
                          child: SizedBox(
                            height: 32,
                            child: Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: 0.35,
                                  ),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Align(
      alignment: Alignment.topCenter,
      child: AnimatedBuilder(
        animation: widget.animation,
        child: sheet,
        builder: (context, child) {
          final v = widget.animation.value;
          if (reduced) return Opacity(opacity: v, child: child);
          // Follows the finger while dragging; otherwise drops in with a
          // long deceleration and leaves accelerating upward.
          final t = route._dragging
              ? v
              : widget.animation.status == AnimationStatus.reverse
              ? Curves.easeOutCubic.transform(v)
              : Curves.easeOutQuint.transform(v);
          return FractionalTranslation(
            translation: Offset(0, t - 1),
            child: child,
          );
        },
      ),
    );
  }
}
