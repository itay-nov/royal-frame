import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────────
// GAME MODEL
// ─────────────────────────────────────────────────────────────────────────────
enum SlotType { kingCorner, queenEdge, jackEdge, innerDump }

enum Phase { fill, clear, winner, gameOver }

// Difficulty levels exposed to the rest of the app.
enum GameDifficulty { medium, hard, extreme }

const int kMaxCardsForClear = 2;

sealed class Rank {
  const Rank();
}

class Ace extends Rank {
  const Ace();
}

class Num extends Rank {
  final int value;
  const Num(this.value);
}

class Jack extends Rank {
  const Jack();
}

class Queen extends Rank {
  const Queen();
}

class King extends Rank {
  const King();
}

enum Suit { spade, heart, diamond, club }

String suitSymbol(Suit s) => switch (s) {
  Suit.spade => '♠',
  Suit.heart => '♥',
  Suit.diamond => '♦',
  Suit.club => '♣',
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
    Ace() => 1,
    Num(:final value) => value,
    _ => 0,
  };
  String get label => switch (rank) {
    King() => 'K',
    Queen() => 'Q',
    Jack() => 'J',
    Ace() => 'A',
    Num(:final value) => '$value',
  };

  String get assetRankName => switch (rank) {
    King() => 'king',
    Queen() => 'queen',
    Jack() => 'jack',
    Ace() => 'ace',
    Num(:final value) => '$value',
  };

  String get assetSuitName => switch (suit) {
    Suit.spade => 'spades',
    Suit.heart => 'hearts',
    Suit.diamond => 'diamonds',
    Suit.club => 'clubs',
  };

  static const kCardAssetBase =
      'https://raw.githubusercontent.com/HEB/playing-cards-assets/master/png';
  static const kCardAssetCorsProxy = 'https://corsproxy.io/?';

  String get imageUrl {
    final direct = '$kCardAssetBase/${assetRankName}_of_$assetSuitName.png';
    return '$kCardAssetCorsProxy$direct';
  }
}

