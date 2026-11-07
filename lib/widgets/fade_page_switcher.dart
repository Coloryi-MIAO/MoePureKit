import 'package:flutter/material.dart';

class FadePageSwitcher extends StatelessWidget {
  const FadePageSwitcher({
    super.key,
    required this.child,
    required this.duration,
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // Keep only the incoming page in the layout during the transition.
      // Avoid compositing two full pages at once on lower-end desktops.
      layoutBuilder: (currentChild, _) =>
          currentChild ?? const SizedBox.shrink(),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: RepaintBoundary(child: child),
      ),
      child: child,
    );
  }
}
