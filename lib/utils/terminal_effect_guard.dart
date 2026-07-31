import '../models/game_model.dart';

/// Claims terminal side effects once on both the UI State and the game model.
class TerminalEffectGuard {
  bool _handled = false;

  bool get handled => _handled;

  bool claim(GameState game) {
    if (_handled ||
        game.terminalEffectsApplied ||
        (game.phase != Phase.winner && game.phase != Phase.gameOver)) {
      return false;
    }
    _handled = true;
    game.terminalEffectsApplied = true;
    return true;
  }

  void reset() => _handled = false;
}

/// Orders terminal rewards after their backing services have loaded.
///
/// A failed load skips only the affected local reward path. The caller can
/// keep UI effects non-blocking by not awaiting [apply] from the render path.
class TerminalProgressCoordinator {
  TerminalProgressCoordinator({
    required Future<void> dailyGoalLoad,
    required Future<void> xpLoad,
  }) : _dailyGoalReady = _settle(dailyGoalLoad),
       _xpReady = _settle(xpLoad);

  final Future<bool> _dailyGoalReady;
  final Future<bool> _xpReady;

  static Future<bool> _settle(Future<void> load) async {
    try {
      await load;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> apply({
    required Future<void> Function() applyDailyGoals,
    required Future<void> Function() applyXp,
    void Function(String service)? onLoadFailure,
  }) async {
    if (await _dailyGoalReady) {
      await applyDailyGoals();
    } else {
      onLoadFailure?.call('daily goals');
    }

    if (await _xpReady) {
      await applyXp();
    } else {
      onLoadFailure?.call('XP');
    }
  }
}
