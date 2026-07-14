import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/models/game_model.dart';

void main() {
  group('public API hardening', () {
    test('terminal state is explicit for winner and game over only', () {
      final game = GameState.newGame(seed: 7);
      expect(game.isTerminal, isFalse);

      game.phase = Phase.clear;
      expect(game.isTerminal, isFalse);

      game.phase = Phase.winner;
      expect(game.isTerminal, isTrue);

      game.phase = Phase.gameOver;
      expect(game.isTerminal, isTrue);
    });

    test('invalid cell indices are rejected without mutating state', () {
      final game = GameState.newGame(seed: 7);
      final before = game.clone();

      expect(game.tryPlaceAt(-1), isFalse);
      expect(game.tryPlaceAt(game.cells.length), isFalse);
      expect(game.moveCard(-1, 0), isFalse);
      expect(game.moveCard(0, game.cells.length), isFalse);
      game.toggleSelectForClear(-1);
      game.toggleSelectForClear(game.cells.length);

      expect(game.current, same(before.current));
      expect(game.drawPile, orderedEquals(before.drawPile));
      expect(game.cells, orderedEquals(before.cells));
      expect(game.selectedForClear, isEmpty);
    });
  });

  group('seeded game invariants', () {
    for (final difficulty in GameDifficulty.values) {
      test('${difficulty.name}: card conservation and terminal timestamps', () {
        for (var seed = 0; seed < 100; seed++) {
          final game = GameState.newGame(seed: seed, difficulty: difficulty);

          for (var step = 0; step < 200; step++) {
            _expectCardConservation(game, reason: 'seed=$seed step=$step');

            if (game.phase == Phase.winner || game.phase == Phase.gameOver) {
              expect(
                game.endTime,
                isNotNull,
                reason: 'seed=$seed ended without a timestamp',
              );
              break;
            }

            if (game.phase == Phase.fill) {
              final legalSlots = <int>[];
              for (var i = 0; i < game.cells.length; i++) {
                final probe = game.clone();
                if (probe.tryPlaceAt(i)) {
                  legalSlots.add(i);
                }
              }

              if (legalSlots.isEmpty) {
                game.evaluateGameOverInFill();
              } else {
                final index = legalSlots[(seed + step) % legalSlots.length];
                expect(game.tryPlaceAt(index), isTrue);
              }
            } else if (game.phase == Phase.clear) {
              final pair = _firstElevenPair(game);
              expect(pair, isNotNull, reason: 'clear phase must expose a pair');
              game.toggleSelectForClear(pair!.$1);
              game.toggleSelectForClear(pair.$2);
              expect(game.canClearSelection, isTrue);
              game.performClear();
            }

            if (step == 199) {
              fail('seed=$seed did not terminate within the step budget');
            }
          }
        }
      });
    }
  });
}

void _expectCardConservation(GameState game, {required String reason}) {
  final cardsInState =
      game.drawPile.length +
      game.cells.whereType<CardModel>().length +
      game.clearedCards.length +
      (game.current == null ? 0 : 1);
  expect(cardsInState, game.initialDeckCount, reason: reason);
}

(int, int)? _firstElevenPair(GameState game) {
  for (var first = 0; first < game.cells.length; first++) {
    final firstCard = game.cells[first];
    if (firstCard == null || !firstCard.isNumOrAce) continue;
    for (var second = first + 1; second < game.cells.length; second++) {
      final secondCard = game.cells[second];
      if (secondCard == null || !secondCard.isNumOrAce) continue;
      if (firstCard.valueForSum + secondCard.valueForSum == 11) {
        return (first, second);
      }
    }
  }
  return null;
}
