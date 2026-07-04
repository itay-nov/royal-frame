import 'package:flutter/material.dart';

import '../../models/game_model.dart';
import '../../theme_constants.dart';
import '../../utils/localization.dart';
import '../royal_button.dart';

/// Full-screen loss overlay. Pure visual: state comes in via constructor,
/// user intents leave via callbacks — persistence and XP accounting stay
/// with the caller.
class GameOverOverlay extends StatelessWidget {
  final GameState game;
  final AppLang lang;
  final int xpGained;
  final VoidCallback onTryAgain;
  final VoidCallback onChangeDifficulty;
  final VoidCallback onShare;
  final VoidCallback onMainMenu;

  const GameOverOverlay({
    super.key,
    required this.game,
    required this.lang,
    required this.xpGained,
    required this.onTryAgain,
    required this.onChangeDifficulty,
    required this.onShare,
    required this.onMainMenu,
  });

  @override
  Widget build(BuildContext context) {
    final l = L(lang);
    final deckLeft = game.cardsRemainingDisplay;
    const textShadow = [
      Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 2)),
    ];

    return Container(
      color: Colors.black.withValues(alpha: 0.40),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding:
              const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBlockedBorder, width: 1.8),
            boxShadow: [
              BoxShadow(
                color: kBlockedBorder.withValues(alpha: 0.28),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                game.isSuddenDeath ? '💣' : '💀',
                style: const TextStyle(fontSize: 48),
              ),
              const SizedBox(height: 10),
              Text(
                l.lossTitle,
                style: const TextStyle(
                  color: kBlockedBorder,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  shadows: textShadow,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                game.isSuddenDeath
                    ? 'One wrong move — and that\'s it.'
                    : l.lossSub,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    shadows: textShadow),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: kBurgundy.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: kGoldDark.withValues(alpha: 0.5), width: 1),
                ),
                child: Text(
                  l.lossCardsLeft(deckLeft),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: kGoldLight,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      shadows: textShadow),
                ),
              ),
              const SizedBox(height: 12),

              // XP consolation badge
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
                    const Icon(Icons.star_outline,
                        color: kGoldLight, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '+$xpGained XP  — keep going!',
                      style: const TextStyle(
                        color: kGoldLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              RoyalButton(
                label: l.lossBtn,
                icon: Icons.refresh,
                variant: RoyalButtonVariant.emphasized,
                expand: true,
                minHeight: 52,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                onPressed: onTryAgain,
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
                label: l.shareScoreBtn,
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
