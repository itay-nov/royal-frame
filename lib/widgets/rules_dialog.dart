import 'package:flutter/material.dart';
import '../theme_constants.dart';
import '../utils/localization.dart';
import '../services/tutorial_manager.dart';

class _RulePage {
  final Color color;
  final IconData icon;
  final String text;
  const _RulePage(this.color, this.icon, this.text);
}

const List<_RulePage> _hePages = [
  _RulePage(
    Color(0xFF4A1A2A),
    Icons.star,
    'קלפי מלוכה (מלך, מלכה, נסיך) חובה למקם במסגרת החיצונית במקומות '
        'הייעודיים. אפשר לגרור קלף או פשוט ללחוץ על המשבצת הייעודית.',
  ),
  _RulePage(
    Color(0xFF1A2A4A),
    Icons.grid_view,
    'קלפי מספרים אפשר לשים בכל מקום פנוי — במרכז או במסגרת החיצונית.',
  ),
  _RulePage(
    Color(0xFF1A3A2A),
    Icons.cleaning_services,
    'כשהלוח מתמלא, יש למצוא ולפנות זוגות של קלפי מספרים שסכומם 11. '
        'חובה לפנות את כל הזוגות האפשריים לפני שחוזרים להניח שוב!',
  ),
  _RulePage(
    Color(0xFF3A2A1A),
    Icons.emoji_events,
    'הניצחון מוכרז רק כשהמסגרת מלאה בקלפי מלוכה. אם יש עוד זוגות לפנות — '
        'מפנים, אך המטרה היא 12 קלפי מלוכה (או 8 ברמה הקלה).',
  ),
];

const List<_RulePage> _enPages = [
  _RulePage(
    Color(0xFF4A1A2A),
    Icons.star,
    'Royal cards (King, Queen, Jack) must be placed in their matching slots '
        'on the outer frame. You can drag a card or tap the target slot directly.',
  ),
  _RulePage(
    Color(0xFF1A2A4A),
    Icons.grid_view,
    'Number cards can be placed in any empty slot — center or outer frame.',
  ),
  _RulePage(
    Color(0xFF1A3A2A),
    Icons.cleaning_services,
    'When the board fills up, find and clear pairs of number cards that sum '
        'to 11. You must clear all available pairs before placing new cards!',
  ),
  _RulePage(
    Color(0xFF3A2A1A),
    Icons.emoji_events,
    'Victory is declared only when the outer frame is full of royals. '
        'Clear pairs along the way, but the goal is 12 royal cards (or 8 on Easy mode).',
  ),
];

class RulesDialog extends StatefulWidget {
  const RulesDialog({super.key, required this.lang});
  final AppLang lang;

  @override
  State<RulesDialog> createState() => _RulesDialogState();
}

class _RulesDialogState extends State<RulesDialog> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    final pages = widget.lang == AppLang.he ? _hePages : _enPages;
    if (index < 0 || index >= pages.length) return;
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.lang == AppLang.he ? _hePages : _enPages;
    final isHe = widget.lang == AppLang.he;
    return Directionality(
      textDirection: isHe ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        backgroundColor: kBurgundyLight,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: kGold, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '${_page + 1} / ${pages.length}',
                  style: const TextStyle(
                    color: kGold,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 360,
                child: PageView.builder(
                  controller: _controller,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) {
                    final p = pages[i];
                    return Column(
                      children: [
                        Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: p.color,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: kBlockedBorder, width: 1),
                          ),
                          child: Icon(p.icon, color: kGoldLight, size: 72),
                        ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Text(
                              p.text,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left button: always chevron_left, always on the left.
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kGoldLight,
                        side: const BorderSide(color: kGold),
                      ),
                      onPressed: isHe
                          ? (_page < pages.length - 1
                              ? () => _goTo(_page + 1)
                              : null)
                          : (_page > 0 ? () => _goTo(_page - 1) : null),
                      child: const Icon(Icons.chevron_left),
                    ),
                    Directionality(
                      textDirection: isHe ? TextDirection.rtl : TextDirection.ltr,
                      child: Row(
                        children: List.generate(pages.length, (i) {
                          final active = i == _page;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: active ? kGold : Colors.white30,
                            ),
                          );
                        }),
                      ),
                    ),
                    // Right button: always chevron_right, always on the right.
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kGoldLight,
                        side: const BorderSide(color: kGold),
                      ),
                      onPressed: isHe
                          ? (_page > 0 ? () => _goTo(_page - 1) : null)
                          : (_page < pages.length - 1
                              ? () => _goTo(_page + 1)
                              : null),
                      child: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.replay, color: kGoldLight),
                    label: Text(isHe ? 'הפעל מדריך מחדש' : 'Replay Tutorial',
                        style: const TextStyle(color: kGoldLight)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kGold)),
                    onPressed: () {
                      Navigator.pop(context);
                      TutorialManager.reset();
                    },
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(isHe ? 'סגור' : 'Close',
                        style: const TextStyle(
                            color: kGoldLight,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
