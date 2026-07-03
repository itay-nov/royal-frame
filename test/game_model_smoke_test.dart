// Characterization smoke tests for the game engine.
//
// The engine (lib/models/game_model.dart) is LOCKED: these tests pin its
// current observable behavior so any accidental change during UI/structural
// refactors fails fast. They deliberately avoid asserting on specific shuffle
// outcomes — only shuffle-independent invariants are checked here.
// A fuller suite lives in game_model_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/models/game_model.dart';

String cardKey(CardModel c) => '${c.label}${suitSymbol(c.suit)}';

void main() {
  group('deck composition', () {
    test('classic: 52-card deck, four kings in play, 12 royal slots', () {
      final g = GameState.newGame(seed: 42, difficulty: GameDifficulty.classic);
      expect(g.initialDeckCount, 52);
      expect(g.drawPile.length, 51, reason: 'one card drawn as current');
      expect(g.current, isNotNull);
      expect(g.totalCardsDrawn, 1);
      expect(g.totalRoyalSlots, 12);
      final all = [...g.drawPile, g.current!];
      expect(all.where((c) => c.isK).length, 4);
      expect(all.where((c) => c.isQ).length, 4);
      expect(all.where((c) => c.isJ).length, 4);
    });

    test('expert: same 52-card deck, sudden death enabled', () {
      final g = GameState.newGame(seed: 7, difficulty: GameDifficulty.expert);
      expect(g.initialDeckCount, 52);
      expect(g.isSuddenDeath, isTrue);
    });

    test('easy/medium: kings omitted, corners become dumps, 8 royal slots',
        () {
      for (final d in [GameDifficulty.easy, GameDifficulty.medium]) {
        final g = GameState.newGame(seed: 42, difficulty: d);
        expect(g.initialDeckCount, 48, reason: '$d omits kings');
        expect(g.drawPile.length, 47);
        final all = [...g.drawPile, g.current!];
        expect(all.any((c) => c.isK), isFalse);
        expect(g.totalRoyalSlots, 8);
        for (final i in [0, 3, 12, 15]) {
          expect(g.layout[i], SlotType.innerDump,
              reason: 'king corner $i converts to dump on $d');
        }
        expect(g.isSuddenDeath, isFalse);
      }
    });
  });

  group('seed determinism', () {
    test('same seed produces identical draw sequence and current card', () {
      final a = GameState.newGame(seed: 1234);
      final b = GameState.newGame(seed: 1234);
      expect(cardKey(a.current!), cardKey(b.current!));
      expect(a.drawPile.map(cardKey).toList(),
          b.drawPile.map(cardKey).toList());
    });

    test('different seeds produce a different order', () {
      final a = GameState.newGame(seed: 1);
      final b = GameState.newGame(seed: 2);
      expect(a.drawPile.map(cardKey).toList(),
          isNot(equals(b.drawPile.map(cardKey).toList())));
    });
  });

  group('clone independence', () {
    test('mutating a clone leaves the original untouched', () {
      final g = GameState.newGame(seed: 99);
      final pileSnapshot = g.drawPile.map(cardKey).toList();
      final c = g.clone();

      c.cells[0] = c.current;
      c.isBlocked[0] = true;
      c.drawPile.removeLast();
      c.selectedForClear.add(3);
      c.clearedCards.add(c.drawPile.last);
      c.score += 500;

      expect(g.cells[0], isNull);
      expect(g.isBlocked[0], isFalse);
      expect(g.drawPile.map(cardKey).toList(), pileSnapshot);
      expect(g.selectedForClear, isEmpty);
      expect(g.clearedCards, isEmpty);
      expect(g.score, 0);
    });
  });

  group('initial state and scoring constants', () {
    test('new game starts in fill phase, zero score, classic default', () {
      final g = GameState.newGame(seed: 5);
      expect(g.phase, Phase.fill);
      expect(g.score, 0);
      expect(g.difficulty, GameDifficulty.classic);
      expect(g.lifelineMoveAvailable, isTrue);
      expect(g.lifelinePeekAvailable, isTrue);
    });

    test('score multiplier table is pinned', () {
      double mult(GameDifficulty d) =>
          GameState.newGame(seed: 1, difficulty: d).scoreMultiplier;
      expect(mult(GameDifficulty.easy), 0.25);
      expect(mult(GameDifficulty.medium), 0.5);
      expect(mult(GameDifficulty.classic), 1.0);
      expect(mult(GameDifficulty.expert), 2.0);
    });

    test('applyInstantWin reaches winner phase with the debug score', () {
      final g = GameState.newGame(seed: 1);
      g.applyInstantWin();
      expect(g.phase, Phase.winner);
      expect(g.score, 1200);
      expect(g.deckExhausted, isTrue);
      expect(g.isWinConditionMet, isTrue);
    });
  });
}
