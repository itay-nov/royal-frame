import 'package:flutter/material.dart';

import '../theme_constants.dart';

/// Animates an overlay's arrival: fade from 0 and scale from 0.94, once,
/// on insertion. Buttons stay hittable throughout (no pointer blocking) —
/// at 250ms the window is too short to matter.
class OverlayEntrance extends StatelessWidget {
  final Widget child;

  const OverlayEntrance({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: kDurMed,
      curve: kCurveEmphasized,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.94 + (0.06 * t),
          child: child,
        ),
      ),
    );
  }
}
