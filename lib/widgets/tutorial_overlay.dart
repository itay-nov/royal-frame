import 'package:flutter/material.dart';
import '../services/haptic_service.dart';
import '../theme_constants.dart';
import '../utils/localization.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Spotlight painter — blacks out everything except the listed rects.
// ─────────────────────────────────────────────────────────────────────────────
class OverlayHolePainter extends CustomPainter {
  final List<Rect> holes;
  const OverlayHolePainter(this.holes);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawColor(Colors.black.withValues(alpha: 0.82), BlendMode.srcOver);
    final clear = Paint()..blendMode = BlendMode.clear;
    for (final r in holes) {
      if (r.width > 0 && r.height > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(5), const Radius.circular(9)),
          clear,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(OverlayHolePainter old) => old.holes != holes;
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase A — Blocking welcome modals with per-step spotlights.
// ─────────────────────────────────────────────────────────────────────────────
class TutorialOverlay extends StatefulWidget {
  final void Function({bool skipped}) onFinish;
  final AppLang lang;
  final GlobalKey deckRowKey;
  final GlobalKey gridKey;
  final List<GlobalKey> cellKeys;

  const TutorialOverlay({
    super.key,
    required this.onFinish,
    required this.lang,
    required this.deckRowKey,
    required this.gridKey,
    required this.cellKeys,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  List<Rect> _holes = [];
  late final AnimationController _fadeCtrl;

  // ── Texts ──────────────────────────────────────────────────────────────────

  static const _stepsEn = [
    'Welcome to Royal Frame! This is your deck. Draw cards to fill the board.',
    'Royals (J, Q, K) must go in the outer frame. Try to complete all 12!',
    'Number cards go anywhere. The inner 4 slots are a great dump for numbers so you don\'t block Royals.',
    'Now try to fill the board with cards! (You cannot place a card on an occupied slot.) Once the table is full, you will clear pairs that sum exactly 11.',
  ];

  static const _stepsHe = [
    'ברוכים הבאים ל-Royal Frame! זו החפיסה שלך. משוך קלפים כדי למלא את הלוח.',
    'קלפי מלוכה (J, Q, K) חייבים להיות במסגרת החיצונית. כדי לנצח עליך להשלים את כל ה12!',
    'קלפי מספרים יכולים להיות בכל מקום. 4 המשבצות הפנימיות הן מקום מצוין לאחסן מספרים כדי לא לחסום מלוכה.',
    'כעת מלא את הלוח! (לא ניתן להניח קלף על משבצת תפוסה.) לאחר שהשולחן מלא, תפנה זוגות שסכומם 11 בדיוק.',
  ];

  List<String> get _steps =>
      widget.lang == AppLang.he ? _stepsHe : _stepsEn;
  bool get _isLast => _step == _steps.length - 1;

  // ── Spotlight geometry ─────────────────────────────────────────────────────

  // Step 0 → deck row only
  // Step 1 → outer 12 grid slots
  // Step 2 → inner 4 grid slots
  // Step 3 → entire grid
  static const _outerIndices = [0, 1, 2, 3, 4, 7, 8, 11, 12, 13, 14, 15];
  static const _innerIndices = [5, 6, 9, 10];

  // Modal position per step: avoid covering the spotlight.
  // Deck row is in the upper-middle area; grid is below it.
  static const _alignments = [
    Alignment.topCenter,    // step 0: deck row lit → modal just below deck
    Alignment.topCenter,    // step 1: outer grid lit → modal at top
    Alignment.topCenter,    // step 2: inner grid lit → modal at top
    Alignment.bottomCenter, // step 3: full grid lit → modal at bottom
  ];

  // Step 0: 158 px top margin clears the 150 px deck row + small gap.
  static const _margins = [
    EdgeInsets.fromLTRB(20, 158, 20, 0),  // step 0: sit right below deck row
    EdgeInsets.fromLTRB(20, 28, 20, 0),   // step 1
    EdgeInsets.fromLTRB(20, 28, 20, 0),   // step 2
    EdgeInsets.fromLTRB(20, 0, 20, 28),   // step 3
  ];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHoles());
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Rect _getRect(GlobalKey k) {
    final box = k.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox = context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null || !box.hasSize) return Rect.zero;
    // box and overlayBox are siblings in the Stack — overlay is NOT an ancestor
    // of box, so localToGlobal(ancestor: overlay) would assert. Compute the
    // relative position by subtracting global origins instead.
    final globalPos = box.localToGlobal(Offset.zero);
    final overlayOrigin = overlayBox.localToGlobal(Offset.zero);
    return (globalPos - overlayOrigin) & box.size;
  }

  void _updateHoles() {
    if (!mounted) return;
    List<Rect> next;
    switch (_step) {
      case 0:
        next = [_getRect(widget.deckRowKey)];
      case 1:
        next = _outerIndices
            .map((i) => _getRect(widget.cellKeys[i]))
            .toList();
      case 2:
        next = _innerIndices
            .map((i) => _getRect(widget.cellKeys[i]))
            .toList();
      default:
        next = [_getRect(widget.gridKey)];
    }
    next.removeWhere((r) => r.width == 0);
    setState(() => _holes = next);
  }

  void _goTo(int step) {
    _fadeCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() => _step = step);
      _fadeCtrl.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateHoles());
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isHe = widget.lang == AppLang.he;

    return Material(
      color: Colors.transparent,
      child: CustomPaint(
        painter: OverlayHolePainter(_holes),
        child: SafeArea(
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            alignment: _alignments[_step],
            child: Padding(
              padding: _margins[_step],
              child: Container(
                constraints: const BoxConstraints(maxWidth: 460),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                decoration: BoxDecoration(
                  color: kBurgundyLight,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kGold, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: kGold.withValues(alpha: 0.28),
                      blurRadius: 28,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Step counter
                    Text(
                      isHe
                          ? 'שלב ${_step + 1} / ${_steps.length}'
                          : 'Step ${_step + 1} / ${_steps.length}',
                      style: const TextStyle(
                        // kGoldLight for WCAG small-text contrast on the
                        // burgundy modal (kGold measures ~2.9:1 here).
                        color: kGoldLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Step text
                    FadeTransition(
                      opacity: _fadeCtrl,
                      child: Text(
                        _steps[_step],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: kGoldLight,
                          fontSize: 15,
                          height: 1.6,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Dot indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_steps.length, (i) {
                        final active = i == _step;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 10 : 7,
                          height: active ? 10 : 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: active ? kGold : Colors.transparent,
                            border: Border.all(
                              color: active ? kGold : kGoldDark,
                              width: 1.5,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 18),

                    // Navigation
                    Directionality(
                      textDirection:
                          isHe ? TextDirection.rtl : TextDirection.ltr,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            TextButton(
                              onPressed: () =>
                                  widget.onFinish(skipped: true),
                              child: Text(
                                isHe ? 'דלג' : 'Skip',
                                style:
                                    const TextStyle(color: kGoldDark),
                              ),
                            ),
                            if (_step > 0) ...[
                              const SizedBox(width: 2),
                              TextButton(
                                onPressed: () => _goTo(_step - 1),
                                child: Text(
                                  isHe ? 'חזור' : 'Back',
                                  style: const TextStyle(
                                      color: kGoldLight),
                                ),
                              ),
                            ],
                          ]),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: kGold,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 11),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onPressed: () {
                              HapticService.light();
                              if (_isLast) {
                                widget.onFinish(skipped: false);
                              } else {
                                _goTo(_step + 1);
                              }
                            },
                            child: Text(
                              _isLast
                                  ? (isHe ? "יאללה נשחק! 👑" : "Let's Play! 👑")
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
        ),
      ),
    );
  }
}
