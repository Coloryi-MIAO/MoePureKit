import 'package:flutter/material.dart';

/// Shared reduced-motion preference for subtle entrance and page transitions.
class MotionSettings extends InheritedWidget {
  const MotionSettings({super.key, required this.enabled, required super.child});

  final bool enabled;

  static bool enabledOf(BuildContext context) {
    final setting = context.dependOnInheritedWidgetOfExactType<MotionSettings>();
    return setting?.enabled ?? true;
  }

  @override
  bool updateShouldNotify(MotionSettings oldWidget) => enabled != oldWidget.enabled;
}

/// A lightweight fade + small vertical settle for major UI components.
class FadeIn extends StatelessWidget {
  const FadeIn({super.key, required this.child, this.duration = const Duration(milliseconds: 170), this.offset = 4});

  final Widget child;
  final Duration duration;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = MotionSettings.enabledOf(context) && !reduceMotion;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: enabled ? duration : Duration.zero,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, content) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * offset),
          child: Transform.scale(
            // A tiny settle-in adds depth without introducing blur or heavy
            // compositing layers, so low-end machines stay responsive.
            scale: .985 + (.015 * value),
            alignment: Alignment.topCenter,
            child: content,
          ),
        ),
      ),
    );
  }
}