// Builds the standard 4×4 board layout.
// Medium difficulty overrides the king-corner slots to innerDump after calling this.
List<SlotType> buildBoardLayout() {
  final s = List.filled(16, SlotType.innerDump);
  for (final i in [0, 3, 12, 15]) s[i] = SlotType.kingCorner;
  for (final i in [1, 2, 13, 14]) s[i] = SlotType.queenEdge;
  for (final i in [4, 8, 7, 11]) s[i] = SlotType.jackEdge;
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
  final List<CardModel> clearedCards;
  bool lifelineMoveAvailable;
  bool lifelinePeekAvailable;
  bool peekActiveNow;

  // Difficulty & modifiers
  final GameDifficulty difficulty;
  final bool isSuddenDeath; // true for Extreme; any illegal move ends the game

  int score;
  DateTime startTime;
  DateTime? endTime;
  DateTime? pausedAt;
  int totalCardsDrawn;
  int? cardsDrawnWhenFrameFilled;

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
    List<CardModel> clearedCards = const [],
    required this.lifelineMoveAvailable,
    required this.lifelinePeekAvailable,
    required this.peekActiveNow,
    required this.difficulty,
    required this.isSuddenDeath,
    required this.score,
    required this.startTime,
    this.endTime,
    this.pausedAt,
    required this.totalCardsDrawn,
    this.cardsDrawnWhenFrameFilled,
  }) : clearedCards = List<CardModel>.from(clearedCards);

  // ── Convenience getters ────────────────────────────────────────────────────

  CardModel? get clearPileTop =>
      clearedCards.isEmpty ? null : clearedCards.last;

  /// Score multiplier applied to the final score breakdown in the win overlay.
  double get scoreMultiplier => switch (difficulty) {
    GameDifficulty.medium  => 0.5,
    GameDifficulty.hard    => 1.0,
    GameDifficulty.extreme => 2.0,
  };

  // ── Factory ────────────────────────────────────────────────────────────────

  factory GameState.newGame({
    int? seed,
    GameDifficulty difficulty = GameDifficulty.hard,
  }) {
    final layout = buildBoardLayout();

    // Medium: replace king-corner slots with inner dumps (no kings in play).
    if (difficulty == GameDifficulty.medium) {
      for (final i in [0, 3, 12, 15]) layout[i] = SlotType.innerDump;
    }

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
        // Medium: omit kings entirely.
        if (difficulty != GameDifficulty.medium)
          CardModel(suit, const King()),
      ]);
    }
    deck.shuffle(rng);
    final initialCount = deck.length;
    final drawPile = deck;
    final current = drawPile.removeLast();

    return GameState._(
      layout: layout,
      cells: cells,
      isBlocked: blocked,
      drawPile: drawPile,
      initialDeckCount: initialCount,
      seed: effectiveSeed,
      current: current,
      phase: Phase.fill,
      selectedForClear: <int>{},
      clearedCards: [],
      lifelineMoveAvailable: true,
      lifelinePeekAvailable: true,
      peekActiveNow: false,
      difficulty: difficulty,
      isSuddenDeath: difficulty == GameDifficulty.extreme,
      score: 0,
      startTime: DateTime.now(),
      totalCardsDrawn: 1,
    );
  }

  GameState clone() => GameState._(
    layout: List<SlotType>.from(layout),
    cells: List<CardModel?>.from(cells),
    isBlocked: List<bool>.from(isBlocked),
    drawPile: List<CardModel>.from(drawPile),
    initialDeckCount: initialDeckCount,
    seed: seed,
    current: current,
    phase: phase,
    selectedForClear: Set<int>.from(selectedForClear),
    clearedCards: List<CardModel>.from(clearedCards),
    lifelineMoveAvailable: lifelineMoveAvailable,
    lifelinePeekAvailable: lifelinePeekAvailable,
    peekActiveNow: peekActiveNow,
    difficulty: difficulty,
    isSuddenDeath: isSuddenDeath,
    score: score,
    startTime: startTime,
    endTime: endTime,
    pausedAt: pausedAt,
    totalCardsDrawn: totalCardsDrawn,
    cardsDrawnWhenFrameFilled: cardsDrawnWhenFrameFilled,
  );

  List<int> _idxOf(SlotType t) => [
    for (int i = 0; i < layout.length; i++)
      if (layout[i] == t) i,
  ];

  bool get boardFull => cells.every((c) => c != null);
  int get remainingInDeck => drawPile.length;

  int get cardsRemainingDisplay => drawPile.length + (current != null ? 1 : 0);

  bool get deckExhausted => drawPile.isEmpty && current == null;

  /// Total number of royal slots on the board (varies by difficulty).
  int get totalRoyalSlots =>
      _idxOf(SlotType.kingCorner).length +
      _idxOf(SlotType.queenEdge).length +
      _idxOf(SlotType.jackEdge).length;

  int get royalsPlacedCorrect {
    int c = 0;
    for (final i in _idxOf(SlotType.kingCorner))
      if (cells[i]?.isK == true && !isBlocked[i]) c++;
    for (final i in _idxOf(SlotType.queenEdge))
      if (cells[i]?.isQ == true && !isBlocked[i]) c++;
    for (final i in _idxOf(SlotType.jackEdge))
      if (cells[i]?.isJ == true && !isBlocked[i]) c++;
    return c;
  }

  double get royalsProgress =>
      totalRoyalSlots > 0 ? royalsPlacedCorrect / totalRoyalSlots : 0.0;

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

  bool get isWinConditionMet =>
      royalsPlacedCorrect == totalRoyalSlots &&
      deckExhausted &&
      !hasAnyPairFor11;

  bool get frameFull =>
      _idxOf(SlotType.kingCorner).every((i) => cells[i] != null) &&
      _idxOf(SlotType.queenEdge).every((i) => cells[i] != null) &&
      _idxOf(SlotType.jackEdge).every((i) => cells[i] != null);

  List<int> _allowedSlotsFor(CardModel card) {
    final result = <int>[];
    for (int i = 0; i < 16; i++) {
      final st = layout[i];
      if (card.isNumOrAce) {
        result.add(i);
      } else if (card.isK && st == SlotType.kingCorner && !isBlocked[i]) {
        result.add(i);
      } else if (card.isQ && st == SlotType.queenEdge && !isBlocked[i]) {
        result.add(i);
      } else if (card.isJ && st == SlotType.jackEdge && !isBlocked[i]) {
        result.add(i);
      }
    }
    return result;
  }

  bool _cardHasLegalPlacement(CardModel card) =>
      _allowedSlotsFor(card).any((i) => cells[i] == null);

  bool hasAnyLegalMove() {
    if (phase != Phase.fill) return true;
    if (current == null) return false;
    return _cardHasLegalPlacement(current!);
  }

  void _evaluatePhaseAfterChange() {
    if (isWinConditionMet) {
      phase = Phase.winner;
      endTime ??= DateTime.now();
      return;
    }

    if (phase == Phase.fill && current != null) {
      if (_cardHasLegalPlacement(current!)) return;
      phase = Phase.gameOver;
      endTime ??= DateTime.now();
      return;
    }

    if (phase == Phase.fill && current == null) {
      if (royalsPlacedCorrect == totalRoyalSlots && !hasAnyPairFor11) {
        phase = Phase.winner;
        endTime ??= DateTime.now();
        return;
      }
      if (hasAnyPairFor11) {
        phase = Phase.clear;
        selectedForClear.clear();
      } else {
        phase = Phase.gameOver;
        endTime ??= DateTime.now();
      }
      return;
    }

    if (phase == Phase.clear) {
      if (isWinConditionMet) {
        phase = Phase.winner;
        endTime ??= DateTime.now();
        return;
      }
      if (hasAnyPairFor11) return;

      if (cells.any((c) => c == null)) {
        if (current == null && drawPile.isEmpty) {
          phase = royalsPlacedCorrect == totalRoyalSlots
              ? Phase.winner
              : Phase.gameOver;
          endTime ??= DateTime.now();
          return;
        }
        phase = Phase.fill;
        if (current == null && drawPile.isNotEmpty) {
          current = drawPile.removeLast();
          totalCardsDrawn++;
        }
        _evaluatePhaseAfterChange();
        return;
      }

      phase = Phase.gameOver;
      endTime ??= DateTime.now();
      return;
    }
  }

  void evaluateGameOverInFill() {
    if (phase == Phase.fill) _evaluatePhaseAfterChange();
  }

  bool tryPlaceAt(int index, {bool godMode = false}) {
    if (phase != Phase.fill || current == null || cells[index] != null)
      return false;
    final st = layout[index];
    final card = current!;

    if (godMode) {
      cells[index] = card;
      isBlocked[index] = false;
      _afterPlacement();
      return true;
    }

    if (card.isNumOrAce) {
      cells[index] = card;
      isBlocked[index] = (st != SlotType.innerDump);
      _afterPlacement();
      return true;
    }

    if (card.isK && st == SlotType.kingCorner && !isBlocked[index]) {
      cells[index] = card;
      score += 100;
      _afterPlacement();
      return true;
    }
    if (card.isQ && st == SlotType.queenEdge && !isBlocked[index]) {
      cells[index] = card;
      score += 100;
      _afterPlacement();
      return true;
    }
    if (card.isJ && st == SlotType.jackEdge && !isBlocked[index]) {
      cells[index] = card;
      score += 100;
      _afterPlacement();
      return true;
    }

    return false;
  }

  void _afterPlacement() {
    peekActiveNow = false;

    if (frameFull && cardsDrawnWhenFrameFilled == null) {
      cardsDrawnWhenFrameFilled = totalCardsDrawn;
    }

    if (boardFull && drawPile.isNotEmpty) {
      current = null;
      if (hasAnyPairFor11) {
        phase = Phase.clear;
        selectedForClear.clear();
      } else {
        phase = Phase.gameOver;
      }
      return;
    }

    current = drawPile.isNotEmpty ? drawPile.removeLast() : null;
    if (current != null) totalCardsDrawn++;

    _evaluatePhaseAfterChange();
  }

  void toggleSelectForClear(int index) {
    if (phase != Phase.clear) return;
    final c = cells[index];
    if (c == null || !c.isNumOrAce) return;
    if (!selectedForClear.add(index)) selectedForClear.remove(index);
  }

  bool get canClearSelection {
    if (selectedForClear.length != kMaxCardsForClear) return false;
    return selectedForClear
            .map((i) => cells[i]!.valueForSum)
            .fold(0, (a, b) => a + b) ==
        11;
  }

  void performClear() {
    if (!canClearSelection) return;
    final indices = selectedForClear.toList()..sort();
    for (final i in indices) {
      clearedCards.add(cells[i]!);
      cells[i] = null;
      isBlocked[i] = false;
    }
    selectedForClear.clear();
    score += 50;
    _evaluatePhaseAfterChange();
  }

  bool get canResumeFill =>
      phase == Phase.clear &&
      !hasAnyPairFor11 &&
      cells.any((c) => c == null) &&
      (current != null || drawPile.isNotEmpty);

  bool resumeFill() {
    if (!canResumeFill) return false;
    phase = Phase.fill;
    if (current == null && drawPile.isNotEmpty) {
      current = drawPile.removeLast();
      totalCardsDrawn++;
    }
    _evaluatePhaseAfterChange();
    return true;
  }

  bool activatePeek() {
    if (!lifelinePeekAvailable || drawPile.isEmpty) return false;
    lifelinePeekAvailable = false;
    peekActiveNow = true;
    return true;
  }

  CardModel? get peekCard =>
      (peekActiveNow && drawPile.isNotEmpty) ? drawPile.last : null;

  bool moveCard(int from, int to, {bool godMode = false}) {
    if (!cells.asMap().containsKey(from) || !cells.asMap().containsKey(to))
      return false;
    if (cells[from] == null || cells[to] != null) return false;
    final c = cells[from]!;
    final stTo = layout[to];

    if (godMode) {
      cells[to] = c;
      isBlocked[to] = false;
      cells[from] = null;
      isBlocked[from] = false;
      return true;
    }

    if (c.isK && stTo != SlotType.kingCorner) return false;
    if (c.isQ && stTo != SlotType.queenEdge) return false;
    if (c.isJ && stTo != SlotType.jackEdge) return false;
    if (c.isK || c.isQ || c.isJ) {
      cells[to] = c;
      isBlocked[to] = false;
      cells[from] = null;
      isBlocked[from] = false;
      _evaluatePhaseAfterChange();
      return true;
    }
    cells[to] = c;
    isBlocked[to] = (stTo != SlotType.innerDump);
    cells[from] = null;
    isBlocked[from] = false;
    _evaluatePhaseAfterChange();
    return true;
  }

  void applyInstantWin() {
    for (int i = 0; i < 16; i++) {
      cells[i] = null;
      isBlocked[i] = false;
    }
    selectedForClear.clear();
    clearedCards.clear();
    drawPile.clear();
    current = null;

    const kings   = [Suit.spade, Suit.heart, Suit.diamond, Suit.club];
    const queens  = [Suit.spade, Suit.heart, Suit.diamond, Suit.club];
    const jacks   = [Suit.spade, Suit.heart, Suit.diamond, Suit.club];
    int ki = 0, qi = 0, ji = 0;
    for (int i = 0; i < 16; i++) {
      switch (layout[i]) {
        case SlotType.kingCorner:
          cells[i] = CardModel(kings[ki++], const King());
        case SlotType.queenEdge:
          cells[i] = CardModel(queens[qi++], const Queen());
        case SlotType.jackEdge:
          cells[i] = CardModel(jacks[ji++], const Jack());
        case SlotType.innerDump:
          break;
      }
    }
    score = 1200;
    cardsDrawnWhenFrameFilled = 12;
    phase = Phase.winner;
    endTime = DateTime.now();
  }
}
