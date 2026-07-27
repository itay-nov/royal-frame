import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/models/game_model.dart';

const _centerSlots = [5, 6, 9, 10];

CardModel _number(int value, [Suit suit = Suit.spade]) =>
    CardModel(suit, value == 1 ? const Ace() : Num(value));

GameState _completedFrameInFill() {
  final game = GameState.newGame(seed: 1);
  game.applyInstantWin();
  game
    ..phase = Phase.fill
    ..endTime = null;
  return game;
}

void _fillFirstThreeCenterSlots(GameState game, List<int> values) {
  expect(values, hasLength(3));
  for (int i = 0; i < values.length; i++) {
    game.cells[_centerSlots[i]] = _number(values[i], Suit.values[i]);
    game.isBlocked[_centerSlots[i]] = false;
  }
}

void main() {
  group('completed royal frame terminal evaluation', () {
    test('continues filling while the current card has a legal placement', () {
      final game = _completedFrameInFill();
      game
        ..current = _number(2)
        ..drawPile.add(_number(3, Suit.heart));

      expect(game.tryPlaceAt(_centerSlots.first), isTrue);

      expect(game.isRoyalFrameComplete, isTrue);
      expect(game.phase, Phase.fill);
      expect(game.current?.valueForSum, 3);
      expect(game.endTime, isNull);
    });

    test('enters clearing when a full board contains an 11-pair', () {
      final game = _completedFrameInFill();
      _fillFirstThreeCenterSlots(game, [1, 10, 2]);
      game
        ..current = _number(3, Suit.club)
        ..drawPile.add(_number(4, Suit.heart));

      expect(game.tryPlaceAt(_centerSlots.last), isTrue);

      expect(game.isRoyalFrameComplete, isTrue);
      expect(game.hasAnyPairFor11, isTrue);
      expect(game.phase, Phase.clear);
      expect(game.endTime, isNull);
    });

    test(
      'wins with a full completed frame and no 11-pair while cards remain',
      () {
        final game = _completedFrameInFill();
        _fillFirstThreeCenterSlots(game, [2, 2, 2]);
        game
          ..current = _number(2, Suit.club)
          ..drawPile.add(_number(9, Suit.heart));

        expect(game.tryPlaceAt(_centerSlots.last), isTrue);

        expect(game.isRoyalFrameComplete, isTrue);
        expect(game.hasAnyPairFor11, isFalse);
        expect(game.drawPile, isNotEmpty);
        expect(game.cardsRemainingDisplay, 1);
        expect(game.phase, Phase.winner);
        expect(game.endTime, isNotNull);
      },
    );

    test('loses with a full incomplete frame and no 11-pair', () {
      final game = _completedFrameInFill();
      game
        ..cells[0] = _number(2)
        ..isBlocked[0] = true;
      _fillFirstThreeCenterSlots(game, [2, 2, 2]);
      game
        ..current = _number(2, Suit.club)
        ..drawPile.add(_number(9, Suit.heart));

      expect(game.tryPlaceAt(_centerSlots.last), isTrue);

      expect(game.isRoyalFrameComplete, isFalse);
      expect(game.hasAnyPairFor11, isFalse);
      expect(game.phase, Phase.gameOver);
      expect(game.endTime, isNotNull);
    });

    test(
      'wins when the completed frame has no action and the deck is empty',
      () {
        final game = _completedFrameInFill();
        _fillFirstThreeCenterSlots(game, [2, 2, 2]);
        game.current = _number(2, Suit.club);

        expect(game.tryPlaceAt(_centerSlots.last), isTrue);

        expect(game.isRoyalFrameComplete, isTrue);
        expect(game.hasAnyPairFor11, isFalse);
        expect(game.deckExhausted, isTrue);
        expect(game.phase, Phase.winner);
      },
    );

    test(
      'remaining draw-pile cards do not block an otherwise terminal win',
      () {
        final game = _completedFrameInFill();
        game
          ..current = const CardModel(Suit.spade, King())
          ..drawPile.add(_number(2));

        expect(game.hasAnyLegalMove(), isFalse);
        game.evaluateGameOverInFill();

        expect(game.isRoyalFrameComplete, isTrue);
        expect(game.drawPile, isNotEmpty);
        expect(game.phase, Phase.winner);
      },
    );
  });
}
