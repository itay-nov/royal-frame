import 'package:flutter/material.dart';
import '../services/duel_service.dart';
import '../theme_constants.dart';

class DuelResultOverlay extends StatelessWidget {
  final DuelSession session;
  final String myUid;
  final int myElapsedSeconds;
  final int myRoyals;
  final bool myRematchReady;
  final VoidCallback onPlayAgain;

  const DuelResultOverlay({
    super.key,
    required this.session,
    required this.myUid,
    required this.myElapsedSeconds,
    required this.myRoyals,
    required this.myRematchReady,
    required this.onPlayAgain,
  });

  String _formatTime(int? secs) {
    if (secs == null) return '--:--';
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isHost       = session.hostUid == myUid;
    final iWon         = session.winnerId == myUid;
    final opponentReady = isHost
        ? (session.rematchReady[session.guestUid ?? ''] == true)
        : (session.rematchReady[session.hostUid] == true);

    final myName       = isHost ? session.hostName : (session.guestName ?? 'Guest');
    final myScore      = isHost ? session.hostScore : session.guestScore;
    final myTime       = myElapsedSeconds;
    final myRoyalCount = myRoyals;

    final oppName      = isHost ? (session.guestName ?? 'Opponent') : session.hostName;
    final oppScore     = isHost ? session.guestScore : session.hostScore;
    final oppTime      = isHost ? session.guestTime  : session.hostTime;
    final oppRoyals    = isHost ? session.guestRoyals : session.hostRoyals;

    return Container(
      color: Colors.black.withValues(alpha: 0.82),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          decoration: BoxDecoration(
            color: kBurgundyLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kGold, width: 2),
            boxShadow: [
              BoxShadow(
                color: kGold.withValues(alpha: 0.25),
                blurRadius: 32,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Text(
                iWon ? '👑 You Win the Duel!' : '💀 Opponent Wins',
                style: TextStyle(
                  color: iWon ? kGold : kBlockedBorder,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$myName  vs  $oppName',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 20),

              // Side-by-side stat columns
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // MY column
                    Expanded(
                      child: _StatColumn(
                        label: 'YOU',
                        name: myName,
                        score: myScore,
                        time: _formatTime(myTime),
                        royals: myRoyalCount,
                        highlight: iWon,
                      ),
                    ),
                    // Divider
                    Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      color: kGoldDark.withValues(alpha: 0.4),
                    ),
                    // OPPONENT column
                    Expanded(
                      child: _StatColumn(
                        label: 'OPPONENT',
                        name: oppName,
                        score: oppScore,
                        time: _formatTime(oppTime),
                        royals: oppRoyals,
                        highlight: !iWon,
                        alignRight: true,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Opponent ready indicator
              if (opponentReady && !myRematchReady)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Opponent is ready!',
                    style: TextStyle(
                      color: kGoldLight,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              // Play Again / Waiting
              if (myRematchReady)
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: kGold,
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Waiting for opponent...',
                      style: TextStyle(
                        color: kGoldDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kGold,
                      foregroundColor: kBurgundy,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: onPlayAgain,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text(
                      'Play Again',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String name;
  final int score;
  final String time;
  final int? royals;
  final bool highlight;
  final bool alignRight;

  const _StatColumn({
    required this.label,
    required this.name,
    required this.score,
    required this.time,
    required this.royals,
    required this.highlight,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    final align = alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final textAlign = alignRight ? TextAlign.right : TextAlign.left;
    final color = highlight ? kGold : kBlockedBorder;
    final bgColor = highlight
        ? kGold.withValues(alpha: 0.08)
        : Colors.red.withValues(alpha: 0.06);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(
            label,
            textAlign: textAlign,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            textAlign: textAlign,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: highlight ? Colors.white : Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _StatRow(icon: Icons.stars, value: '$score', highlight: highlight, alignRight: alignRight),
          const SizedBox(height: 6),
          _StatRow(icon: Icons.timer_outlined, value: time, highlight: highlight, alignRight: alignRight),
          const SizedBox(height: 6),
          _StatRow(
            icon: Icons.auto_awesome,
            value: royals != null ? '$royals royals' : '--',
            highlight: highlight,
            alignRight: alignRight,
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final bool highlight;
  final bool alignRight;

  const _StatRow({
    required this.icon,
    required this.value,
    required this.highlight,
    required this.alignRight,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight ? kGoldLight : Colors.white54;
    final children = [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ];
    return Row(
      mainAxisAlignment: alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: alignRight ? children.reversed.toList() : children,
    );
  }
}
