import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:audioplayers/audioplayers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// THEME CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────
const _kBurgundy         = Color(0xFF4A0E1A);
const _kBurgundyLight    = Color(0xFF6B1A2A);
const _kGold             = Color(0xFFD4AF37);
const _kGoldLight        = Color(0xFFF0D060);
const _kGoldDark         = Color(0xFF9A7B1A);
const _kCardWhite        = Color(0xFFFFFDF5);
const _kCardRed          = Color(0xFFB71C1C);
const _kCardBlack        = Color(0xFF1A1A1A);
const _kTableGreen       = Color(0xFF1A3A2A);
const _kTableGreenMid    = Color(0xFF254D38);
const _kSlotFrame        = Color(0xFF2E5C44);
const _kSlotFrameBorder  = Color(0xFF5AAE80);   // brighter than before
const _kSlotDumpBorder   = Color(0xFF2E4A3A);
const _kBlockedBg        = Color(0xFF3D1A1A);
const _kBlockedBorder    = Color(0xFFB06060);
const _kDragTarget       = Color(0xFF3D3010);
const _kDragTargetBorder = Color(0xFFE8C84A);

// Golden Royal colours
const _kRoyalGoldBg      = Color(0xFF3A2800);   // deep gold background
const _kRoyalGoldBorder  = Color(0xFFFFD700);   // bright gold border
const _kRoyalGlowColor   = Color(0xFFFFD700);   // glow tint

// Number cards (Ace–10), any slot — high contrast on dark green table
const _kNumberSilverBorder = Color(0xFFE0E0E0);

// Phase.clear reduction selection / pair highlights (distinct from royal / gold)
const _kSelectionNeonMagenta = Color(0xFFFF00FF);

// Classic bicycle-style card back (deckofcardsapi) via CORS proxy for web
const _kCardBackUrl =
    'https://corsproxy.io/?https://deckofcardsapi.com/static/img/back.png';
const _kCardBackUrlAlt =
    'https://corsproxy.io/?https://www.deckofcardsapi.com/static/img/back.png';

// 3D deck stack: card 72×100 + max 4-layer offset (left +3, bottom +6)
const _kDeckStackW = 78.0;
const _kDeckStackH = 108.0;
const _kDeckLayerOffsetX = 1.0;
const _kDeckLayerOffsetY = 2.0;

// ─────────────────────────────────────────────────────────────────────────────
// LOCALIZATION
// ─────────────────────────────────────────────────────────────────────────────
enum AppLang { he, en }

class L {
  final AppLang lang;
  const L(this.lang);
  bool get isHe => lang == AppLang.he;

  String get phaseInstructFill  => isHe ? 'הנח קלף'            : 'Place a Card';
  String get phaseInstructClear => isHe ? 'מצא זוגות של 11'    : 'Find pairs of 11';
  String get langToggleLabel    => isHe ? 'English'             : 'עברית';

  String get tooltipPeekAvail  => isHe ? 'הצצה (חד-פעמי)'  : 'Peek (one-time)';
  String get tooltipPeekUsed   => isHe ? 'הצצה נוצלה'       : 'Peek used';
  String get tooltipMoveAvail  => isHe ? 'הזזה (חד-פעמי)'  : 'Move (one-time)';
  String get tooltipMoveCancl  => isHe ? 'בטל הזזה'          : 'Cancel move';
  String get tooltipMoveUsed   => isHe ? 'הזזה נוצלה'        : 'Move used';
  String get tooltipUndo       => isHe ? 'בטל'                : 'Undo';
  String get tooltipRedo       => isHe ? 'חזור'               : 'Redo';
  String get tooltipNewGame    => isHe ? 'משחק חדש'           : 'New Game';
  String get tooltipRules      => isHe ? 'חוקים'              : 'Rules';
  String get tooltipMore       => isHe ? 'עוד'                : 'More';

  String get menuDebugShow  => isHe ? 'הצג כלי פיתוח'  : 'Show debug tools';
  String get menuDebugHide  => isHe ? 'הסתר כלי פיתוח' : 'Hide debug tools';

  String get labelDeck    => isHe ? 'חפיסה'     : 'Deck';
  String get labelCurrent => isHe ? 'קלף נוכחי' : 'Current';
  String get labelHidden  => isHe ? 'מוסתר'     : 'Hidden';
  String peekNext(String card) => isHe ? 'הבא: $card' : 'Next: $card';

  String get btnClearPair     => isHe ? 'פנה זוג'            : 'Clear Pair';
  String get btnResumeFill    => isHe ? 'המשך מילוי'         : 'Continue';
  String get tooltipPairsLeft => isHe ? 'יש עוד זוגות לפנות!' : 'More pairs to clear!';
  String get tooltipHintsShow => isHe ? 'הצג הדגשות'         : 'Show hints';
  String get tooltipHintsHide => isHe ? 'הסתר הדגשות'        : 'Hide hints';

  String get dbgPhase    => isHe ? 'פאזה'   : 'Phase';
  String get dbgCurrent  => isHe ? 'נוכחי'  : 'Current';
  String get dbgDeck     => isHe ? 'חפיסה'  : 'Deck';
  String get dbgRoyals   => isHe ? 'מלוכה'  : 'Royals';
  String get dbgGodMode  => isHe ? 'God Mode' : 'God Mode';
  String get dbgInstantWin => isHe ? 'Instant Win ⚡' : 'Instant Win ⚡';

  String get snackIllegal     => isHe ? 'מהלך לא חוקי'      : 'Illegal move';
  String get snackIllegalMove => isHe ? 'מהלך הזזה לא חוקי' : 'Illegal move';

  String get movePick => isHe ? 'בחר קלף להזזה'  : 'Pick a card to move';
  String get moveDrop => isHe ? 'בחר תא יעד ריק' : 'Pick an empty target';

  String get winTitle => isHe ? '!ניצחת'                : 'ROYAL WINNER!';
  String get winSub   => isHe ? '.המסגרת המלכותית הושלמה' : 'The Royal Frame is complete.';
  String get winBtn   => isHe ? 'משחק חדש'               : 'New Game';
  String get lossTitle => isHe ? 'Game Over' : 'GAME OVER';
  String get lossSub   => 'no moves left. hefsadeta ya kaka.';
  String get lossBtn   => isHe ? 'נסה שוב' : 'Try Again';
  String lossCardsLeft(int n) =>
      isHe ? 'קלפים שנשארו בחפיסה: $n' : 'Cards remaining in deck: $n';

  String get rulesTitle => isHe ? 'חוקים' : 'Rules';
  String get rulesBody  => isHe
      ? 'קלפי מלוכה (מלך, מלכה, נסיך) חובה למקם במסגרת החיצונית בלבד. '
        'קלפי מספרים אפשר לשים בכל מקום פנוי. '
        'כשהלוח מתמלא, יש למצוא ולפנות זוגות של קלפי מספרים שסכומם 11. '
        'חובה לפנות את כל הקלפים האפשריים לפני שחוזרים להניח שוב! '
        'הניצחון מוכרז רק כשהמסגרת מלאה במלוכה, החפיסה נגמרה, ואין זוגות 11 לפנות. '
        'המטרה: למלא את כל 12 משבצות המסגרת בקלפי מלוכה. תהנו!'
      : 'King, Queen, Jack must go in the outer frame. '
        'Match pairs of numbers that sum to 11 to clear space. '
        'You must clear all possible pairs before you can proceed to place cards again! '
        'Win is declared only when the frame holds 12 royals, the deck is empty, and no 11-pairs remain. '
        'Fill the frame to win. Enjoy!';

