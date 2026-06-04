import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:audioplayers/audioplayers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// THEME CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────
const kBurgundy         = Color(0xFF4A0E1A);
const kBurgundyLight    = Color(0xFF6B1A2A);
const kGold             = Color(0xFFD4AF37);
const kGoldLight        = Color(0xFFF0D060);
const kGoldDark         = Color(0xFF9A7B1A);
const kCardWhite        = Color(0xFFFFFDF5);
const kCardRed          = Color(0xFFB71C1C);
const kCardBlack        = Color(0xFF1A1A1A);
const kTableGreen       = Color(0xFF1A3A2A);
const kTableGreenMid    = Color(0xFF254D38);
const kSlotFrame        = Color(0xFF2E5C44);
const kSlotFrameBorder  = Color(0xFF5AAE80);   // brighter than before
const kSlotDumpBorder   = Color(0xFF2E4A3A);
const kBlockedBg        = Color(0xFF3D1A1A);
const kBlockedBorder    = Color(0xFFB06060);
const kDragTarget       = Color(0xFF3D3010);
const kDragTargetBorder = Color(0xFFE8C84A);

// Golden Royal colours
const kRoyalGoldBg      = Color(0xFF3A2800);   // deep gold background
const kRoyalGoldBorder  = Color(0xFFFFD700);   // bright gold border
const kRoyalGlowColor   = Color(0xFFFFD700);   // glow tint

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
        scaffoldBackgroundColor: kBurgundy,
        appBarTheme: const AppBarTheme(
          backgroundColor: kBurgundyLight,
          foregroundColor: kGold,
          elevation: 0,
          titleSpacing: 16,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: kGold,
            foregroundColor: kBurgundy,
            textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: kGoldLight),
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

  /// True iff clearing 11-pairs could eventually open a slot for [card].
  ///
  /// Algorithm (exactly as specified):
  ///   1. Get all allowed slots for the card.
  ///   2. For each allowed slot that is currently OCCUPIED:
  ///        • Is the occupying card a number/ace?
  ///        • Does its 11-complement exist somewhere else on the board?
  ///      If both true for any slot → space CAN be made → return true.
  ///   3. If no such slot exists → true deadlock → return false.
  bool _canSpaceBeMadeFor(CardModel card) {
    // Collect the numeric values already on the board (for O(1) complement lookup).
    final boardNums = <int, int>{}; // value → count of that value on board
    for (int i = 0; i < 16; i++) {
      final c = cells[i];
      if (c != null && c.isNumOrAce) {
        boardNums[c.valueForSum] = (boardNums[c.valueForSum] ?? 0) + 1;
      }
    }

    for (final i in _allowedSlotsFor(card)) {
      if (cells[i] == null) continue; // empty slots already handled by _cardHasLegalPlacement
      final occupant = cells[i]!;
      if (!occupant.isNumOrAce) continue; // royals can't be cleared via 11-pairs
      final complement = 11 - occupant.valueForSum;
      if (complement < 1 || complement > 10) continue; // not a valid pair value
      // Check if the complement exists on the board (excluding the occupant itself).
      final countOnBoard = boardNums[complement] ?? 0;
      // If the complement is the same value as the occupant (e.g. both are 5+6=11
      // and complement==occupant.value) we need at least 2 of that value;
      // otherwise we just need at least 1.
      final needed = (complement == occupant.valueForSum) ? 2 : 1;
      if (countOnBoard >= needed) return true;
    }
    return false;
  }

  // Kept for call-site compatibility.
  bool hasAnyLegalMove() {
    if (phase != Phase.fill) return true;
    if (current == null) return false;
    return _cardHasLegalPlacement(current!) || _canSpaceBeMadeFor(current!);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE STATE MACHINE  —  _evaluatePhaseAfterChange()
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Called after EVERY board/deck mutation (placement, clear, undo, init).
  //
  // SMART DEADLOCK EVALUATION (branches 2c / 2d):
  //   When the current card has no immediate empty slot, we do NOT blindly
  //   enter clear phase or immediately declare Game Over.  Instead we run the
  //   targeted _canSpaceBeMadeFor() check:
  //     • At least one allowed slot holds a number whose 11-complement is
  //       also on the board  →  Phase.clear  (player CAN free space).
  //     • No such slot exists  →  Phase.gameOver  (true deadlock).
  //
  // Decision tree (top-to-bottom, first match wins):
  //
  //  1. Win?  (12 royals + deck exhausted + no pairs)        → Phase.winner
  //
  //  2. Phase.fill — card in hand  (current != null)
  //       2a. At least one allowed slot is EMPTY              → stay Phase.fill
  //       2b. No allowed slot is empty — smart check:
  //             space CAN be made (freeable slot exists)      → Phase.clear
  //             space CANNOT be made (true deadlock)          → Phase.gameOver
  //
  //  3. Phase.fill — deck exhausted  (current == null)
  //       win re-check  → Phase.winner  (if 12 royals + no pairs)
  //       pairs remain  → Phase.clear
  //       no pairs      → Phase.gameOver
  //
  //  4. Phase.clear  (post-performClear / post-resumeFill)
  //       4a. Win?                                            → Phase.winner
  //       4b. Pairs remain                                    → stay Phase.clear
  //       4c. No pairs + empty slots exist
  //             draw next card if current == null + pile non-empty
  //             deck now exhausted  → winner / gameOver immediately
  //             else set Phase.fill, re-evaluate (new card might deadlock)
  //       4d. No pairs + board full                          → Phase.gameOver

  void _evaluatePhaseAfterChange() {
    // ── 1. Win ────────────────────────────────────────────────────────────────
    if (isWinConditionMet) { phase = Phase.winner; return; }

    // ── 2. Phase.fill — card in hand ─────────────────────────────────────────
    if (phase == Phase.fill && current != null) {
      // 2a: At least one allowed slot is currently empty → player places it.
      if (_cardHasLegalPlacement(current!)) return;

      // 2b: No empty allowed slot for this card.
      //     Run the smart check: can any required slot be freed by an 11-pair?
      if (_canSpaceBeMadeFor(current!)) {
        // Yes — enter clear phase so the player can reduce pairs and open space.
        // `current` stays in hand and is visible throughout clear phase.
        phase = Phase.clear;
        selectedForClear.clear();
      } else {
        // No — true deadlock: nowhere to place the card, nothing that can be
        // cleared to make room for it.
        phase = Phase.gameOver;
      }
      return;
    }

    // ── 3. Phase.fill — deck exhausted, nothing in hand ──────────────────────
    if (phase == Phase.fill && current == null) {
      if (royalsPlacedCorrect == 12 && !hasAnyPairFor11) {
        phase = Phase.winner; return;
      }
      if (hasAnyPairFor11) {
        phase = Phase.clear; selectedForClear.clear();
      } else {
        phase = Phase.gameOver;
      }
      return;
    }

    // ── 4. Phase.clear ────────────────────────────────────────────────────────
    if (phase == Phase.clear) {
      // 4a: Win re-check after a pair was cleared.
      if (isWinConditionMet) { phase = Phase.winner; return; }

      // 4b: More pairs remain → stay in clear so the player can keep reducing.
      if (hasAnyPairFor11) return;

      // 4c: No pairs left + empty slots exist.
      if (cells.any((c) => c == null)) {
        // ── Exhausted-deck sub-case ───────────────────────────────────────────
        // Deck is empty AND no card in hand: the player cannot fill anything
        // even if they "resume".  Auto-resolve immediately — the Resume button
        // would be meaningless here.
        if (current == null && drawPile.isEmpty) {
          phase = (royalsPlacedCorrect == 12) ? Phase.winner : Phase.gameOver;
          return;
        }
        // ── Normal sub-case ──────────────────────────────────────────────────
        // Cards remain (in hand or in the pile).  Do NOT auto-transition.
        // Simply return: canResumeFill will become true, the "Resume Fill"
        // button lights up, and the player taps it to continue.  This is the
        // intended game rhythm — the button is the explicit gate back to fill.
        return;
      }

      // 4d: Board full, no pairs left → no moves possible → loss.
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
    // Draw the next card immediately; _evaluatePhaseAfterChange handles it.
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
  //
  // canResumeFill becomes true the moment ALL of the following hold:
  //   1. We are in Phase.clear.
  //   2. No 11-pairs remain on the board (!hasAnyPairFor11).
  //   3. At least one slot is empty (space was cleared).
  //   4. There is something to fill with: a card already in hand (royal-freeze
  //      path where current != null) OR cards still in the draw pile.
  //      — When deck is exhausted AND current is null the machine auto-resolves
  //        in branch 4c and the button is never needed.
  //
  // This getter is the SOLE gate that lights up the "Resume Fill" button.
  // The phase machine (branch 4c) deliberately does NOT auto-transition when
  // cards are available — the button is the explicit player-controlled gate
  // back to Phase.fill, preserving the intended game rhythm.
  bool get canResumeFill =>
      phase == Phase.clear &&
      !hasAnyPairFor11 &&
      cells.any((c) => c == null) &&
      (current != null || drawPile.isNotEmpty);

  // Called when the player taps "Resume Fill".
  // Draws the next card (if not already holding one) then re-enters fill phase.
  // _evaluatePhaseAfterChange runs immediately so a freshly drawn card that is
  // already deadlocked (e.g. a Queen when all Queen slots are blocked) triggers
  // the correct outcome without the player having to take another action.
  bool resumeFill() {
    if (!canResumeFill) return false;
    phase = Phase.fill;
    // Draw only when not already holding a card (royal-freeze path already has
    // current set; board-full path needs to draw the next card now).
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
    // Drain the deck so deckExhausted becomes true
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
  // During a royal-freeze clear (phase == clear, current != null), the player
  // is still holding a card and may drag it once a slot opens. Allow highlights
  // whenever a card is being dragged and game.current is non-null.
  Set<int> _computeDragHighlights() {
    final card = _draggingCard;
    // Show highlights only when actively dragging and a card is in hand.
    // Works in both Phase.fill and Phase.clear (royal-freeze scenario).
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
        color: kBurgundyLight,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_l.rulesTitle,
                style: const TextStyle(color: kGold, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 16),
            Text(_l.rulesBody,
                style: const TextStyle(color: kGoldLight, fontSize: 14, height: 1.7)),
          ],
        ),
      ),
    );
    if (isWide) {
      showDialog(context: context, builder: (_) => Dialog(child: SizedBox(width: 460, child: content)));
    } else {
      showModalBottomSheet(
        context: context, showDragHandle: true, backgroundColor: kBurgundyLight,
        builder: (_) => content,
      );
    }
  }

  // ── Overflow menu ─────────────────────────────────────────────────────────
  Widget _overflowMenu() {
    return PopupMenuButton<String>(
      tooltip: _l.tooltipMore,
      icon: const Icon(Icons.more_vert, color: kGold),
      color: kBurgundyLight,
      onSelected: (v) {
        switch (v) {
          case 'lang':  setState(() => _lang = _lang == AppLang.he ? AppLang.en : AppLang.he);
          case 'debug': setState(() => _showDebugTools = !_showDebugTools);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'lang',
          child: ListTile(
            leading: const Icon(Icons.language, color: kGold),
            title: Text(_l.langToggleLabel, style: const TextStyle(color: kGoldLight)),
          )),
        PopupMenuItem(value: 'debug',
          child: ListTile(
            leading: Icon(_showDebugTools ? Icons.settings : Icons.settings_outlined, color: kGold),
            title: Text(_showDebugTools ? _l.menuDebugHide : _l.menuDebugShow,
                style: const TextStyle(color: kGoldLight)),
          )),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CARD WIDGETS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _playingCard(CardModel c, {bool large = false, bool dimmed = false}) {
    final faceColor = isRed(c.suit) ? kCardRed : kCardBlack;
    final w = large ? 90.0 : 72.0;
    final h = large ? 126.0 : 100.0;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: dimmed ? 0.45 : 1,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: w, height: h,
          child: Material(
            elevation: 6, shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                color: kCardWhite, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kGoldDark, width: 1.6),
              ),
              padding: const EdgeInsets.all(6),
              child: Stack(children: [
                Align(alignment: Alignment.topLeft,
                  child: Text('${c.label}\n${suitSymbol(c.suit)}',
                    style: TextStyle(fontSize: large ? 17.0 : 14.0, fontWeight: FontWeight.w900,
                        height: 1.05, color: faceColor, fontFamily: 'Georgia'))),
                Align(alignment: Alignment.center,
                  child: Text(suitSymbol(c.suit),
                    style: TextStyle(fontSize: large ? 36.0 : 28.0, color: faceColor))),
                Align(alignment: Alignment.bottomRight,
                  child: Transform.rotate(angle: pi,
                    child: Text('${c.label}\n${suitSymbol(c.suit)}',
                      style: TextStyle(fontSize: large ? 17.0 : 14.0, fontWeight: FontWeight.w900,
                          height: 1.05, color: faceColor, fontFamily: 'Georgia')))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardBackWidget({String? label}) {
    return Container(
      width: 72, height: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kGold, width: 1.8),
        gradient: const LinearGradient(
          colors: [Color(0xFF6B1A2A), Color(0xFF3A0A12)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: Stack(children: [
        Center(child: Opacity(opacity: 0.25,
            child: Icon(Icons.diamond_outlined, size: 48, color: kGold))),
        if (label != null && label.isNotEmpty)
          Center(child: Text(label, textAlign: TextAlign.center,
            style: const TextStyle(color: kGold, fontWeight: FontWeight.w700, fontSize: 12, height: 1.3))),
      ]),
    );
  }

  Widget _emptyCardWidget({required String label}) {
    return Container(
      width: 72, height: 100,
      decoration: BoxDecoration(
        color: kBurgundyLight, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kGoldDark, width: 1.2),
      ),
      child: Center(child: Text(label,
          style: const TextStyle(color: kGold, fontWeight: FontWeight.bold))),
    );
  }

  // ── Deck row ──────────────────────────────────────────────────────────────
  // current is ALWAYS the player's card-in-hand and is ALWAYS shown when
  // non-null, regardless of phase. The "?" back is shown only when the phase
  // is clear AND current == null (i.e. the board filled up and forced a clear
  // before the next card was drawn). When a royal freeze triggers clear phase
  // while current != null, the player must still see — and drag — their card.
  Widget _deckRow() {
    final curr = game.current;
    final peek = game.peekCard;

    // True only for the board-full clear: no card in hand, phase is clear.
    final bool boardFullClear =
        game.phase == Phase.clear && curr == null;

    final deckColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _cardBackWidget(label: '${_l.labelDeck}\n${game.cardsRemainingDisplay}'),
        const SizedBox(height: 4),
        Text(_l.labelDeck, style: _labelStyle()),
        if (peek != null) ...[
          const SizedBox(height: 3),
          Text(_l.peekNext('${peek.label}${suitSymbol(peek.suit)}'),
              style: const TextStyle(fontSize: 10, color: kGoldLight, fontWeight: FontWeight.w600)),
        ],
      ],
    );

    // Build the exposed-face widget:
    //   • boardFullClear (no card in hand) → show "?" card back
    //   • curr == null otherwise           → show empty "—" placeholder
    //   • curr != null                     → always show the real card (draggable)
    final Widget exposedFace = boardFullClear
        ? _cardBackWidget(label: '?')
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

    // Label under the exposed face: dim it only for board-full clear.
    final String faceLabel = boardFullClear ? _l.labelHidden : _l.labelCurrent;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        deckColumn,
        const SizedBox(width: 16),
        Column(mainAxisSize: MainAxisSize.min, children: [
          exposedFace,
          const SizedBox(height: 4),
          Text(faceLabel, style: _labelStyle(dimmed: boardFullClear)),
        ]),
      ],
    );
  }

  TextStyle _labelStyle({bool dimmed = false}) => TextStyle(
    fontSize: 11, fontWeight: FontWeight.w600,
    color: dimmed ? Colors.white38 : kGoldLight,
    fontStyle: dimmed ? FontStyle.italic : FontStyle.normal,
    letterSpacing: 0.4,
  );

  // ── 4×4 grid ──────────────────────────────────────────────────────────────
  // gridW / gridH are the exact pixels available for the board container.
  // childAspectRatio is derived from them so all 4 rows always fit perfectly.
  Widget _buildGrid(
    Set<int> clearHighlights,
    Set<int> dragHighlights, {
    required double gridW,
    required double gridH,
  }) {
    // Inner padding on all sides inside the green container.
    const double pad     = 6.0;
    const double gap     = 4.0;
    const int    cols    = 4;
    const int    rows    = 4;

    // Usable space after removing container padding and inter-cell gaps.
    final double cellW = (gridW - pad * 2 - gap * (cols - 1)) / cols;
    final double cellH = (gridH - pad * 2 - gap * (rows - 1)) / rows;
    final double ratio = cellW / cellH; // <1 → tall cards, always correct

    return Container(
      width: gridW, height: gridH,
      decoration: BoxDecoration(
        color: kTableGreen, borderRadius: BorderRadius.circular(12),
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

          // ── Determine correct royal placement ─────────────────────────
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
              bgColor = kDragTarget;
              borderColor = kDragTargetBorder;
              // ── Task 2.2: frame drag targets get extra-thick border ───
              borderWidth = isFrame ? 3.0 : 2.4;
              text = _l.slotLabel(type);
            } else if (isFrame) {
              bgColor = kSlotFrame;
              // ── Task 2.2: bold frame border ───────────────────────────
              borderColor = kSlotFrameBorder;
              borderWidth = 2.2;
              text = _l.slotLabel(type);
            } else {
              bgColor = kTableGreenMid.withOpacity(0.5);
              borderColor = kSlotDumpBorder;
              borderWidth = 1.0;
            }
          } else {
            text = '${card.label}${suitSymbol(card.suit)}';

            if (correctRoyal) {
              // ── Task 2.3: Golden Royal ────────────────────────────────
              bgColor     = kRoyalGoldBg;
              borderColor = kRoyalGoldBorder;
              borderWidth = 2.8;
              gradient = const LinearGradient(
                colors: [Color(0xFF4A3200), Color(0xFF2A1800), Color(0xFF4A3200)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              );
              shadows = [
                BoxShadow(
                  color: kRoyalGlowColor.withOpacity(0.55),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ];
            } else if (blocked) {
              bgColor = kBlockedBg;
              borderColor = kBlockedBorder;
              borderWidth = isFrame ? 2.2 : 1.4;
              shadows = null;
            } else {
              bgColor = kBurgundyLight;
              borderColor = isFrame ? kSlotFrameBorder : kGoldDark;
              // ── Task 2.2: occupied frame slots keep bold border ────────
              borderWidth = isFrame ? 2.2 : 1.4;
              shadows = null;
            }

            // Selection / hint overlays override border only
            if (game.phase == Phase.clear) {
              if (selected) {
                borderColor = kGoldLight;
                borderWidth = 3.5;
              } else if (clearHighlights.contains(i)) {
                borderColor = const Color(0xFFFFC107);
                borderWidth = 2.8;
              }
            }
            if (_moveMode && _moveFromIndex == i) {
              borderColor = kGoldLight;
              borderWidth = 3.5;
            }
            if (blocked) text = '${card.label}${suitSymbol(card.suit)}\n✕';
          }

          final cellWidget = InkWell(
            onTap: () => _onTapCell(i),
            borderRadius: BorderRadius.circular(7),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                // gradient takes priority for golden royals; others use flat color
                color: gradient == null ? bgColor : null,
                gradient: gradient,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: borderColor, width: borderWidth),
                boxShadow: shadows,
              ),
              child: Center(
                child: Text(text, textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: card == null ? 11 : 16,
                    fontWeight: card == null ? FontWeight.w600 : FontWeight.w800,
                    color: card == null
                        ? (isDragTarget
                            ? kDragTargetBorder.withOpacity(0.9)
                            : (isFrame ? kSlotFrameBorder.withOpacity(0.85) : Colors.transparent))
                        : (correctRoyal ? kGoldLight : kCardWhite),
                    fontFamily: card != null ? 'Georgia' : null,
                    height: 1.15,
                    shadows: correctRoyal
                        ? [const Shadow(color: kGoldDark, blurRadius: 4)]
                        : null,
                  )),
              ),
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

    // The deck row has a fixed height; the grid fills whatever remains.
    // LayoutBuilder gives us exact pixels so we derive childAspectRatio
    // dynamically — no scrolling, no clipping, no overflow.
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
        backgroundColor: kBurgundy,
        appBar: AppBar(
          backgroundColor: kBurgundyLight,
          title: Column(
            crossAxisAlignment: _lang == AppLang.he ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                text: const TextSpan(children: [
                  TextSpan(text: 'Royal ', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w300, letterSpacing: 1.5, color: kGoldLight)),
                  TextSpan(text: 'Frame', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: kGold)),
                ]),
              ),
              if (phaseInstruction.isNotEmpty)
                Text(phaseInstruction,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                      color: kGold, letterSpacing: 0.5)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: game.lifelinePeekAvailable ? _l.tooltipPeekAvail : _l.tooltipPeekUsed,
              onPressed: (!game.lifelinePeekAvailable || game.phase != Phase.fill || game.drawPile.isEmpty)
                  ? null : () => setState(() { game.activatePeek(); }),
              icon: Icon(game.peekActiveNow ? Icons.visibility : Icons.visibility_outlined, color: kGold),
            ),
            Builder(builder: (ctx) {
              final bool canActivate = _godMode || game.lifelineMoveAvailable;
              final String tip = _godMode
                  ? (_moveMode ? 'Cancel God Move' : 'God Move ∞')
                  : (game.lifelineMoveAvailable
                      ? (_moveMode ? _l.tooltipMoveCancl : _l.tooltipMoveAvail)
                      : _l.tooltipMoveUsed);
              final Color iconColor = canActivate
                  ? (_moveMode ? kGoldLight : kGold)
                  : kGoldDark;

              return IconButton(
                tooltip: tip,
                style: IconButton.styleFrom(
                  foregroundColor: iconColor,
                  disabledForegroundColor: kGoldDark,
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
                icon: Icon(Icons.undo, color: _undo.isNotEmpty ? kGold : kGoldDark)),
            IconButton(tooltip: _l.tooltipRedo, onPressed: _redo.isNotEmpty ? _redoAction : null,
                icon: Icon(Icons.redo, color: _redo.isNotEmpty ? kGold : kGoldDark)),
            IconButton(tooltip: _l.tooltipRules, onPressed: _showRules,
                icon: const Icon(Icons.menu_book_rounded, color: kGold)),
            IconButton(tooltip: _l.tooltipNewGame, onPressed: () => _newGame(),
                icon: const Icon(Icons.refresh, color: kGold)),
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
                      color: kGoldDark.withOpacity(0.25),
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.open_with_rounded, size: 14, color: kGoldLight),
                          const SizedBox(width: 6),
                          Text(_moveFromIndex == null ? _l.movePick : _l.moveDrop,
                              style: const TextStyle(color: kGoldLight, fontSize: 12, fontWeight: FontWeight.w600)),
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
                          // Total vertical space available to the play area.
                          final double totalH = constraints.maxHeight;
                          final double totalW = constraints.maxWidth;

                          // Grid gets what's left after the deck row + gap.
                          final double gridH = totalH - deckRowH - innerGap;
                          // Grid width: square up to the available width, but
                          // never wider than height*1.2 to keep card proportions sane.
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
                  colors: const [kGold, kGoldLight, Colors.white, Color(0xFFE91E63), Color(0xFF2196F3)],
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
      color: kBurgundyLight.withOpacity(0.92),
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
                minHeight: 6, backgroundColor: kBurgundy, color: kGold,
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
                      color: _godMode ? kGoldLight : Colors.white38,
                    )),
                const SizedBox(width: 6),
                Switch(
                  value: _godMode,
                  activeColor: kGold,
                  onChanged: (v) => setState(() => _godMode = v),
                ),
              ]),
              const SizedBox(width: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2A5C1A),
                  foregroundColor: kGoldLight,
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
    color: kBurgundy, margin: const EdgeInsets.symmetric(horizontal: 3),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Column(children: [
        Text(title, style: const TextStyle(fontSize: 10, color: kGoldDark, fontWeight: FontWeight.w600)),
        Text(value,  style: const TextStyle(fontSize: 12, color: kGoldLight)),
      ]),
    ),
  );

  Widget _buildClearBar() {
    final pairsLeft = game.hasAnyPairFor11;
    return Container(
      color: kBurgundyLight,
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
              backgroundColor: game.canResumeFill ? kGoldDark : Colors.grey.shade800,
              foregroundColor: game.canResumeFill ? kCardWhite : Colors.grey,
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
            icon: Icon(Icons.more_vert, color: _showClearHints ? kGold : kGoldDark),
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
            color: kBurgundyLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kGold, width: 2.5),
            boxShadow: [BoxShadow(color: kGold.withOpacity(0.35), blurRadius: 40, spreadRadius: 4)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('👑', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(_l.winTitle, style: const TextStyle(color: kGold, fontSize: 30,
                fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text(_l.winSub, textAlign: TextAlign.center,
                style: const TextStyle(color: kGoldLight, fontSize: 14)),
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
            border: Border.all(color: kBlockedBorder, width: 1.8),
            boxShadow: [BoxShadow(
              color: kBlockedBorder.withOpacity(0.28),
              blurRadius: 28, spreadRadius: 2,
            )],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('💀', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 10),
            Text(_l.lossTitle,
              style: const TextStyle(
                color: kBlockedBorder, fontSize: 28,
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
                color: kBurgundy.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kGoldDark.withOpacity(0.5), width: 1),
              ),
              child: Text(_l.lossCardsLeft(deckLeft),
                textAlign: TextAlign.center,
                style: const TextStyle(color: kGoldLight, fontSize: 13,
                    fontWeight: FontWeight.w600, shadows: textShadow)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kBlockedBorder),
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
