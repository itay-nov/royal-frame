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
                  'שלב הפינוי! עלייך לפנות קלפים ככל הניתן ורק אז תוכל למלא שוב.\n'
                  'בחר שני קלפי מספרים שסכומם 11 כדי לפנות אותם. נסה עכשיו!',
                ]
              : [
                  'Clear Phase! You must clear as many cards as possible — only then can you fill again.\n'
                  'Select two number cards that sum to exactly 11 to clear them. Try it now!',
                ])
        : (isHe
              ? [
                  'ברוך הבא ל-Royal Frame! זו החפיסה שלך. משוך קלפים כדי למלא את הלוח.',
                  'קלפי מלוכה (J, Q, K) חייבים להיות מונחים במסגרת החיצונית בלבד. נסה להשלים את כל ה-12!',
                  'קלפי מספרים יכולים להיות מונחים בכל מקום. 4 המשבצות הפנימיות הן "פח" מצוין לזרוק אליו מספרים מבלי לחסום מלוכה.',
                  'עכשיו נסה למלא את כל הלוח! כשהלוח יתמלא לגמרי, יתחיל שלב הפינוי בו תפנה זוגות.',
                ]
              : [
                  'Welcome to Royal Frame! This is your deck. Draw cards to fill the board.',
                  'Royals (J, Q, K) must go in the outer frame. Try to complete all 12!',
                  'Number cards go anywhere. The inner 4 slots are a great "dump" for numbers so you don\'t block Royals.',
                  'Now try to fill the board with cards! Once the table is full, you will clear pairs that sum to exactly 11.',
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
