import 'package:flutter/material.dart';

/// Overlay widget that flies a card visual from a board cell to the clear
/// pile, shrinking slightly in transit, then reports completion.
///
/// Must be placed inside a [Stack] (it emits a [Positioned]).
class FlyingClearCard extends StatefulWidget {
  final Offset from;
  final Offset to;
  final Widget card;
  final VoidCallback onComplete;

  const FlyingClearCard({
    super.key,
    required this.from,
    required this.to,
    required this.card,
    required this.onComplete,
  });

  @override
  State<FlyingClearCard> createState() => _FlyingClearCardState();
}

class _FlyingClearCardState extends State<FlyingClearCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _ctrl.forward().then((_) {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = Curves.easeInOutCubic.transform(_ctrl.value);
        final pos = Offset.lerp(widget.from, widget.to, t)!;
        final scale = 1.0 - (t * 0.08);
        return Positioned(
          left: pos.dx - (72.0 * scale) / 2,
          top: pos.dy - (100.0 * scale) / 2,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Material(
        elevation: 10,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: widget.card,
      ),
    );
  }
}