  String slotLabel(SlotType t) {
    if (isHe) {
      return switch (t) {
        SlotType.kingCorner => 'מלך',
        SlotType.queenEdge  => 'מלכה',
        SlotType.jackEdge   => 'נסיך',
        SlotType.innerDump  => '',
      };
    }
    return switch (t) {
      SlotType.kingCorner => 'K',
      SlotType.queenEdge  => 'Q',
      SlotType.jackEdge   => 'J',
      SlotType.innerDump  => '',
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP ROOT
// ─────────────────────────────────────────────────────────────────────────────
void main() => runApp(const RoyalFrameApp());

class RoyalFrameApp extends StatelessWidget {
  const RoyalFrameApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Royal Frame',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFD4AF37),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _kBurgundy,
        appBarTheme: const AppBarTheme(
          backgroundColor: _kBurgundyLight,
          foregroundColor: _kGold,
          elevation: 0,
          titleSpacing: 16,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _kGold,
            foregroundColor: _kBurgundy,
            textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: _kGoldLight),
        ),
      ),
      home: const BoardScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GAME MODEL
// ─────────────────────────────────────────────────────────────────────────────
enum SlotType { kingCorner, queenEdge, jackEdge, innerDump }
enum Phase    { fill, clear, winner, gameOver }

const int kMaxCardsForClear = 2;

sealed class Rank { const Rank(); }
class Ace   extends Rank { const Ace(); }
class Num   extends Rank { final int value; const Num(this.value); }
class Jack  extends Rank { const Jack(); }
class Queen extends Rank { const Queen(); }
class King  extends Rank { const King(); }

enum Suit { spade, heart, diamond, club }

String suitSymbol(Suit s) => switch (s) {
  Suit.spade   => '♠',
  Suit.heart   => '♥',
  Suit.diamond => '♦',
  Suit.club    => '♣',
};
bool isRed(Suit s) => s == Suit.heart || s == Suit.diamond;

class CardModel {
  final Suit suit;
  final Rank rank;
  const CardModel(this.suit, this.rank);

  bool get isK => rank is King;
  bool get isQ => rank is Queen;
  bool get isJ => rank is Jack;
  bool get isNumOrAce => rank is Ace || rank is Num;
  int get valueForSum => switch (rank) {
    Ace()             => 1,
    Num(:final value) => value,
    _                 => 0,
  };
  String get label => switch (rank) {
    King()            => 'K',
    Queen()           => 'Q',
    Jack()            => 'J',
    Ace()             => 'A',
    Num(:final value) => '$value',
  };

  /// Rank segment for playing-cards-assets PNG filenames.
  String get assetRankName => switch (rank) {
    King()            => 'king',
    Queen()           => 'queen',
    Jack()            => 'jack',
    Ace()             => 'ace',
    Num(:final value) => '$value',
  };

  /// Plural suit segment for playing-cards-assets PNG filenames.
  String get assetSuitName => switch (suit) {
    Suit.spade   => 'spades',
    Suit.heart   => 'hearts',
    Suit.diamond => 'diamonds',
    Suit.club    => 'clubs',
  };

  static const _kCardAssetBase =
      'https://raw.githubusercontent.com/HEB/playing-cards-assets/master/png';
  static const _kCardAssetCorsProxy = 'https://corsproxy.io/?';

  String get imageUrl {
    final direct = '$_kCardAssetBase/${assetRankName}_of_$assetSuitName.png';
    return '$_kCardAssetCorsProxy$direct';
  }
}

List<SlotType> buildBoardLayout() {
  final s = List.filled(16, SlotType.innerDump);
  for (final i in [0, 3, 12, 15])  s[i] = SlotType.kingCorner;
  for (final i in [1, 2, 13, 14])  s[i] = SlotType.queenEdge;
  for (final i in [4, 8, 7, 11])   s[i] = SlotType.jackEdge;
  return s;
}

// ─────────────────────────────────────────────────────────────────────────────
// GAME STATE
// ─────────────────────────────────────────────────────────────────────────────
class GameState {
  final List<SlotType> layout;
  final List<CardModel?> cells;
  final List<bool> isBlocked;
  final List<CardModel> drawPile;
  final int initialDeckCount;
  final int seed;
  CardModel? current;
  Phase phase;
  final Set<int> selectedForClear;
  bool lifelineMoveAvailable;
  bool lifelinePeekAvailable;
  bool peekActiveNow;

  GameState._({
    required this.layout,
    required this.cells,
    required this.isBlocked,
    required this.drawPile,
    required this.initialDeckCount,
    required this.seed,
    required this.current,
    required this.phase,
    required this.selectedForClear,
    required this.lifelineMoveAvailable,
    required this.lifelinePeekAvailable,
    required this.peekActiveNow,
  });

  factory GameState.newGame({int? seed}) {
    final layout  = buildBoardLayout();
    final cells   = List<CardModel?>.filled(16, null);
    final blocked = List<bool>.filled(16, false);
    final effectiveSeed = seed ?? DateTime.now().millisecondsSinceEpoch;
    final rng = Random(effectiveSeed);

    final deck = <CardModel>[];
    for (final suit in Suit.values) {
      deck.add(CardModel(suit, const Ace()));
      for (int v = 2; v <= 10; v++) deck.add(CardModel(suit, Num(v)));
      deck.addAll([
        CardModel(suit, const Jack()),
        CardModel(suit, const Queen()),
        CardModel(suit, const King()),
      ]);
    }
    deck.shuffle(rng);
    final initialCount = deck.length;
    final drawPile = deck;
    final current  = drawPile.removeLast();

    return GameState._(
      layout: layout, cells: cells, isBlocked: blocked,
      drawPile: drawPile, initialDeckCount: initialCount,
      seed: effectiveSeed, current: current, phase: Phase.fill,
      selectedForClear: <int>{},
      lifelineMoveAvailable: true,
      lifelinePeekAvailable: true,
      peekActiveNow: false,
    );
  }

  GameState clone() => GameState._(
    layout: List<SlotType>.from(layout),
    cells: List<CardModel?>.from(cells),
    isBlocked: List<bool>.from(isBlocked),
    drawPile: List<CardModel>.from(drawPile),
    initialDeckCount: initialDeckCount, seed: seed,
    current: current, phase: phase,
    selectedForClear: Set<int>.from(selectedForClear),
    lifelineMoveAvailable: lifelineMoveAvailable,
    lifelinePeekAvailable: lifelinePeekAvailable,
    peekActiveNow: peekActiveNow,
  );

  List<int> _idxOf(SlotType t) =>
      [for (int i = 0; i < layout.length; i++) if (layout[i] == t) i];

  bool get boardFull => cells.every((c) => c != null);
  int  get remainingInDeck => drawPile.length;

  /// Cards left to see: pile + current card in hand.
  int  get cardsRemainingDisplay => drawPile.length + (current != null ? 1 : 0);

  /// True when there is absolutely nothing left to draw or place.
  bool get deckExhausted => drawPile.isEmpty && current == null;

  int get royalsPlacedCorrect {
    int c = 0;
    for (final i in _idxOf(SlotType.kingCorner)) if (cells[i]?.isK == true && !isBlocked[i]) c++;
    for (final i in _idxOf(SlotType.queenEdge))  if (cells[i]?.isQ == true && !isBlocked[i]) c++;
    for (final i in _idxOf(SlotType.jackEdge))   if (cells[i]?.isJ == true && !isBlocked[i]) c++;
    return c;
  }
  double get royalsProgress => royalsPlacedCorrect / 12.0;

  bool get hasAnyPairFor11 {
    final vals = <int>[];
    for (int i = 0; i < 16; i++) {
      final c = cells[i];
      if (c != null && c.isNumOrAce) vals.add(c.valueForSum);
    }
    for (int a = 0; a < vals.length; a++)
      for (int b = a + 1; b < vals.length; b++)
        if (vals[a] + vals[b] == 11) return true;
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN CONDITION
  // ═══════════════════════════════════════════════════════════════════════════

  // WIN: 12 correct royals in frame + deck fully exhausted + no pairs left.
  bool get isWinConditionMet =>
      royalsPlacedCorrect == 12 &&
      deckExhausted &&
      !hasAnyPairFor11;

  // ═══════════════════════════════════════════════════════════════════════════
  // PLACEMENT LEGALITY HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// True when the 12 outer-frame slots are all occupied (by anything).
  bool get frameFull =>
      _idxOf(SlotType.kingCorner).every((i) => cells[i] != null) &&
      _idxOf(SlotType.queenEdge) .every((i) => cells[i] != null) &&
      _idxOf(SlotType.jackEdge)  .every((i) => cells[i] != null);

  /// Returns every board index that is a *legally-allowed* slot for [card],
  /// regardless of whether it is currently occupied or empty.
  ///
  /// For number/ace cards every slot is allowed (they can go anywhere).
  /// For royals only the matching, non-blocked frame slots are allowed.
  List<int> _allowedSlotsFor(CardModel card) {
    final result = <int>[];
    for (int i = 0; i < 16; i++) {
      final st = layout[i];
      if (card.isNumOrAce) {
        result.add(i);
      } else if (card.isK && st == SlotType.kingCorner && !isBlocked[i]) {
        result.add(i);
      } else if (card.isQ && st == SlotType.queenEdge  && !isBlocked[i]) {
        result.add(i);
      } else if (card.isJ && st == SlotType.jackEdge   && !isBlocked[i]) {
        result.add(i);
      }
    }
    return result;
  }

  /// True iff [card] can be placed immediately (at least one allowed slot is empty).
  bool _cardHasLegalPlacement(CardModel card) =>
      _allowedSlotsFor(card).any((i) => cells[i] == null);

  /// During [Phase.fill], true only when [current] can be placed on an empty legal slot.
  bool hasAnyLegalMove() {
    if (phase != Phase.fill) return true;
    if (current == null) return false;
    return _cardHasLegalPlacement(current!);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE STATE MACHINE  —  _evaluatePhaseAfterChange()
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Strict fill rule: while phase == fill and current != null, the only legal
  // action is placing [current] on an empty slot allowed for that card. If none
  // exists, game over immediately — 11-pairs do not rescue a stuck hand card.
  //
  //  1. Win (12 royals + deck exhausted + no pairs)     → Phase.winner
  //  2. fill + card in hand
  //       legal empty slot exists                       → stay Phase.fill
  //       no legal empty slot                           → Phase.gameOver
  //  3. fill + no card in hand
  //       12 royals + no pairs                          → Phase.winner
  //       pairs on board                                → Phase.clear
  //       else                                          → Phase.gameOver
  //  4. clear
  //       win                                           → Phase.winner
  //       pairs remain                                  → stay Phase.clear
  //       no pairs + empty cells + deck/hand exhausted  → winner / gameOver
  //       no pairs + empty cells + can resume           → stay (Resume Fill)
  //       no pairs + board full                         → Phase.gameOver

  void _evaluatePhaseAfterChange() {
    if (isWinConditionMet) {
      phase = Phase.winner;
      return;
    }

    if (phase == Phase.fill && current != null) {
      if (_cardHasLegalPlacement(current!)) return;
      phase = Phase.gameOver;
      return;
    }

    if (phase == Phase.fill && current == null) {
      if (royalsPlacedCorrect == 12 && !hasAnyPairFor11) {
        phase = Phase.winner;
        return;
      }
      if (hasAnyPairFor11) {
        phase = Phase.clear;
        selectedForClear.clear();
      } else {
        phase = Phase.gameOver;
      }
      return;
    }

    if (phase == Phase.clear) {
      if (isWinConditionMet) {
        phase = Phase.winner;
        return;
      }
      if (hasAnyPairFor11) return;

      if (cells.any((c) => c == null)) {
        if (current == null && drawPile.isEmpty) {
          phase = royalsPlacedCorrect == 12 ? Phase.winner : Phase.gameOver;
          return;
        }
        return;
      }

      phase = Phase.gameOver;
      return;
    }
  }

  /// Called on game-start and after undo/redo restore.
  void evaluateGameOverInFill() {
    if (phase == Phase.fill) _evaluatePhaseAfterChange();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLACEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  bool tryPlaceAt(int index, {bool godMode = false}) {
    if (phase != Phase.fill || current == null || cells[index] != null) return false;
    final st   = layout[index];
    final card = current!;

    if (godMode) {
      cells[index]     = card;
      isBlocked[index] = false;
      _afterPlacement();
      return true;
    }

    if (card.isNumOrAce) {
      cells[index]     = card;
      isBlocked[index] = (st != SlotType.innerDump);
      _afterPlacement();
      return true;
    }
    if (card.isK && st == SlotType.kingCorner && !isBlocked[index]) { cells[index] = card; _afterPlacement(); return true; }
    if (card.isQ && st == SlotType.queenEdge  && !isBlocked[index]) { cells[index] = card; _afterPlacement(); return true; }
    if (card.isJ && st == SlotType.jackEdge   && !isBlocked[index]) { cells[index] = card; _afterPlacement(); return true; }
    return false;
  }

  void _afterPlacement() {
    peekActiveNow = false;

    // ── Suspense-reveal gate (השהיית הקלף) ─────────────────────────────────
    // אם הלוח התמלא בדיוק עכשיו ויש עוד קלפים בקופה
    if (boardFull && drawPile.isNotEmpty) {
      current = null; // הקלף הבא נשאר מוסתר
      
      // אם יש מה לצמצם - עבור לשלב צמצום
      if (hasAnyPairFor11) {
        phase = Phase.clear;
        selectedForClear.clear();
      } else {
        // אם הלוח מלא ואין זוגות - זה סוף המשחק! (פותר את באג הלוח המת)
        phase = Phase.gameOver;
      }
      return; 
    }

    // ── Normal path ────────────────────────────────────────────────────────
    // אם הלוח לא מלא, משוך את הקלף הבא ובדוק מה המצב
    current = drawPile.isNotEmpty ? drawPile.removeLast() : null;
    _evaluatePhaseAfterChange();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEAR PHASE
  // ═══════════════════════════════════════════════════════════════════════════

  void toggleSelectForClear(int index) {
    if (phase != Phase.clear) return;
    final c = cells[index];
    if (c == null || !c.isNumOrAce) return;
    if (!selectedForClear.add(index)) selectedForClear.remove(index);
  }

  bool get canClearSelection {
    if (selectedForClear.length != kMaxCardsForClear) return false;
    return selectedForClear.map((i) => cells[i]!.valueForSum).fold(0, (a, b) => a + b) == 11;
  }

  void performClear() {
    if (!canClearSelection) return;
    for (final i in selectedForClear) { cells[i] = null; isBlocked[i] = false; }
    selectedForClear.clear();
    _evaluatePhaseAfterChange();
  }

  // ── Resume Fill ──────────────────────────────────────────────────────────
  bool get canResumeFill =>
      phase == Phase.clear &&
      !hasAnyPairFor11 &&
      cells.any((c) => c == null) &&
      (current != null || drawPile.isNotEmpty);

  bool resumeFill() {
    if (!canResumeFill) return false;
    phase = Phase.fill;
    if (current == null && drawPile.isNotEmpty) current = drawPile.removeLast();
    _evaluatePhaseAfterChange();
    return true;
  }


  // ── Lifelines ────────────────────────────────────────────────────────────
  bool activatePeek() {
    if (!lifelinePeekAvailable || drawPile.isEmpty) return false;
    lifelinePeekAvailable = false;
    peekActiveNow = true;
    return true;
  }
  CardModel? get peekCard => (peekActiveNow && drawPile.isNotEmpty) ? drawPile.last : null;

  bool moveCard(int from, int to, {bool godMode = false}) {
    if (!cells.asMap().containsKey(from) || !cells.asMap().containsKey(to)) return false;
    if (cells[from] == null || cells[to] != null) return false;
    final c    = cells[from]!;
    final stTo = layout[to];

    if (godMode) {
      cells[to]       = c;
      isBlocked[to]   = false;
      cells[from]     = null;
      isBlocked[from] = false;
      return true;
    }

    if (c.isK && stTo != SlotType.kingCorner) return false;
    if (c.isQ && stTo != SlotType.queenEdge)  return false;
    if (c.isJ && stTo != SlotType.jackEdge)   return false;
    if (c.isK || c.isQ || c.isJ) {
      cells[to] = c; isBlocked[to] = false; cells[from] = null; isBlocked[from] = false;
      _evaluatePhaseAfterChange(); return true;
    }
    cells[to] = c; isBlocked[to] = (stTo != SlotType.innerDump);
    cells[from] = null; isBlocked[from] = false;
    _evaluatePhaseAfterChange(); return true;
  }

  // ── Dev: Instant Win ──────────────────────────────────────────────────────
  void applyInstantWin() {
    for (int i = 0; i < 16; i++) { cells[i] = null; isBlocked[i] = false; }
    selectedForClear.clear();
    drawPile.clear();
    current = null;

    const kings  = [Suit.spade, Suit.heart, Suit.diamond, Suit.club];
    const queens = [Suit.spade, Suit.heart, Suit.diamond, Suit.club];
    const jacks  = [Suit.spade, Suit.heart, Suit.diamond, Suit.club];
    int ki = 0, qi = 0, ji = 0;
    for (int i = 0; i < 16; i++) {
      switch (layout[i]) {
        case SlotType.kingCorner: cells[i] = CardModel(kings[ki++],  const King());
        case SlotType.queenEdge:  cells[i] = CardModel(queens[qi++], const Queen());
        case SlotType.jackEdge:   cells[i] = CardModel(jacks[ji++],  const Jack());
        case SlotType.innerDump:  break;
      }
    }
    phase = Phase.winner;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOARD SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});
  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  late GameState game;
  final List<GameState> _undo = [];
  final List<GameState> _redo = [];

  bool _showClearHints  = false;
  bool _moveMode        = false;
  int? _moveFromIndex;
  bool _showDebugTools  = false;

  bool _godMode         = false;

  CardModel? _draggingCard;

  AppLang _lang = AppLang.he;
  L get _l => L(_lang);

  bool _showGameOverOverlay = false;

  // Audio
  final AudioPlayer _winPlayer  = AudioPlayer();
  final AudioPlayer _lossPlayer = AudioPlayer();
  final AudioPlayer _popPlayer  = AudioPlayer();
  bool _audioUnlocked = false;

  // Confetti
  late ConfettiController _confettiCtrl;

  @override
  void initState() {
    super.initState();
    _confettiCtrl = ConfettiController(duration: const Duration(seconds: 6));
    game = GameState.newGame();
    game.evaluateGameOverInFill();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await _winPlayer.setReleaseMode(ReleaseMode.stop);
      await _lossPlayer.setReleaseMode(ReleaseMode.stop);
      await _popPlayer.setReleaseMode(ReleaseMode.stop);
      await _winPlayer.setSourceAsset('audio/win_cheer.mp3');
      await _lossPlayer.setSourceAsset('audio/game_over.mp3');
      await _popPlayer.setSourceAsset('audio/pop.mp3');
    } catch (_) {}
  }

  void _unlockAudio() {
    if (_audioUnlocked) return;
    _audioUnlocked = true;
    _doUnlock();
  }
  Future<void> _doUnlock() async {
    try {
      for (final p in [_winPlayer, _lossPlayer, _popPlayer]) {
        await p.setVolume(0); await p.resume(); await p.stop(); await p.setVolume(1);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _confettiCtrl.dispose();
    _winPlayer.dispose(); _lossPlayer.dispose(); _popPlayer.dispose();
    super.dispose();
  }

  Future<void> _playWin()  async { try { await _winPlayer.stop();  await _winPlayer.play(AssetSource('audio/win_cheer.mp3')); } catch (_) {} }
  Future<void> _playLoss() async { try { await _lossPlayer.stop(); await _lossPlayer.play(AssetSource('audio/game_over.mp3')); } catch (_) {} }
  Future<void> _playPop()  async { try { await _popPlayer.stop();  await _popPlayer.play(AssetSource('audio/pop.mp3')); } catch (_) {} }

  // ── State helpers ─────────────────────────────────────────────────────────
  void _pushUndo() { _undo.add(game.clone()); _redo.clear(); }

  void _undoAction() {
    if (_undo.isEmpty) return;
    _redo.add(game.clone());
    setState(() {
      game = _undo.removeLast();
      _moveMode = false; _moveFromIndex = null;
      _showGameOverOverlay = game.phase == Phase.gameOver;
    });
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    _undo.add(game.clone());
    setState(() {
      game = _redo.removeLast();
      _moveMode = false; _moveFromIndex = null;
      _showGameOverOverlay = game.phase == Phase.gameOver;
    });
  }

  void _newGame({int? seed}) {
    _confettiCtrl.stop();
    setState(() {
      _undo.clear(); _redo.clear();
      game = GameState.newGame(seed: seed);
      game.evaluateGameOverInFill();
      _moveMode = false; _moveFromIndex = null;
      _showGameOverOverlay = false;
      _godMode = false;
    });
  }

  void _checkEndState() {
    if (game.phase == Phase.winner) {
      setState(() => _showGameOverOverlay = false);
      _confettiCtrl.play();
      _playWin();
    } else if (game.phase == Phase.gameOver) {
      setState(() => _showGameOverOverlay = false);
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && game.phase == Phase.gameOver) {
          setState(() => _showGameOverOverlay = true);
          _playLoss();
        }
      });
    }
  }

  // ── Cell tap ──────────────────────────────────────────────────────────────
  void _onTapCell(int i) {
    _unlockAudio();
    if (_moveMode) {
      if (_moveFromIndex == null) {
        if (game.cells[i] != null) setState(() => _moveFromIndex = i);
      } else {
        if (game.cells[i] == null) {
          _pushUndo();
          final ok = game.moveCard(_moveFromIndex!, i, godMode: _godMode);
          setState(() {
            if (ok) {
              HapticFeedback.selectionClick();
              _moveFromIndex = null;
              if (!_godMode) {
                _moveMode = false;
                game.lifelineMoveAvailable = false;
              }
            } else {
              _moveFromIndex = null;
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_l.snackIllegalMove)));
            }
          });
          if (ok) _checkEndState();
        } else {
          setState(() => _moveFromIndex = i);
        }
      }
      return;
    }
    if (game.phase == Phase.fill) {
      _pushUndo();
      final ok = game.tryPlaceAt(i, godMode: _godMode);
      if (ok) HapticFeedback.lightImpact();
      setState(() {});
      _checkEndState();
    } else if (game.phase == Phase.clear) {
      setState(() => game.toggleSelectForClear(i));
    }
  }

