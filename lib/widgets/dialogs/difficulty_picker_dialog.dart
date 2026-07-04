import 'package:flutter/material.dart';

import '../../models/game_model.dart';
import '../../services/haptic_service.dart';
import '../../theme_constants.dart';
import '../../utils/localization.dart';


// ─────────────────────────────────────────────────────────────────────────────
// DIFFICULTY PICKER DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class DifficultyPickerDialog extends StatefulWidget {
  final GameDifficulty current;
  final void Function(GameDifficulty) onSelected;
  final AppLang lang;

  const DifficultyPickerDialog({
    super.key,
    required this.current,
    required this.onSelected,
    required this.lang,
  });

  @override
  State<DifficultyPickerDialog> createState() =>
      _DifficultyPickerDialogState();
}

class _DifficultyPickerDialogState
    extends State<DifficultyPickerDialog> {
  late GameDifficulty _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  List<({GameDifficulty diff, String emoji, String name, String subtitle, Color accentLight, Color accentDark})> get _data {
    final isHe = widget.lang == AppLang.he;
    return [
      (
        diff: GameDifficulty.easy,
        emoji: '🌱',
        name: isHe ? 'קל' : 'Easy',
        subtitle: isHe ? 'מפנים זוגות מתי שרוצים.\nניקוד ×0.25' : 'Clear pairs whenever you want.\nScore ×0.25',
        accentLight: kDiffEasy,
        accentDark: kDiffEasyDark,
      ),
      (
        diff: GameDifficulty.medium,
        emoji: '☀️',
        name: isHe ? 'בינוני' : 'Medium',
        subtitle: isHe ? 'ללא מלכים — 8 תאי זבל.\nניקוד ×0.5' : 'No Kings — 8 dump slots.\nScore ×0.5',
        accentLight: kDiffMedium,
        accentDark: kDiffMediumDark,
      ),
      (
        diff: GameDifficulty.classic,
        emoji: '⚔️',
        name: isHe ? 'קלאסי' : 'Classic',
        subtitle: isHe ? 'חוקים רגילים.\nניקוד ×1.0' : 'Standard rules.\nScore ×1.0',
        accentLight: kGold,
        accentDark: kGoldDark,
      ),
      (
        diff: GameDifficulty.expert,
        emoji: '💣',
        name: isHe ? 'מומחה' : 'Expert',
        subtitle: isHe ? 'פצצה 3 דקות + מוות פתאומי.\nניקוד ×2.0' : '3-min bomb + Sudden Death.\nScore ×2.0',
        accentLight: kDiffExpert,
        accentDark: kCardRed,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 28, vertical: 60),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: kBurgundyDeep,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kGold, width: 1.8),
          boxShadow: [
            BoxShadow(
              color: kGold.withValues(alpha: 0.15),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
              decoration: BoxDecoration(
                color: kBurgundyLight.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune, color: kGold, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.lang == AppLang.he ? 'בחר רמת קושי' : 'Choose Difficulty',
                      style: const TextStyle(
                        color: kGold,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close,
                          color: kGoldDark, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // Difficulty tiles
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                children: _data.map((d) {
                  final isChosen = _selected == d.diff;
                  return GestureDetector(
                    onTap: () {
                      HapticService.light();
                      setState(() => _selected = d.diff);
                    },
                    child: AnimatedContainer(
                      duration:
                          const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isChosen
                            ? d.accentDark.withValues(alpha: 0.35)
                            : Colors.black.withValues(alpha: 0.25),
                        borderRadius:
                            BorderRadius.circular(14),
                        border: Border.all(
                          color: isChosen
                              ? d.accentLight
                              : Colors.white12,
                          width: isChosen ? 2.0 : 1.0,
                        ),
                        boxShadow: isChosen
                            ? [
                                BoxShadow(
                                  color: d.accentLight
                                      .withValues(alpha: 0.22),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          Text(d.emoji,
                              style: const TextStyle(
                                  fontSize: 30)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.name,
                                  style: TextStyle(
                                    color: isChosen
                                        ? d.accentLight
                                        : Colors.white,
                                    fontSize: 16,
                                    fontWeight:
                                        FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  d.subtitle,
                                  style: TextStyle(
                                    color: isChosen
                                        ? d.accentLight
                                            .withValues(alpha: 0.75)
                                        : Colors.white38,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AnimatedOpacity(
                            duration: const Duration(
                                milliseconds: 150),
                            opacity: isChosen ? 1.0 : 0.0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: d.accentLight,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check,
                                  color: Colors.black, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Confirm button
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  onPressed: () =>
                      widget.onSelected(_selected),
                  icon: const Icon(Icons.play_arrow_rounded,
                      size: 22),
                  label: Text(widget.lang == AppLang.he ? 'התחל משחק' : 'START GAME'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
