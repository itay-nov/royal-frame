import 'package:flutter/material.dart';

import '../theme_constants.dart';

/// Non-blocking floating hint bubble.
/// Positioning is handled by the caller (e.g. Positioned).
class FloatingHint extends StatefulWidget {
  final String message;

  const FloatingHint({super.key, required this.message});

  @override
  State<FloatingHint> createState() => _FloatingHintState();
}

class _FloatingHintState extends State<FloatingHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeIn;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _fadeIn = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
    );
    _pulse = Tween<double>(begin: 1.0, end: 1.042).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Opacity(
          opacity: _fadeIn.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: _pulse.value, child: child),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.80),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Text(
            widget.message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kBurgundyDeep, // readable on the white bubble
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.45,
              shadows: [
                Shadow(
                  color: Colors.white.withValues(alpha: 0.50),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
