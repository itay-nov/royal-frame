import 'package:flutter/material.dart';
import '../theme_constants.dart';
import '../utils/localization.dart';

class OverlayHolePainter extends CustomPainter {
  final List<Rect> holes;
  OverlayHolePainter(this.holes);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawColor(Colors.black.withOpacity(0.85), BlendMode.srcOver);

    final holePaint = Paint()..blendMode = BlendMode.clear;
    for (final rect in holes) {
      if (rect.width > 0 && rect.height > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(8)),
          holePaint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(OverlayHolePainter oldDelegate) => true;
}

class TutorialOverlay extends StatefulWidget {
  final void Function({bool skipped}) onFinish;
  final AppLang lang;
  final GlobalKey deckRowKey;
  final GlobalKey gridKey;
  final List<GlobalKey> cellKeys;
  final bool isClearPhase;

  const TutorialOverlay({
    super.key,
    required this.onFinish,
    required this.lang,
    required this.deckRowKey,
    required this.gridKey,
    required this.cellKeys,
    this.isClearPhase = false,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  int _step = 0;
  List<Rect> _holes = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHoles());
  }

  Rect _getRect(GlobalKey k) {
    final box = k.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox = context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return Rect.zero;
    final pos = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    return pos & box.size;
  }

  void _updateHoles() {
    if (!mounted) return;
    if (widget.isClearPhase) {
      _holes = [_getRect(widget.gridKey)];
    } else {
      if (_step == 0) {
        _holes = [_getRect(widget.deckRowKey)];
      } else if (_step == 1) {
        _holes = [
          0,
          1,
          2,
          3,
          4,
          7,
          8,
          11,
          12,
          13,
          14,
          15,
        ].map((i) => _getRect(widget.cellKeys[i])).toList();
      } else if (_step == 2) {
        _holes = [
          5,
          6,
          9,
          10,
        ].map((i) => _getRect(widget.cellKeys[i])).toList();
      } else if (_step == 3) {
        _holes = [_getRect(widget.gridKey)];
      }
    }
    _holes.removeWhere((r) => r.width == 0);
    setState(() {});
  }

  void _nextStep() {
    if (widget.isClearPhase || _step == 3) {
      widget.onFinish(skipped: false);
    } else {
      setState(() => _step++);
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateHoles());
    }
  }

  void _prevStep() {
    if (_step > 0) {
      setState(() => _step--);
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateHoles());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHe = widget.lang == AppLang.he;

    final texts = widget.isClearPhase
        ? (isHe
              ? [
                  '🧹 שלב הפינוי! הקש על שני קלפי מספרים שסכומם 11 כדי להסיר אותם. פנה כמה שיותר לפני המילוי מחדש!',
                ]
              : [
                  '🧹 Clear Phase! Tap two number cards that add up to 11 to remove them. Clear as many as you can before refilling!',
                ])
        : (isHe
              ? [
                  'הקש על החפיסה כדי למשוך קלף, ואז הקש על משבצת ריקה כדי להניח אותו. מלא את כל הלוח!',
                  '👑 קלפי מלוכה (J, Q, K) שייכים אך ורק ב-12 המשבצות החיצוניות. שמור על המסגרת מלכותית!',
                  '4 המשבצות המרכזיות הן "אזור ההשלכה" שלך — חנה כאן קלפי מספרים כדי שלא יחסמו את קלפי המלוכה.',
                  'מלא כל משבצת כדי להשלים את הלוח — ואז יתחיל שלב הפינוי!',
                ]
              : [
                  'Tap the deck to draw a card, then tap an empty slot to place it. Fill the whole board!',
                  '👑 Royals (J, Q, K) ONLY belong in the outer 12 slots. Keep the frame royal!',
                  'The 4 center slots are your "dump zone" — park number cards here so they don\'t block Royals.',
                  'Fill every slot to complete the board — then the Clear Phase begins!',
                ]);

    final alignments = widget.isClearPhase
        ? [Alignment.bottomCenter]
        : [
            Alignment.center,
            Alignment.center,
            Alignment.bottomCenter,
            Alignment.bottomCenter,
          ];

    final margins = widget.isClearPhase
        ? [const EdgeInsets.only(bottom: 60)]
        : [
            const EdgeInsets.only(top: 80),
            const EdgeInsets.all(0),
            const EdgeInsets.only(bottom: 60),
            const EdgeInsets.only(bottom: 60),
          ];

    return Material(
      color: Colors.transparent,
      child: CustomPaint(
        painter: OverlayHolePainter(_holes),
        child: SafeArea(
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: alignments[_step],
                child: Padding(
                  padding:
                      margins[_step] +
                      const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: kBurgundyLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kGold, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: kGold.withOpacity(0.3),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!widget.isClearPhase)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              isHe
                                  ? 'שלב ${_step + 1} / 4'
                                  : 'Step ${_step + 1} / 4',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: kGold,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        Text(
                          texts[_step],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: kGoldLight,
                            fontSize: 15,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!widget.isClearPhase) ...[
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(4, (i) {
                              final isCurrent = i == _step;
                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                width: isCurrent ? 10 : 8,
                                height: isCurrent ? 10 : 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isCurrent
                                      ? kGold
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: isCurrent ? kGold : kGoldDark,
                                    width: 1.5,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Directionality(
                          textDirection: isHe
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () =>
                                        widget.onFinish(skipped: true),
                                    child: Text(
                                      isHe ? 'דלג' : 'Skip',
                                      style: const TextStyle(color: kGoldDark),
                                    ),
                                  ),
                                  if (!widget.isClearPhase && _step > 0) ...[
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: _prevStep,
                                      child: Text(
                                        isHe ? 'חזור' : 'Back',
                                        style: const TextStyle(
                                          color: kGoldLight,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              FilledButton(
                                onPressed: _nextStep,
                                child: Text(
                                  widget.isClearPhase || _step == 3
                                      ? (isHe ? 'שחק!' : 'Play!')
                                      : (isHe ? 'הבא' : 'Next'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
