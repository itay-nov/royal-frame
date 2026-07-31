import 'package:flutter/material.dart';

import '../theme_constants.dart';
import '../utils/localization.dart';
import 'royal_button.dart';

class RatingInvitationOverlay extends StatelessWidget {
  final AppLang lang;
  final VoidCallback onRateAndroidGame;
  final VoidCallback onDismiss;

  const RatingInvitationOverlay({
    super.key,
    required this.lang,
    required this.onRateAndroidGame,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final l = L(lang);
    final direction = lang == AppLang.he
        ? TextDirection.rtl
        : TextDirection.ltr;

    return Positioned.fill(
      child: Semantics(
        namesRoute: true,
        scopesRoute: true,
        explicitChildNodes: true,
        label: l.ratingInvitationSemanticLabel,
        child: Directionality(
          textDirection: direction,
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.72),
            child: SafeArea(
              minimum: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          constraints: const BoxConstraints(maxWidth: 440),
                          decoration: BoxDecoration(
                            color: kBurgundyLight,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: kGold, width: 2),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_outline,
                                color: kGold,
                                size: 44,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l.ratingInvitationTitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: kGold,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                l.ratingInvitationBody,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: kGoldLight,
                                  fontSize: 16,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 22),
                              RoyalButton(
                                label: l.ratingInvitationAction,
                                icon: Icons.open_in_new,
                                variant: RoyalButtonVariant.emphasized,
                                expand: true,
                                minHeight: 52,
                                onPressed: onRateAndroidGame,
                              ),
                              const SizedBox(height: 10),
                              RoyalButton(
                                label: l.ratingInvitationDismiss,
                                variant: RoyalButtonVariant.tertiary,
                                expand: true,
                                minHeight: 48,
                                onPressed: onDismiss,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
