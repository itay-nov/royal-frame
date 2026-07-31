import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/models/game_model.dart';
import 'package:royal_frame/utils/terminal_effect_guard.dart';

int _cardCount(GameState game) {
  return game.drawPile.length +
      game.clearedCards.length +
      game.cells.whereType<CardModel>().length +
      (game.current == null ? 0 : 1);
}

void _playDeterministically(GameState game) {
  for (var turn = 0; turn < 300; turn++) {
    expect(_cardCount(game), game.initialDeckCount);
    if (game.phase == Phase.winner || game.phase == Phase.gameOver) return;

    if (game.phase == Phase.fill) {
      var placed = false;
      for (var index = 0; index < game.cells.length; index++) {
        if (game.tryPlaceAt(index)) {
          placed = true;
          break;
        }
      }
      if (!placed) game.evaluateGameOverInFill();
      continue;
    }

    final pair = game.findEasyAutoPairs();
    if (pair.isNotEmpty) {
      final indices = pair.first.$1;
      game
        ..toggleSelectForClear(indices[0])
        ..toggleSelectForClear(indices[1])
        ..performClear();
    } else {
      game.resumeFill();
    }
  }
}

void main() {
  test('invalid indices fail safely without mutation', () {
    final game = GameState.newGame(seed: 7);
    final before = game.clone();

    expect(game.tryPlaceAt(-1), isFalse);
    expect(game.tryPlaceAt(game.cells.length), isFalse);
    expect(() => game.toggleSelectForClear(-1), returnsNormally);
    expect(() => game.toggleSelectForClear(game.cells.length), returnsNormally);
    expect(game.moveCard(-1, 0), isFalse);
    expect(game.moveCard(0, game.cells.length), isFalse);
    game.autoRemoveFoundPairs([
      ([game.cells.length], [const CardModel(Suit.spade, Ace())]),
    ]);

    expect(game.cells, before.cells);
    expect(game.drawPile, before.drawPile);
    expect(game.current, before.current);
    expect(game.selectedForClear, before.selectedForClear);
    expect(game.clearedCards, before.clearedCards);
    expect(game.score, before.score);
  });

  test('cards are conserved for deterministic games at every difficulty', () {
    for (final difficulty in GameDifficulty.values) {
      for (final seed in [0, 1, 7, 2026, 987654]) {
        final game = GameState.newGame(seed: seed, difficulty: difficulty);
        _playDeterministically(game);
        expect(
          _cardCount(game),
          game.initialDeckCount,
          reason: '${difficulty.name} seed $seed',
        );
      }
    }
  });

  test('terminal effects survive guard reconstruction for the same game', () {
    final game = GameState.newGame(seed: 1)..phase = Phase.winner;
    final firstGuard = TerminalEffectGuard();
    final reconstructedGuard = TerminalEffectGuard();

    expect(firstGuard.claim(game), isTrue);
    expect(firstGuard.claim(game), isFalse);
    expect(reconstructedGuard.claim(game), isFalse);
    expect(reconstructedGuard.claim(game.clone()), isFalse);
  });

  test('non-terminal games do not claim terminal effects', () {
    final game = GameState.newGame(seed: 2);

    expect(TerminalEffectGuard().claim(game), isFalse);
    expect(game.terminalEffectsApplied, isFalse);
  });

  test('different terminal games each receive their effects', () {
    final first = GameState.newGame(seed: 1)..phase = Phase.winner;
    final second = GameState.newGame(seed: 1)..phase = Phase.gameOver;

    expect(TerminalEffectGuard().claim(first), isTrue);
    expect(TerminalEffectGuard().claim(second), isTrue);
  });

  test('terminal progress waits for delayed goal and XP loads', () async {
    final dailyLoad = Completer<void>();
    final xpLoad = Completer<void>();
    final events = <String>[];
    final coordinator = TerminalProgressCoordinator(
      dailyGoalLoad: dailyLoad.future,
      xpLoad: xpLoad.future,
    );

    final application = coordinator.apply(
      applyDailyGoals: () async {
        events.add('daily');
      },
      applyXp: () async {
        events.add('xp');
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);

    dailyLoad.complete();
    await Future<void>.delayed(Duration.zero);
    expect(events, ['daily']);

    xpLoad.complete();
    await application;
    expect(events, ['daily', 'xp']);
  });

  test('failed progress-service loads skip only affected rewards', () async {
    final failures = <String>[];
    var dailyApplied = false;
    var xpApplied = false;
    final coordinator = TerminalProgressCoordinator(
      dailyGoalLoad: Future<void>.error(StateError('daily unavailable')),
      xpLoad: Future<void>.value(),
    );

    await coordinator.apply(
      applyDailyGoals: () async {
        dailyApplied = true;
      },
      applyXp: () async {
        xpApplied = true;
      },
      onLoadFailure: failures.add,
    );

    expect(dailyApplied, isFalse);
    expect(xpApplied, isTrue);
    expect(failures, ['daily goals']);
  });
}