  void _doClear() {
    if (!game.canClearSelection) return;
    _pushUndo();
    setState(() => game.performClear());
    HapticFeedback.selectionClick();
    _playPop();
    _checkEndState();
  }

  void _resumeFill() {
    if (!game.canResumeFill) return;
    _pushUndo();
    setState(() => game.resumeFill());
    _checkEndState();
  }

  // ── Drag highlights ───────────────────────────────────────────────────────
  Set<int> _computeDragHighlights() {
    final card = _draggingCard;
    if (card == null || game.current == null) return {};
    final result = <int>{};
    for (int i = 0; i < 16; i++) {
      if (game.cells[i] != null) continue;
      if (_godMode) { result.add(i); continue; }
      final type = game.layout[i];
      if (card.isNumOrAce) {
        result.add(i);
      } else if (card.isK && type == SlotType.kingCorner && !game.isBlocked[i]) {
        result.add(i);
      } else if (card.isQ && type == SlotType.queenEdge  && !game.isBlocked[i]) {
        result.add(i);
      } else if (card.isJ && type == SlotType.jackEdge   && !game.isBlocked[i]) {
        result.add(i);
      }
    }
    return result;
  }

  // ── Clear pair highlights ─────────────────────────────────────────────────
  Set<int> _highlightClearableIndices() {
    if (game.phase != Phase.clear || !_showClearHints) return {};
    final nums = <int, int>{};
    for (int i = 0; i < game.cells.length; i++) {
      final c = game.cells[i];
      if (c != null && c.isNumOrAce) nums[i] = c.valueForSum;
    }
    final idxList = nums.keys.toList();
    final result  = <int>{};
    for (int a = 0; a < idxList.length; a++)
      for (int b = a + 1; b < idxList.length; b++)
        if (nums[idxList[a]]! + nums[idxList[b]]! == 11)
          result..add(idxList[a])..add(idxList[b]);
    return result;
  }

