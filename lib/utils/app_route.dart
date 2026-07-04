import 'package:flutter/material.dart';

import '../theme_constants.dart';

/// The app's shared page transition: a quick fade with a subtle 3% upward
/// slide. Replaces default MaterialPageRoute slides for a calmer, more
/// premium feel. Generic so `await Navigator.push(...)` result plumbing
/// (e.g. BoardScreen popping its GameState for resume) keeps working.
Route<T> appRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: kDurRoute,
      reverseTransitionDuration: kDurRouteBack,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: kCurveEmphasized);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
