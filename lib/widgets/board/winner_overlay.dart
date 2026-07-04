import 'package:flutter/material.dart';

import '../../theme_constants.dart';
import '../../utils/localization.dart';
import '../royal_button.dart';

/// Final score breakdown shown on the win overlay, computed by the caller
/// at end-state time.
typedef WinnerStats = ({
  int baseScore,
  int winBonus,
  int effBonus,
  int speedBonus,
  double multiplier,
  int totalScore,
  int xpGained,
});

/// Full-screen victory overlay. Pure visual: stats come in via constructor,
/// user intents leave via callbacks — persistence and XP accounting stay
/// with the caller.
class WinnerOverlay extends StatelessWidget {
  final WinnerStats stats;
  final AppLang lang;
  final VoidCallback onPlayAgain;
  final VoidCallback onChangeDifficulty;
  final VoidCallback onShare;
  final VoidCallback onMainMenu;

  const WinnerOverlay({
    super.key,
    required this.stats,
    required this.lang,
    required this.onPlayAgain,
    required this.onChangeDifficulty,
    required this.onShare,
    required this.onMainMenu,
  });

  Widget _scoreRow(String title, String value, {bool isGold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              color: isGold ? kGold : kGoldLight,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L(lang);
    const textShadow = [
      Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 2)),
    ];

    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding:
              const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
          decoration: BoxDecoration(
            color: kBurgundyLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kGold, width: 2.5),
            boxShadow: [
              BoxShadow(
                  color: kGold.withValues(alpha: 0.35),
                  blurRadius: 40,
                  spreadRadius: 4)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('👑', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text(
                l.winTitle,
                style: const TextStyle(
                  color: kGold,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  shadows: textShadow,
                ),
              ),
              const SizedBox(height: 12),

              // Score breakdown
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: kGoldDark.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    _scoreRow(l.winBaseScore, '+${stats.baseScore}'),
                    _scoreRow(l.effBonus, '+${stats.effBonus}'),
                    _scoreRow(l.speedBonus, '+${stats.speedBonus}'),
                    _scoreRow(l.winBonus, '+${stats.winBonus}',
                        isGold: true),
                    if (stats.multiplier != 1.0)
                      _scoreRow(
                        l.difficultyMultiplier(
                            stats.multiplier.toStringAsFixed(1)),
                        '',
                      ),
                    const Divider(color: kGoldDark, height: 24),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l.totalScore,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${stats.totalScore}',
                          style: const TextStyle(
                              color: kGold,
                              fontSize: 20,
                              fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // XP badge
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: kGoldDark.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: kGold, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '+${stats.xpGained} XP',
                      style: const TextStyle(
                        // kGoldLight for WCAG small-text contrast on the
                        // burgundy overlay card.
                        color: kGoldLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              RoyalButton(
                label: l.winBtn,
                icon: Icons.refresh,
                variant: RoyalButtonVariant.emphasized,
                expand: true,
                minHeight: 52,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                onPressed: onPlayAgain,
              ),
              const SizedBox(height: 10),

              RoyalButton(
                label: lang == AppLang.he ? 'בחר רמה' : 'Change Difficulty',
                icon: Icons.tune,
                variant: RoyalButtonVariant.secondary,
                expand: true,
                minHeight: 44,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                onPressed: onChangeDifficulty,
              ),
              const SizedBox(height: 8),
              RoyalButton(
                label: l.shareVictoryBtn,
                icon: Icons.share,
                variant: RoyalButtonVariant.secondary,
                expand: true,
                minHeight: 44,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                onPressed: onShare,
              ),
              const SizedBox(height: 8),
              RoyalButton(
                label: lang == AppLang.he ? 'תפריט ראשי' : 'Main Menu',
                icon: Icons.home_outlined,
                variant: RoyalButtonVariant.tertiary,
                onPressed: onMainMenu,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