  // ── Rules ─────────────────────────────────────────────────────────────────
  void _showRules() {
    final isWide = MediaQuery.of(context).size.width > 700;
    final content = Directionality(
      textDirection: _lang == AppLang.he ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        color: _kBurgundyLight,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_l.rulesTitle,
                style: const TextStyle(color: _kGold, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 16),
            Text(_l.rulesBody,
                style: const TextStyle(color: _kGoldLight, fontSize: 14, height: 1.7)),
          ],
        ),
      ),
    );
    if (isWide) {
      showDialog(context: context, builder: (_) => Dialog(child: SizedBox(width: 460, child: content)));
    } else {
      showModalBottomSheet(
        context: context, showDragHandle: true, backgroundColor: _kBurgundyLight,
        builder: (_) => content,
      );
    }
  }

  // ── Overflow menu ─────────────────────────────────────────────────────────
  Widget _overflowMenu() {
    return PopupMenuButton<String>(
      tooltip: _l.tooltipMore,
      icon: const Icon(Icons.more_vert, color: _kGold),
      color: _kBurgundyLight,
      onSelected: (v) {
        switch (v) {
          case 'lang':  setState(() => _lang = _lang == AppLang.he ? AppLang.en : AppLang.he);
          case 'debug': setState(() => _showDebugTools = !_showDebugTools);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'lang',
          child: ListTile(
            leading: const Icon(Icons.language, color: _kGold),
            title: Text(_l.langToggleLabel, style: const TextStyle(color: _kGoldLight)),
          )),
        PopupMenuItem(value: 'debug',
          child: ListTile(
            leading: Icon(_showDebugTools ? Icons.settings : Icons.settings_outlined, color: _kGold),
            title: Text(_showDebugTools ? _l.menuDebugHide : _l.menuDebugShow,
                style: const TextStyle(color: _kGoldLight)),
          )),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CARD WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  static const double _kCardW = 72.0;
  static const double _kCardH = 100.0;

  /// Layer count for the stacked deck visual from remaining card count.
  int _deckStackLayers(int remaining) {
    if (remaining <= 0) return 0;
    if (remaining > 30) return 4;
    if (remaining >= 15) return 3;
    return 2;
  }

  Widget _playingCardFallback(CardModel c, {required double w, required double h}) {
    final faceColor = isRed(c.suit) ? _kCardRed : _kCardBlack;
    final large = w > _kCardW;
    return Container(
      width: w, height: h,
      color: _kCardWhite,
      padding: const EdgeInsets.all(6),
      child: Stack(children: [
        Align(
          alignment: Alignment.topLeft,
          child: Text(
            '${c.label}\n${suitSymbol(c.suit)}',
            style: TextStyle(
              fontSize: large ? 17.0 : 14.0,
              fontWeight: FontWeight.w900,
              height: 1.05,
              color: faceColor,
              fontFamily: 'Georgia',
            ),
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: Text(
            suitSymbol(c.suit),
            style: TextStyle(fontSize: large ? 36.0 : 28.0, color: faceColor),
          ),
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Transform.rotate(
            angle: pi,
            child: Text(
              '${c.label}\n${suitSymbol(c.suit)}',
              style: TextStyle(
                fontSize: large ? 17.0 : 14.0,
                fontWeight: FontWeight.w900,
                height: 1.05,
                color: faceColor,
                fontFamily: 'Georgia',
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _cardFaceImage(
    CardModel c, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    return Image.network(
      c.imageUrl,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _cardFaceFallbackSized(context, c, width, height);
      },
      errorBuilder: (context, _, __) =>
          _cardFaceFallbackSized(context, c, width, height),
    );
  }

  Widget _cardFaceFallbackSized(
    BuildContext context,
    CardModel c,
    double? width,
    double? height,
  ) {
    if (width != null && height != null && width > 0 && height > 0) {
      return _playingCardFallback(c, w: width, h: height);
    }
    return LayoutBuilder(
      builder: (context, constraints) => _playingCardFallback(
        c,
        w: constraints.maxWidth,
        h: constraints.maxHeight,
      ),
    );
  }

  Widget _playingCard(CardModel c, {bool large = false, bool dimmed = false}) {
    final w = large ? 90.0 : _kCardW;
    final h = large ? 126.0 : _kCardH;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: dimmed ? 0.45 : 1,
      child: SizedBox(
        width: w,
        height: h,
        child: Material(
          elevation: 6,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kGoldDark, width: 1.6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _cardFaceImage(c, width: w, height: h),
            ),
          ),
        ),
      ),
    );
  }

  /// Card face for a grid cell — inset so colored borders stay visible.
  Widget _gridCardFace(CardModel card) {
    const innerPad = 3.0;
    const imageRadius = 4.0;

    return Padding(
      padding: const EdgeInsets.all(innerPad),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(imageRadius),
        child: _cardFaceImage(card),
      ),
    );
  }

  Widget _cardBackFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Opacity(
          opacity: 0.4,
          child: Icon(Icons.grid_4x4_rounded, size: 36, color: Colors.white70),
        ),
      ),
    );
  }

  Widget _cardBackImage() {
    return Image.network(
      _kCardBackUrl,
      width: _kCardW,
      height: _kCardH,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _cardBackFallback();
      },
      errorBuilder: (_, __, ___) => Image.network(
        _kCardBackUrlAlt,
        width: _kCardW,
        height: _kCardH,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _cardBackFallback(),
      ),
    );
  }

  Widget _cardBackLayer({int depth = 0}) {
    return Container(
      width: _kCardW,
      height: _kCardH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: depth == 0 ? _kGold.withOpacity(0.9) : _kGoldDark.withOpacity(0.75),
          width: depth == 0 ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30 + depth * 0.06),
            blurRadius: 2.5 + depth * 1.5,
            spreadRadius: depth * 0.3,
            offset: Offset(0.8 + depth * 0.6, 1.5 + depth * 1.2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _cardBackImage(),
      ),
    );
  }

  Widget _cardBackWidget() => _cardBackLayer();

  Widget _emptyDeckSlot() {
    return Container(
      width: _kCardW,
      height: _kCardH,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kGoldDark.withOpacity(0.55), width: 1.6),
      ),
    );
  }

  /// Fixed-size 3D deck stack — offsets stay inside the box so labels don't shift.
  Widget _stackedDeckWidget() {
    final remaining = game.cardsRemainingDisplay;

    return SizedBox(
      width: _kDeckStackW,
      height: _kDeckStackH,
      child: remaining <= 0
          ? Align(
              alignment: Alignment.bottomLeft,
              child: _emptyDeckSlot(),
            )
          : Stack(
              clipBehavior: Clip.hardEdge,
              alignment: Alignment.bottomLeft,
              children: [
                for (int i = 0; i < _deckStackLayers(remaining); i++)
                  Positioned(
                    bottom: i * _kDeckLayerOffsetY,
                    left: i * _kDeckLayerOffsetX,
                    child: _cardBackLayer(depth: i),
                  ),
              ],
            ),
    );
  }

  Widget _emptyCardWidget({required String label}) {
    return Container(
      width: 72, height: 100,
      decoration: BoxDecoration(
        color: _kBurgundyLight, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kGoldDark, width: 1.2),
      ),
      child: Center(child: Text(label,
          style: const TextStyle(color: _kGold, fontWeight: FontWeight.bold))),
    );
  }

  // ── Deck row ──────────────────────────────────────────────────────────────
  Widget _deckRow() {
    final curr = game.current;
    final peek = game.peekCard;

    final bool boardFullClear =
        game.phase == Phase.clear && curr == null;

    final deckColumn = SizedBox(
      width: _kDeckStackW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _stackedDeckWidget(),
          const SizedBox(height: 4),
          Text(
            '${game.cardsRemainingDisplay}',
            style: const TextStyle(
              color: _kGoldLight,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(_l.labelDeck, style: _labelStyle()),
          if (peek != null) ...[
            const SizedBox(height: 3),
            Text(
              _l.peekNext('${peek.label}${suitSymbol(peek.suit)}'),
              style: const TextStyle(
                fontSize: 10,
                color: _kGoldLight,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );

    final Widget exposedFace = boardFullClear
        ? _cardBackWidget()
        : (curr == null
            ? _emptyCardWidget(label: '—')
            : Draggable<CardModel>(
                data: curr,
                feedback: Opacity(opacity: 0.9, child: _playingCard(curr, large: true)),
                childWhenDragging: _playingCard(curr, dimmed: true),
                onDragStarted:       () => setState(() => _draggingCard = curr),
                onDragEnd:           (_)    => setState(() => _draggingCard = null),
                onDraggableCanceled: (_, __) => setState(() => _draggingCard = null),
                child: _playingCard(curr),
              ));

    final String faceLabel = boardFullClear ? _l.labelHidden : _l.labelCurrent;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        deckColumn,
        const SizedBox(width: 16),
        SizedBox(
          width: _kDeckStackW,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              exposedFace,
              const SizedBox(height: 4),
              Text(faceLabel, style: _labelStyle(dimmed: boardFullClear)),
            ],
          ),
        ),
      ],
    );
  }

  TextStyle _labelStyle({bool dimmed = false}) => TextStyle(
    fontSize: 11, fontWeight: FontWeight.w600,
    color: dimmed ? Colors.white38 : _kGoldLight,
    fontStyle: dimmed ? FontStyle.italic : FontStyle.normal,
    letterSpacing: 0.4,
  );

  // ── 4×4 grid ──────────────────────────────────────────────────────────────
  Widget _buildGrid(
    Set<int> clearHighlights,
    Set<int> dragHighlights, {
    required double gridW,
    required double gridH,
  }) {
    const double pad     = 6.0;
    const double gap     = 4.0;
    const int    cols    = 4;
    const int    rows    = 4;

    final double cellW = (gridW - pad * 2 - gap * (cols - 1)) / cols;
    final double cellH = (gridH - pad * 2 - gap * (rows - 1)) / rows;
    final double ratio = cellW / cellH;

    return Container(
      width: gridW, height: gridH,
      decoration: BoxDecoration(
        color: _kTableGreen, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(pad),
      child: GridView.count(
        crossAxisCount: cols,
        childAspectRatio: ratio,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        mainAxisSpacing: gap, crossAxisSpacing: gap,
        children: List.generate(16, (i) {
          final type       = game.layout[i];
          final card       = game.cells[i];
          final blocked    = game.isBlocked[i];
          final selected   = game.selectedForClear.contains(i);
          final isFrame    = type != SlotType.innerDump;
          final isDragTarget = dragHighlights.contains(i);

          final bool correctRoyal = card != null && !blocked && (
              (card.isK && type == SlotType.kingCorner) ||
              (card.isQ && type == SlotType.queenEdge)  ||
              (card.isJ && type == SlotType.jackEdge)
          );

          Color  bgColor;
          Color  borderColor;
          double borderWidth;
          List<BoxShadow>? shadows;
          Gradient? gradient;
          String text = '';

          if (card == null) {
            if (isDragTarget) {
              bgColor = _kDragTarget;
              borderColor = _kDragTargetBorder;
              borderWidth = isFrame ? 3.0 : 2.4;
              text = _l.slotLabel(type);
            } else if (isFrame) {
              bgColor = _kSlotFrame;
              borderColor = _kSlotFrameBorder;
              borderWidth = 2.2;
              text = _l.slotLabel(type);
            } else {
              bgColor = _kTableGreenMid.withOpacity(0.5);
              borderColor = _kSlotDumpBorder;
              borderWidth = 1.0;
            }
          } else {
            final isNumber = card.isNumOrAce;

            if (correctRoyal) {
              bgColor     = _kRoyalGoldBg;
              borderColor = _kRoyalGoldBorder;
              borderWidth = 2.8;
              gradient = const LinearGradient(
                colors: [Color(0xFF4A3200), Color(0xFF2A1800), Color(0xFF4A3200)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              );
              shadows = [
                BoxShadow(
                  color: _kRoyalGlowColor.withOpacity(0.55),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ];
            } else if (isNumber) {
              bgColor     = blocked ? _kBlockedBg : _kBurgundyLight;
              borderColor = _kNumberSilverBorder;
              borderWidth = 2.2;
              shadows     = null;
            } else if (blocked) {
              bgColor     = _kBlockedBg;
              borderColor = _kBlockedBorder;
              borderWidth = isFrame ? 2.2 : 1.4;
              shadows     = null;
            } else {
              bgColor     = _kBurgundyLight;
              borderColor = isFrame ? _kSlotFrameBorder : _kGoldDark;
              borderWidth = isFrame ? 2.2 : 1.4;
              shadows     = null;
            }

            if (_moveMode && _moveFromIndex == i && game.phase != Phase.clear) {
              borderColor = _kGoldLight;
              borderWidth = 3.5;
            }

            // Final overlay — must run last so gold/frame borders never win
            final clearPairActive = game.phase == Phase.clear &&
                (selected || clearHighlights.contains(i));
            if (clearPairActive) {
              borderColor = _kSelectionNeonMagenta;
              borderWidth = 3.5;
            }
          }

          final cellWidget = InkWell(
            onTap: () => _onTapCell(i),
            borderRadius: BorderRadius.circular(7),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                color: gradient == null ? bgColor : null,
                gradient: gradient,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: borderColor, width: borderWidth),
                boxShadow: shadows,
              ),
              child: card == null
                  ? Center(
                      child: Text(
                        text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDragTarget
                              ? _kDragTargetBorder.withOpacity(0.9)
                              : (isFrame
                                  ? _kSlotFrameBorder.withOpacity(0.85)
                                  : Colors.transparent),
                          height: 1.15,
                        ),
                      ),
                    )
                  : _gridCardFace(card),
            ),
          );

          return DragTarget<CardModel>(
            onWillAcceptWithDetails: (_) => true,
            onAccept: (_) {
              _unlockAudio();
              if (game.phase != Phase.fill || game.current == null) return;
              _pushUndo();
              final ok = game.tryPlaceAt(i, godMode: _godMode);
              setState(() {});
              if (ok) { HapticFeedback.lightImpact(); _checkEndState(); }
              else { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_l.snackIllegal))); }
            },
            builder: (_, __, ___) => cellWidget,
          );
        }),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final clearHighlights = _highlightClearableIndices();
    final dragHighlights  = _computeDragHighlights();

    const double deckRowH = 130.0;
    const double innerGap = 10.0;

    final String phaseInstruction = switch (game.phase) {
      Phase.fill     => _l.phaseInstructFill,
      Phase.clear    => _l.phaseInstructClear,
      Phase.winner   => '',
      Phase.gameOver => '',
    };

    return Directionality(
      textDirection: _lang == AppLang.he ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _kBurgundy,
        appBar: AppBar(
          backgroundColor: _kBurgundyLight,
          title: Column(
            crossAxisAlignment: _lang == AppLang.he ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                text: const TextSpan(children: [
                  TextSpan(text: 'Royal ', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w300, letterSpacing: 1.5, color: _kGoldLight)),
                  TextSpan(text: 'Frame', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: _kGold)),
                ]),
              ),
              if (phaseInstruction.isNotEmpty)
                Text(phaseInstruction,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                      color: _kGold, letterSpacing: 0.5)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: game.lifelinePeekAvailable ? _l.tooltipPeekAvail : _l.tooltipPeekUsed,
              onPressed: (!game.lifelinePeekAvailable || game.phase != Phase.fill || game.drawPile.isEmpty)
                  ? null : () => setState(() { game.activatePeek(); }),
              icon: Icon(game.peekActiveNow ? Icons.visibility : Icons.visibility_outlined, color: _kGold),
            ),
            Builder(builder: (ctx) {
              final bool canActivate = _godMode || game.lifelineMoveAvailable;
              final String tip = _godMode
                  ? (_moveMode ? 'Cancel God Move' : 'God Move ∞')
                  : (game.lifelineMoveAvailable
                      ? (_moveMode ? _l.tooltipMoveCancl : _l.tooltipMoveAvail)
                      : _l.tooltipMoveUsed);
              final Color iconColor = canActivate
                  ? (_moveMode ? _kGoldLight : _kGold)
                  : _kGoldDark;

              return IconButton(
                tooltip: tip,
                style: IconButton.styleFrom(
                  foregroundColor: iconColor,
                  disabledForegroundColor: _kGoldDark,
                ),
                onPressed: canActivate
                    ? () => setState(() {
                          _moveMode = !_moveMode;
                          if (!_moveMode) _moveFromIndex = null;
                        })
                    : null,
                icon: Icon(
                  _moveMode ? Icons.open_with_rounded : Icons.swap_horiz_rounded,
                  color: iconColor,
                ),
              );
            }),
            IconButton(tooltip: _l.tooltipUndo, onPressed: _undo.isNotEmpty ? _undoAction : null,
                icon: Icon(Icons.undo, color: _undo.isNotEmpty ? _kGold : _kGoldDark)),
            IconButton(tooltip: _l.tooltipRedo, onPressed: _redo.isNotEmpty ? _redoAction : null,
                icon: Icon(Icons.redo, color: _redo.isNotEmpty ? _kGold : _kGoldDark)),
            IconButton(tooltip: _l.tooltipRules, onPressed: _showRules,
                icon: const Icon(Icons.menu_book_rounded, color: _kGold)),
            IconButton(tooltip: _l.tooltipNewGame, onPressed: () => _newGame(),
                icon: const Icon(Icons.refresh, color: _kGold)),
            _overflowMenu(),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  if (_moveMode)
                    Container(
                      color: _kGoldDark.withOpacity(0.25),
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.open_with_rounded, size: 14, color: _kGoldLight),
                          const SizedBox(width: 6),
                          Text(_moveFromIndex == null ? _l.movePick : _l.moveDrop,
                              style: const TextStyle(color: _kGoldLight, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),

                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    child: _showDebugTools ? _buildDebugPanel() : const SizedBox.shrink(),
                  ),

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final double totalH = constraints.maxHeight;
                          final double totalW = constraints.maxWidth;

                          final double gridH = totalH - deckRowH - innerGap;
                          final double gridW = totalW.clamp(0.0, gridH * 1.4);

                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                height: deckRowH,
                                child: Center(child: _deckRow()),
                              ),
                              SizedBox(height: innerGap),
                              Center(
                                child: _buildGrid(
                                  clearHighlights,
                                  dragHighlights,
                                  gridW: gridW,
                                  gridH: gridH,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                  if (game.phase == Phase.clear) _buildClearBar(),
                ],
              ),

              if (game.phase == Phase.winner) _buildWinnerOverlay(),

              if (game.phase == Phase.gameOver && _showGameOverOverlay)
                _buildGameOverOverlay(),

              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiCtrl,
                  blastDirectionality: BlastDirectionality.explosive,
                  numberOfParticles: 40, gravity: 0.25, emissionFrequency: 0.05,
                  colors: const [_kGold, _kGoldLight, Colors.white, Color(0xFFE91E63), Color(0xFF2196F3)],
                  shouldLoop: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Debug panel ──────────────────────────────────────────────────────────
  Widget _buildDebugPanel() {
    return Container(
      color: _kBurgundyLight.withOpacity(0.92),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(child: _miniCard(_l.dbgPhase,   game.phase.name)),
            Expanded(child: _miniCard(_l.dbgCurrent, game.phase == Phase.clear ? '—' : (game.current?.label ?? '—'))),
            Expanded(child: _miniCard(_l.dbgDeck,    game.cardsRemainingDisplay.toString())),
            Expanded(child: _miniCard(_l.dbgRoyals,  '${game.royalsPlacedCorrect}/12')),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: game.royalsProgress.clamp(0.0, 1.0),
                minHeight: 6, backgroundColor: _kBurgundy, color: _kGold,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_l.dbgGodMode,
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: _godMode ? _kGoldLight : Colors.white38,
                    )),
                const SizedBox(width: 6),
                Switch(
                  value: _godMode,
                  activeColor: _kGold,
                  onChanged: (v) => setState(() => _godMode = v),
                ),
              ]),
              const SizedBox(width: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2A5C1A),
                  foregroundColor: _kGoldLight,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                onPressed: () {
                  _pushUndo();
                  setState(() => game.applyInstantWin());
                  _checkEndState();
                },
                child: Text(_l.dbgInstantWin),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniCard(String title, String value) => Card(
    color: _kBurgundy, margin: const EdgeInsets.symmetric(horizontal: 3),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Column(children: [
        Text(title, style: const TextStyle(fontSize: 10, color: _kGoldDark, fontWeight: FontWeight.w600)),
        Text(value,  style: const TextStyle(fontSize: 12, color: _kGoldLight)),
      ]),
    ),
  );

  Widget _buildClearBar() {
    final pairsLeft = game.hasAnyPairFor11;
    return Container(
      color: _kBurgundyLight,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton(
            onPressed: game.canClearSelection ? _doClear : null,
            child: Text(_l.btnClearPair),
          ),
          const SizedBox(width: 10),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: game.canResumeFill ? _kGoldDark : Colors.grey.shade800,
              foregroundColor: game.canResumeFill ? _kCardWhite : Colors.grey,
            ),
            onPressed: game.canResumeFill ? _resumeFill : null,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_l.btnResumeFill),
              if (pairsLeft) ...[
                const SizedBox(width: 6),
                Tooltip(message: _l.tooltipPairsLeft,
                    child: const Icon(Icons.lock_outline, size: 14)),
              ],
            ]),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: _showClearHints ? _l.tooltipHintsHide : _l.tooltipHintsShow,
            onPressed: () => setState(() => _showClearHints = !_showClearHints),
            icon: Icon(Icons.more_vert, color: _showClearHints ? _kGold : _kGoldDark),
          ),
        ],
      ),
    );
  }

  // ─── Win overlay ──────────────────────────────────────────────────────────
  Widget _buildWinnerOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.72),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 28),
          decoration: BoxDecoration(
            color: _kBurgundyLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kGold, width: 2.5),
            boxShadow: [BoxShadow(color: _kGold.withOpacity(0.35), blurRadius: 40, spreadRadius: 4)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('👑', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(_l.winTitle, style: const TextStyle(color: _kGold, fontSize: 30,
                fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text(_l.winSub, textAlign: TextAlign.center,
                style: const TextStyle(color: _kGoldLight, fontSize: 14)),
            const SizedBox(height: 28),
            FilledButton.icon(onPressed: () => _newGame(),
                icon: const Icon(Icons.refresh), label: Text(_l.winBtn)),
          ]),
        ),
      ),
    );
  }

  // ─── Game Over overlay ────────────────────────────────────────────────────
  Widget _buildGameOverOverlay() {
    final deckLeft = game.cardsRemainingDisplay;
    const textShadow = [Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 2))];

    return Container(
      color: Colors.black.withOpacity(0.40),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kBlockedBorder, width: 1.8),
            boxShadow: [BoxShadow(
              color: _kBlockedBorder.withOpacity(0.28),
              blurRadius: 28, spreadRadius: 2,
            )],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('💀', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 10),
            Text(_l.lossTitle,
              style: const TextStyle(
                color: _kBlockedBorder, fontSize: 28,
                fontWeight: FontWeight.w900, letterSpacing: 2,
                shadows: textShadow,
              )),
            const SizedBox(height: 6),
            Text(_l.lossSub,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13, shadows: textShadow)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _kBurgundy.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kGoldDark.withOpacity(0.5), width: 1),
              ),
              child: Text(_l.lossCardsLeft(deckLeft),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kGoldLight, fontSize: 13,
                    fontWeight: FontWeight.w600, shadows: textShadow)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _kBlockedBorder),
              onPressed: () => _newGame(),
              icon: const Icon(Icons.refresh),
              label: Text(_l.lossBtn),
            ),
          ]),
        ),
      ),
    );
  }
}