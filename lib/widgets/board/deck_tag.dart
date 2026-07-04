import 'package:flutter/material.dart';

import '../../theme_constants.dart';

/// Small labelled chip shown above the deck/clear piles on the board.
class DeckTag extends StatelessWidget {
  final String text;
  const DeckTag({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kBurgundy.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: kGoldDark.withValues(alpha: 0.8), width: 1.0),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: kGoldLight,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          height: 1.3,
        ),
      ),
    );
  }
}
