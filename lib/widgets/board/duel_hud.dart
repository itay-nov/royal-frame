import 'package:flutter/material.dart';

import '../../services/duel_service.dart';
import '../../theme_constants.dart';

/// Duel-mode overlay chrome: the live score strip at the bottom while the
/// duel runs, or the win/lose banner at the top once it's finished.
///
/// Pure visual and non-interactive; must be placed inside a [Stack]
/// (it emits a [Positioned]).
class DuelHud extends StatelessWidget {
  final DuelSession session;
  final String myUid;
  final int myScore;
  final int opponentScore;

  const DuelHud({
    super.key,
    required this.session,
    required this.myUid,
    required this.myScore,
    required this.opponentScore,
  });

  @override
  Widget build(BuildContext context) {
    final isHost = session.hostUid == myUid;
    final opponentName = isHost
        ? (session.guestName ?? 'Opponent')
        : session.hostName;

    // Result banner when duel is finished
    if (session.isFinished && session.abandonedBy == null) {
      final iWon = session.winnerId == myUid;
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Container(
            color: iWon
                ? kGold.withValues(alpha: 0.88)
                : Colors.redAccent.withValues(alpha: 0.82),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  iWon ? '  You Win the Duel!' : '  Opponent Wins the Duel',
                  style: TextStyle(
                    color: iWon ? Colors.black : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Live score HUD strip at the bottom
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.65),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              // My score
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOU',
                      style: TextStyle(
                        color: kGoldLight,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      '$myScore',
                      style: const TextStyle(
                        color: kGold,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              // VS divider
              Container(
                width: 1,
                height: 32,
                color: kGoldDark.withValues(alpha: 0.6),
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              // Opponent score
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      opponentName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      '$opponentScore',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
