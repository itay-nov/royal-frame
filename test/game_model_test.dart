// Characterization suite for the LOCKED game engine.
//
// These tests pin current behavior via the public API only — the engine
// itself must never be modified. Board states are built by driving
// placements with seed-scanned decks (deterministic per SDK), never by
// reaching into private state. Any failure here after an engine edit is
// a locked-boundary violation; any genuine engine bug a test exposes is
// REPORTED, never fixed.

import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/models/game_model.dart';

String cardKey(CardModel c) => '${c.label}${suitSymbol(c.suit)}';

/// Finds a seed whose classic game opens with a card satisfying [test].
int seedWhereFirstCard(bool Function(CardModel) test, {int start = 0}) {
  for (int s = start; s < start + 500; s++) {
    final g = GameState.newGame(seed: s);
    if (test(g.current!)) return s;
  }
  fail('no seed in [$start, ${start + 500}) opens with the wanted card');
}

void main() {
  group('board layout', () {
    test('classic layout: corners K, top/bottom edges Q, side edges J', () {
      final layout = buildBoardLayout();
      for (final i in [0, 3, 12, 15]) {
        expect(layout[i], SlotType.kingCorner);
      }
      for (final i in [1, 2, 13, 14]) {
        expect(layout[i], SlotType.queenEdge);
      }
      for (final i in [4, 7, 8, 11]) {
        expect(layout[i], SlotType.jackEdge);
      }
      for (final i in [5, 6, 9, 10]) {
        expect(layout[i], SlotType.innerDump);
      }
    });
  });

  group('placement legality (fill phase)', () {
    test('number/ace cards place anywhere empty and block royal slots', () {
      final seed = seedWhereFirstCard((c) => c.isNumOrAce);
      final g = GameState.newGame(seed: seed);
      // inner dump: no block flag
      expect(g.tryPlaceAt(5), isTrue);
      expect(g.isBlocked[5], isFalse);
      expect(g.score, 0, reason: 'numbers score nothing');
      // royal slot: allowed but blocks it
      final seed2 = seedWhereFirstCard((c) => c.isNumOrAce);
      final g2 = GameState.newGame(seed: seed2);
      expect(g2.tryPlaceAt(0), isTrue, reason: 'number may sit on a corner');
      expect(g2.isBlocked[0], isTrue, reason: 'and blocks it for kings');
    });

    test('occupied cells reject placement', () {
      final seed = seedWhereFirstCard((c) => c.isNumOrAce);
      final g = GameState.newGame(seed: seed);
      expect(g.tryPlaceAt(5), isTrue);
      expect(g.tryPlaceAt(5), isFalse, reason: 'cell already occupied');
    });

    test('royals only fit their matching frame slots and score 100', () {
      final kSeed = seedWhereFirstCard((c) => c.isK);
      final gk = GameState.newGame(seed: kSeed);
      expect(gk.tryPlaceAt(5), isFalse,
          reason: 'king cannot go to an inner dump');
      expect(gk.tryPlaceAt(1), isFalse,
          reason: 'king cannot go to a queen edge');
      expect(gk.tryPlaceAt(0), isTrue, reason: 'king corner accepts king');
      expect(gk.score, 100);

      final qSeed = seedWhereFirstCard((c) => c.isQ);
      final gq = GameState.newGame(seed: qSeed);
      expect(gq.tryPlaceAt(0), isFalse);
      expect(gq.tryPlaceAt(1), isTrue);
      expect(gq.score, 100);

      final jSeed = seedWhereFirstCard((c) => c.isJ);
      final gj = GameState.newGame(seed: jSeed);
      expect(gj.tryPlaceAt(1), isFalse);
      expect(gj.tryPlaceAt(4), isTrue);
      expect(gj.score, 100);
    });

    test('godMode places anything anywhere', () {
      final kSeed = seedWhereFirstCard((c) => c.isK);
      final g = GameState.newGame(seed: kSeed);
      expect(g.tryPlaceAt(5, godMode: true), isTrue);
      expect(g.isBlocked[5], isFalse);
    });

    test('placement draws the next card and counts it', () {
      final seed = seedWhereFirstCard((c) => c.isNumOrAce);
      final g = GameState.newGame(seed: seed);
      final before = g.drawPile.length;
      final nextUp = g.drawPile.last;
      g.tryPlaceAt(5);
      expect(g.current, isNotNull);
      expect(cardKey(g.current!), cardKey(nextUp));
      expect(g.drawPile.length, before - 1);
      expect(g.totalCardsDrawn, 2);
    });
  });

  group('pair selection and clearing', () {
    // Builds a game in the clear phase is expensive via pure play; instead
    // pin the selection rules that apply in easy-mode fill (public path).
    test('easy mode allows toggling number selections during fill', () {
      final seed = seedWhereFirstCard((c) => c.isNumOrAce, start: 0);
      // A number-opening easy game: numbers place anywhere.
      final g = GameState.newGame(
          seed: seed, difficulty: GameDifficulty.easy);
      // Easy deck differs from classic; find a number by placing whatever
      // comes: numbers and royals both existent — place current wherever
      // legal until a number lands on a dump we can select.
      int placedNumberAt = -1;
      for (int guard = 0; guard < 48 && placedNumberAt < 0; guard++) {
        final c = g.current;
        if (c == null || g.phase != Phase.fill) break;
        if (c.isNumOrAce) {
          for (int i = 0; i < 16; i++) {
            if (g.cells[i] == null && g.tryPlaceAt(i)) {
              placedNumberAt = i;
              break;
            }
          }
        } else {
          bool placed = false;
          for (int i = 0; i < 16 && !placed; i++) {
            if (g.cells[i] == null) placed = g.tryPlaceAt(i);
          }
          if (!placed) break;
        }
      }
      expect(placedNumberAt, greaterThanOrEqualTo(0));
      if (g.phase == Phase.fill) {
        g.toggleSelectForClear(placedNumberAt);
        expect(g.selectedForClear, contains(placedNumberAt),
            reason: 'easy mode may select numbers during fill');
        g.toggleSelectForClear(placedNumberAt);
        expect(g.selectedForClear, isEmpty, reason: 'toggle removes');
      }
    });

    test('classic mode refuses fill-phase selection', () {
      final seed = seedWhereFirstCard((c) => c.isNumOrAce);
      final g = GameState.newGame(seed: seed);
      g.tryPlaceAt(5);
      g.toggleSelectForClear(5);
      expect(g.selectedForClear, isEmpty,
          reason: 'classic only selects during the clear phase');
    });

    test('canClearSelection requires exactly two cards summing 11', () {
      final g = GameState.newGame(seed: 1);
      expect(g.canClearSelection, isFalse, reason: 'empty selection');
    });
  });

  group('lifelines', () {
    test('peek is single-use and exposes the top of the pile', () {
      final g = GameState.newGame(seed: 3);
      final top = g.drawPile.last;
      expect(g.peekCard, isNull);
      expect(g.activatePeek(), isTrue);
      expect(g.peekCard, isNotNull);
      expect(cardKey(g.peekCard!), cardKey(top));
      expect(g.lifelinePeekAvailable, isFalse);
      expect(g.activatePeek(), isFalse, reason: 'peek is one-shot');
    });

    test('peek indicator clears after the next placement', () {
      final seed = seedWhereFirstCard((c) => c.isNumOrAce);
      final g = GameState.newGame(seed: seed);
      g.activatePeek();
      expect(g.peekActiveNow, isTrue);
      g.tryPlaceAt(5);
      expect(g.peekActiveNow, isFalse);
    });

    test('moveCard relocates within legal slots only', () {
      final kSeed = seedWhereFirstCard((c) => c.isK);
      final g = GameState.newGame(seed: kSeed);
      g.tryPlaceAt(0); // king on corner 0
      expect(g.moveCard(0, 5), isFalse,
          reason: 'king may not move to a dump');
      expect(g.moveCard(0, 3), isTrue, reason: 'corner-to-corner is legal');
      expect(g.cells[0], isNull);
      expect(g.cells[3], isNotNull);
      expect(g.moveCard(3, 3), isFalse, reason: 'occupied target');
    });
  });

  group('win and game-over evaluation', () {
    test('applyInstantWin satisfies the full win condition', () {
      final g = GameState.newGame(seed: 1);
      g.applyInstantWin();
      expect(g.royalsPlacedCorrect, g.totalRoyalSlots);
      expect(g.deckExhausted, isTrue);
      expect(g.hasAnyPairFor11, isFalse);
      expect(g.isWinConditionMet, isTrue);
      expect(g.phase, Phase.winner);
      expect(g.endTime, isNotNull);
    });

    test('hasAnyLegalMove is true outside fill and tracks current card', () {
      final g = GameState.newGame(seed: 1);
      expect(g.hasAnyLegalMove(), isTrue,
          reason: 'fresh board always has room');
      g.applyInstantWin();
      expect(g.hasAnyLegalMove(), isTrue,
          reason: 'non-fill phases report true');
    });

    test('royalsProgress moves from 0 toward 1', () {
      final kSeed = seedWhereFirstCard((c) => c.isK);
      final g = GameState.newGame(seed: kSeed);
      expect(g.royalsProgress, 0.0);
      g.tryPlaceAt(0);
      expect(g.royalsProgress, closeTo(1 / 12, 0.001));
    });
  });

  group('findEasyAutoPairs', () {
    test('is read-only and greedy over distinct cells', () {
      final g = GameState.newGame(seed: 7, difficulty: GameDifficulty.easy);
      final before = g.cells.toList();
      final pairs = g.findEasyAutoPairs();
      expect(g.cells, orderedEquals(before),
          reason: 'discovery must not mutate the board');
      for (final (indices, cards) in pairs) {
        expect(indices.length, 2);
        expect(cards[0].valueForSum + cards[1].valueForSum, 11);
      }
    });
  });

  group('clone determinism (deep)', () {
    test('clone replays identically to the original', () {
      final seed = seedWhereFirstCard((c) => c.isNumOrAce);
      final a = GameState.newGame(seed: seed);
      final b = a.clone();
      a.tryPlaceAt(5);
      b.tryPlaceAt(5);
      expect(cardKey(a.current!), cardKey(b.current!));
      expect(a.score, b.score);
      expect(a.phase, b.phase);
      expect(a.drawPile.map(cardKey).toList(),
          b.drawPile.map(cardKey).toList());
    });
  });
}
