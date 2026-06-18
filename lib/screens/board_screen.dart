import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme_constants.dart';
import '../models/game_model.dart';
import '../utils/localization.dart';
import '../widgets/tutorial_overlay.dart';
import '../services/db_service.dart';
import '../services/haptic_service.dart';
import '../services/duel_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/daily_goal_service.dart';
import '../services/xp_service.dart';
import '../services/badge_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BOARD SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class BoardScreen extends StatefulWidget {
  final GameState? existingGame;
  final bool forceTutorial;
  // When true, the difficulty picker opens immediately on first frame.
  final bool showNewGamePicker;
  // Duel mode — set by DuelSetupScreen when a match is found.
  final DuelSession? duelSession;
  final bool isHost;
  final AppLang? initialLang;

  const BoardScreen({
    super.key,
    this.existingGame,
    this.forceTutorial = false,
    this.showNewGamePicker = false,
    this.duelSession,
    this.isHost = false,
    this.initialLang,
  });

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late GameState game;
  final List<GameState> _undo = [];
  final List<GameState> _redo = [];

  // Current difficulty – persists across sessions via SharedPreferences.
  GameDifficulty _difficulty = GameDifficulty.hard;
  static const String _difficultyPrefKey = 'royalFrameDifficulty';

  Timer? _inactivityTimer;
  Timer? _uiTimer;

  // Duel mode state
  DuelSession? _duelSession;
  StreamSubscription<DuelSession?>? _duelSub;
  int _opponentScore = 0;
  bool _duelFinishedReported = false;

  // Extreme countdown limit in seconds.
  static const int _extremeSeconds = 180;

  void _pauseGameTimer() {
    if (game.pausedAt != null) return;
    game.pausedAt = DateTime.now();
    _uiTimer?.cancel();
    _inactivityTimer?.cancel();
  }

  void _resumeGameTimer() {
    if (game.pausedAt == null) return;
    final pausedDuration = DateTime.now().difference(game.pausedAt!);
    game.startTime = game.startTime.add(pausedDuration);
    game.pausedAt = null;
    if (game.phase != Phase.gameOver && game.phase != Phase.winner) {
      _startUITimer();
      _restartHintTimer();
    }
    if (mounted) setState(() {});
  }

  Set<int> _hintedPair = {};
  bool _hintCurrentCard = false;
  late AnimationController _hintPulseCtrl;

  // Phase-transition pulse
  late AnimationController _phasePulseCtrl;
  bool _showPhasePulse = false;
  String _phaseLabel = '';

  bool _moveMode = false;
  int? _moveFromIndex;
  bool _showDebugTools = false;

  bool _godMode = false;

  CardModel? _draggingCard;

  late AppLang _lang;
  L get _l => L(_lang);

  bool _showGameOverOverlay = false;
  bool _isAnimatingClear = false;
  Set<int> _errorHighlights = {};

  bool _showTutorial = false;
  bool _showClearTutorial = false;
  bool _hasSeenInitialTutorial = false;
  bool _hasSeenClearTutorial = false;
  bool _tutorialStateLoaded = false;

  // Prevents duplicate XP awards if _checkEndState is called more than once.
  bool _xpAwardedThisGame = false;
  // Prevents duplicate stats/goal updates when overlay rebuilds.
  bool _statsUpdatedThisGame = false;

  // Optional-clearing setting
  static const String _optionalClearingPrefKey = 'royalFrameOptionalClearing';
  bool _optionalClearing = false;
  bool _clearedAtLeastOnePairThisPhase = false;

  // Audio
  static const String _mutePrefKey = 'royalFrameMuted';
  bool _isMuted = false;
  final AudioPlayer _winPlayer   = AudioPlayer();
  final AudioPlayer _lossPlayer  = AudioPlayer();
  final AudioPlayer _popPlayer   = AudioPlayer();
  final AudioPlayer _placePlayer = AudioPlayer();
  final AudioPlayer _phasePlayer = AudioPlayer();

  bool _isAudioInitialized = false;
  bool _audioUnlocked = false;

  // Confetti
  late ConfettiController _confettiCtrl;

  final GlobalKey _clearPileKey = GlobalKey();
  final GlobalKey _deckRowKey   = GlobalKey();
  final GlobalKey _gridKey      = GlobalKey();
  late final List<GlobalKey> _cellKeys;

  @override
  void initState() {
    super.initState();
    _lang = widget.initialLang ?? AppLang.en;
    WidgetsBinding.instance.addObserver(this);
    _cellKeys = List.generate(16, (_) => GlobalKey());
    _confettiCtrl = ConfettiController(duration: const Duration(seconds: 6));
    _hintPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _phasePulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    game = widget.existingGame ?? GameState.newGame();
    _difficulty = game.difficulty;
    _loadSavedDifficulty();

    if (game.pausedAt != null) {
      final pausedDuration = DateTime.now().difference(game.pausedAt!);
      game.startTime = game.startTime.add(pausedDuration);
      game.pausedAt = null;
    }

    game.evaluateGameOverInFill();

    if (widget.showNewGamePicker) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) { if (mounted) _openDifficultyPicker(); },
      );
    }

    _initAudio();
    _loadMuteState();
    _loadSavedLang();
    HapticService.load();
    _loadTutorialState();
    _startUITimer();
    DailyGoalService.load();
    XpService.load();
    BadgeService.load();
    _initDuelMode();
  }

  // ── Duel mode ──────────────────────────────────────────────────────────────

  void _initDuelMode() {
    if (widget.duelSession == null) return;
    _duelSession = widget.duelSession;

    // In duel mode use the shared seed so both players get the same deck.
    final seed = _duelSession!.seed;
    game = GameState.newGame(seed: seed);
    game.evaluateGameOverInFill();

    _duelSub = DuelService.watchDuel(_duelSession!.duelId).listen((updated) {
      if (!mounted || updated == null) return;
      setState(() {
        _duelSession = updated;
        final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final isHost = updated.hostUid == myUid;
        _opponentScore = isHost ? updated.guestScore : updated.hostScore;
      });
    });
  }

  Future<void> _syncDuelScore() async {
    if (_duelSession == null) return;
    await DuelService.syncScore(_duelSession!.duelId, game.score);
  }

  Future<void> _loadSavedDifficulty() async {
    if (widget.existingGame != null) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_difficultyPrefKey) ?? 'hard';
    if (!mounted) return;
    setState(() {
      _difficulty = switch (saved) {
        'medium'  => GameDifficulty.medium,
        'extreme' => GameDifficulty.extreme,
        _         => GameDifficulty.hard,
      };
    });
  }

  Future<void> _loadSavedLang() async {
    if (widget.initialLang != null) return;
    final lang = await L.loadLang();
    if (!mounted) return;
    setState(() => _lang = lang);
  }

  Future<void> _loadTutorialState() async {
    final prefs = await SharedPreferences.getInstance();
    final playerId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';

    _hasSeenInitialTutorial =
        prefs.getBool('hasSeenTutorialV2_$playerId') ?? false;
    _hasSeenClearTutorial =
        prefs.getBool('hasSeenClearTutorialV2_$playerId') ?? false;

    if (widget.forceTutorial) {
      setState(() {
        if (game.phase == Phase.clear) {
          _showClearTutorial = true;
        } else {
          _showTutorial = true;
        }
      });
      _inactivityTimer?.cancel();
      _hintPulseCtrl.stop();
      _hintCurrentCard = false;
      _hintedPair.clear();
      return;
    }

    if (!_hasSeenInitialTutorial) {
      setState(() => _showTutorial = true);
      _inactivityTimer?.cancel();
      _hintPulseCtrl.stop();
      _hintCurrentCard = false;
      _hintedPair.clear();
      await prefs.setBool('hasSeenTutorialV2_$playerId', true);
    }

    _tutorialStateLoaded = true;
  }

  Future<void> _loadMuteState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isMuted = prefs.getBool(_mutePrefKey) ?? false;
      _optionalClearing = prefs.getBool(_optionalClearingPrefKey) ?? false;
    });
  }

  Future<void> _toggleMute() async {
    final prefs = await SharedPreferences.getInstance();
    final newValue = !_isMuted;
    await prefs.setBool(_mutePrefKey, newValue);
    if (!mounted) return;
    setState(() => _isMuted = newValue);
    if (newValue) {
      try {
        await _winPlayer.stop();
        await _lossPlayer.stop();
        await _popPlayer.stop();
        await _placePlayer.stop();
        await _phasePlayer.stop();
      } catch (_) {}
    }
  }

  Future<void> _toggleHaptic() async {
    await HapticService.setEnabled(!HapticService.isEnabled);
    if (mounted) setState(() {});
  }

  Future<void> _toggleOptionalClearing() async {
    final prefs = await SharedPreferences.getInstance();
    final newValue = !_optionalClearing;
    await prefs.setBool(_optionalClearingPrefKey, newValue);
    setState(() => _optionalClearing = newValue);
  }

  void _startUITimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (game.phase == Phase.winner || game.phase == Phase.gameOver) return;

      // Extreme: count-down bomb. Fire game-over when time runs out.
      if (game.isSuddenDeath && !_xpAwardedThisGame) {
        final elapsed =
            DateTime.now().difference(game.startTime).inSeconds;
        if (elapsed >= _extremeSeconds) {
          _triggerBombGameOver();
          return;
        }
      }

      setState(() {});
    });
  }

  // Called by the extreme bomb timer when countdown reaches zero.
  void _triggerBombGameOver() {
    game.phase = Phase.gameOver;
    game.endTime ??= DateTime.now();
    setState(() {});
    _checkEndState();
  }

  void _restartHintTimer() {
    _inactivityTimer?.cancel();

    if (_showTutorial || _showClearTutorial) return;

    if (_hintedPair.isNotEmpty || _hintCurrentCard) {
      setState(() {
        _hintedPair.clear();
        _hintCurrentCard = false;
      });
      _hintPulseCtrl.stop();
      _hintPulseCtrl.value = 1.0;
    }

    if (game.phase == Phase.clear && game.hasAnyPairFor11) {
      _inactivityTimer = Timer(const Duration(seconds: 7), () {
        if (mounted &&
            game.phase == Phase.clear &&
            !_isAnimatingClear &&
            !_showClearTutorial) {
          final nums = <int, int>{};
          for (int i = 0; i < game.cells.length; i++) {
            final c = game.cells[i];
            if (c != null && c.isNumOrAce) nums[i] = c.valueForSum;
          }
          final idxList = nums.keys.toList();
          for (int a = 0; a < idxList.length; a++) {
            for (int b = a + 1; b < idxList.length; b++) {
              if (nums[idxList[a]]! + nums[idxList[b]]! == 11) {
                setState(() => _hintedPair = {idxList[a], idxList[b]});
                _hintPulseCtrl.repeat(reverse: true);
                return;
              }
            }
          }
        }
      });
    } else if (game.phase == Phase.fill && game.current != null) {
      _inactivityTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && game.phase == Phase.fill && !_showTutorial) {
          setState(() => _hintCurrentCard = true);
          _hintPulseCtrl.repeat(reverse: true);
        }
      });
    }
  }

  Offset? _globalCenter(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  void _animateClearToPile(
    List<int> indices,
    List<CardModel> cards,
    VoidCallback onDone,
  ) {
    final target = _globalCenter(_clearPileKey);
    if (target == null || cards.isEmpty) {
      onDone();
      return;
    }

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    var pending = cards.length;

    void oneFinished() {
      pending--;
      if (pending == 0) {
        entry.remove();
        onDone();
      }
    }

    entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (int k = 0; k < cards.length; k++)
              _FlyingClearCard(
                from: _globalCenter(_cellKeys[indices[k]]) ?? target,
                to: target,
                card: _playingCard(cards[k]),
                onComplete: oneFinished,
              ),
          ],
        ),
      ),
    );
    overlay.insert(entry);
  }

  Future<void> _initAudio() async {
    if (_isAudioInitialized) return;
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.soloAmbient,
            options: const {},
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.game,
            audioFocus: AndroidAudioFocus.gainTransient,
          ),
        ),
      );
      await _winPlayer.setReleaseMode(ReleaseMode.stop);
      await _lossPlayer.setReleaseMode(ReleaseMode.stop);
      await _popPlayer.setReleaseMode(ReleaseMode.stop);
      await _placePlayer.setReleaseMode(ReleaseMode.stop);
      await _phasePlayer.setReleaseMode(ReleaseMode.stop);
      await _winPlayer.setSourceAsset('audio/win_cheer.mp3');
      await _lossPlayer.setSourceAsset('audio/game_over.mp3');
      await _popPlayer.setSourceAsset('audio/pop.mp3');
      await _placePlayer.setSourceAsset('audio/place_card.mp3');
      await _phasePlayer.setSourceAsset('audio/pop.mp3');
      _isAudioInitialized = true;
    } catch (_) {}
  }

  void _unlockAudio() {
    if (_audioUnlocked) return;
    _audioUnlocked = true;
    _doUnlock();
  }

  Future<void> _doUnlock() async {
    try {
      for (final p in [
        _winPlayer, _lossPlayer, _popPlayer, _placePlayer, _phasePlayer,
      ]) {
        await p.setVolume(0);
        await p.resume();
        await p.stop();
        await p.setVolume(1);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiTimer?.cancel();
    _inactivityTimer?.cancel();
    _hintPulseCtrl.dispose();
    _phasePulseCtrl.dispose();
    _confettiCtrl.dispose();
    for (final p in [
      _winPlayer, _lossPlayer, _popPlayer, _placePlayer, _phasePlayer,
    ]) {
      try { p.stop(); } catch (_) {}
      p.dispose();
    }
    _duelSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pauseGameTimer();
      _stopAllAudio();
    } else if (state == AppLifecycleState.resumed) {
      _resumeGameTimer();
    }
  }

  Future<void> _stopAllAudio() async {
    for (final p in [
      _winPlayer, _lossPlayer, _popPlayer, _placePlayer, _phasePlayer,
    ]) {
      try {
        await p.setVolume(0.0);
        await p.pause();
      } catch (_) {}
    }
  }

  Future<void> _stopAllAudioNow() async {
    for (final p in [
      _winPlayer, _lossPlayer, _popPlayer, _placePlayer, _phasePlayer,
    ]) {
      try { await p.stop(); } catch (_) {}
    }
  }

  Future<void> _playWin() async {
    if (_isMuted || !mounted) return;
    try {
      await _winPlayer.setVolume(1.0);
      await _winPlayer.seek(Duration.zero);
      if (!mounted) return;
      await _winPlayer.resume();
    } catch (_) {}
  }

  Future<void> _playLoss() async {
    if (_isMuted || !mounted) return;
    try {
      await _lossPlayer.setVolume(1.0);
      await _lossPlayer.seek(Duration.zero);
      if (!mounted) return;
      await _lossPlayer.resume();
    } catch (_) {}
  }

  Future<void> _playPop() async {
    if (_isMuted || !mounted) return;
    try {
      await _popPlayer.setVolume(1.0);
      await _popPlayer.seek(Duration.zero);
      if (!mounted) return;
      await _popPlayer.resume();
    } catch (_) {}
  }

  Future<void> _playPlace() async {
    if (_isMuted || !mounted) return;
    try {
      await _placePlayer.setVolume(1.0);
      await _placePlayer.seek(Duration.zero);
      if (!mounted) return;
      await _placePlayer.resume();
    } catch (_) {}
  }

  void _pushUndo() {
    _undo.add(game.clone());
    _redo.clear();
  }

  void _undoAction() {
    if (_undo.isEmpty) return;
    _redo.add(game.clone());
    setState(() {
      game = _undo.removeLast();
      _moveMode = false;
      _moveFromIndex = null;
      _showGameOverOverlay = game.phase == Phase.gameOver;
    });
    // Stop any lingering win/loss audio so normal sound effects work again.
    _stopAllAudioNow();
    DailyGoalService.addProgress(GoalType.useUndo, 1);
    _restartHintTimer();
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    _undo.add(game.clone());
    setState(() {
      game = _redo.removeLast();
      _moveMode = false;
      _moveFromIndex = null;
      _showGameOverOverlay = game.phase == Phase.gameOver;
    });
    _restartHintTimer();
  }

  // ── New-game flow ──────────────────────────────────────────────────────────

  // Shows the difficulty picker. On selection, calls _executeNewGame.
  // Used by: AppBar refresh icon, "New Game" in main menu, difficulty menu item.
  void _openDifficultyPicker() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _DifficultyPickerDialog(
        current: _difficulty,
        onSelected: (diff) {
          Navigator.pop(context);
          _executeNewGame(diff);
        },
      ),
    );
  }

  // Immediately restarts with the already-selected difficulty — no dialog.
  // Used by: "Play Again" in win/loss overlays.
  void _restartCurrentGame() => _executeNewGame(_difficulty);

  // Alias kept for the 3-dot menu item.
  void _showDifficultyPicker() => _openDifficultyPicker();

  // Initialises the actual game state for the chosen difficulty.
  void _executeNewGame(GameDifficulty diff, {int? seed}) {
    _confettiCtrl.stop();
    _stopAllAudio();

    SharedPreferences.getInstance()
        .then((p) => p.setString(_difficultyPrefKey, diff.name));

    setState(() {
      _difficulty = diff;
      _undo.clear();
      _redo.clear();
      game = GameState.newGame(seed: seed, difficulty: diff);
      game.evaluateGameOverInFill();
      _moveMode = false;
      _moveFromIndex = null;
      _showGameOverOverlay = false;
      _godMode = false;
      _isAnimatingClear = false;
      _errorHighlights.clear();
      _xpAwardedThisGame = false;
      _statsUpdatedThisGame = false;
      _clearedAtLeastOnePairThisPhase = false;
    });
    _restartHintTimer();
    _startUITimer();
  }

  // ── End-state ──────────────────────────────────────────────────────────────

  void _checkEndState() {
    if (game.phase == Phase.winner) {
      DailyGoalService.addProgress(GoalType.finishMatch, 1);
      if (!_xpAwardedThisGame) {
        _xpAwardedThisGame = true;
        final xp = switch (_difficulty) {
          GameDifficulty.medium  => 250,
          GameDifficulty.hard    => 500,
          GameDifficulty.extreme => 1000,
        };
        XpService.addXP(xp);
      }
      // Duel: report final score as winner
      if (_duelSession != null && !_duelFinishedReported) {
        _duelFinishedReported = true;
        DuelService.markFinished(_duelSession!.duelId, game.score);
      }
      setState(() => _showGameOverOverlay = false);
      _confettiCtrl.play();
      _playWin();
    } else if (game.phase == Phase.gameOver) {
      DailyGoalService.addProgress(GoalType.finishMatch, 1);
      if (!_xpAwardedThisGame) {
        _xpAwardedThisGame = true;
        final xp = switch (_difficulty) {
          GameDifficulty.medium  => 25,
          GameDifficulty.hard    => 50,
          GameDifficulty.extreme => 100,
        };
        XpService.addXP(xp);
      }
      // Duel: report final score as loser
      if (_duelSession != null && !_duelFinishedReported) {
        _duelFinishedReported = true;
        DuelService.markFinished(_duelSession!.duelId, game.score);
      }
      setState(() => _showGameOverOverlay = false);
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted &&
            game.phase == Phase.gameOver &&
            ModalRoute.of(context)?.isCurrent == true) {
          setState(() => _showGameOverOverlay = true);
          _playLoss();
        }
      });
    }
    // Push live score to Firestore whenever game is still ongoing.
    if (_duelSession != null &&
        game.phase != Phase.winner &&
        game.phase != Phase.gameOver) {
      _syncDuelScore();
    }
  }

  // ── Sudden-death helpers ──────────────────────────────────────────────────

  void _triggerSuddenDeath() {
    HapticService.heavy();
    game.phase = Phase.gameOver;
    game.endTime ??= DateTime.now();
    setState(() {});
    _checkEndState();
  }

  // Shows a double red-flash on the offending cells, then triggers game over.
  Future<void> _doubleFlashAndGameOver(List<int> indices) async {
    setState(() => _errorHighlights.addAll(indices));
    HapticService.heavy();
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _errorHighlights.removeAll(indices));
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _errorHighlights.addAll(indices));
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _errorHighlights.removeAll(indices));
    game.phase = Phase.gameOver;
    game.endTime ??= DateTime.now();
    setState(() {});
    _checkEndState();
  }

  Future<void> _flashError(List<int> indices) async {
    setState(() => _errorHighlights.addAll(indices));
    HapticService.heavy();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    setState(() => _errorHighlights.removeAll(indices));
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    setState(() => _errorHighlights.addAll(indices));
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _errorHighlights.removeAll(indices));
  }

  // ── Phase-transition feedback ─────────────────────────────────────────────

  void _maybeTriggerPhaseTransitionFeedback(Phase previous, Phase current) {
    if (previous == current) return;
    final isFillToClear = previous == Phase.fill && current == Phase.clear;
    final isClearToFill = previous == Phase.clear && current == Phase.fill;
    if (!isFillToClear && !isClearToFill) return;
    if (isFillToClear) _clearedAtLeastOnePairThisPhase = false;
    _triggerPhaseTransitionFeedback(isFillToClear: isFillToClear);
  }

  void _triggerPhaseTransitionFeedback({required bool isFillToClear}) {
    HapticService.success();

    if (!_isMuted) {
      _phasePlayer.setVolume(isFillToClear ? 0.9 : 0.7);
      _phasePlayer.stop().then((_) {
        if (mounted) {
          _phasePlayer.play(AssetSource('audio/pop.mp3')).catchError((_) {});
        }
      });
    }

    if (!mounted) return;
    setState(() {
      _showPhasePulse = true;
      _phaseLabel = isFillToClear ? 'CLEAR PAIRS' : 'PLACE CARDS';
    });
    _phasePulseCtrl.forward(from: 0).then((_) {
      if (mounted) setState(() => _showPhasePulse = false);
    });
  }

  // ── Input handlers ────────────────────────────────────────────────────────

  void _onTapCell(int i) {
    if (_showTutorial || _showClearTutorial) return;
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
              HapticService.selection();
              _moveFromIndex = null;
              if (!_godMode) {
                _moveMode = false;
                game.lifelineMoveAvailable = false;
              }
            } else {
              _moveFromIndex = null;
              if (game.isSuddenDeath) {
                _undo.removeLast();
              } else {
                _flashError([i]);
              }
            }
          });
          if (ok) {
            _checkEndState();
          } else if (game.isSuddenDeath) {
            _doubleFlashAndGameOver([i]);
          }
          _restartHintTimer();
        } else {
          setState(() => _moveFromIndex = i);
        }
      }
      return;
    }

    if (game.phase == Phase.fill) {
      _pushUndo();
      final previousPhase = game.phase;
      final ok = game.tryPlaceAt(i, godMode: _godMode);

      if (ok) {
        HapticService.light();
        _playPlace();
        _maybeTriggerPhaseTransitionFeedback(previousPhase, game.phase);

        final placedCard = game.cells[i];
        if (placedCard != null &&
            (placedCard.isK || placedCard.isQ || placedCard.isJ)) {
          DailyGoalService.addProgress(GoalType.placeRoyal, 1);
        }
        if (placedCard != null && placedCard.isQ) {
          final queensOnBoard = game.cells
              .whereType<CardModel>()
              .where((c) => c.isQ)
              .length;
          if (queensOnBoard == 4) BadgeService.unlockQueenBadge();
        }
      } else {
        _undo.removeLast();
        if (game.isSuddenDeath) {
          _doubleFlashAndGameOver([i]);
          return;
        }
        _flashError([i]);
      }

      if (game.phase == Phase.clear &&
          _tutorialStateLoaded &&
          !_hasSeenClearTutorial &&
          !_showTutorial) {
        _showClearTutorial = true;
        _hasSeenClearTutorial = true;
        _inactivityTimer?.cancel();
        _hintPulseCtrl.stop();
        _hintCurrentCard = false;
        _hintedPair.clear();

        final playerId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
        SharedPreferences.getInstance().then(
          (p) => p.setBool('hasSeenClearTutorialV2_$playerId', true),
        );
      }

      setState(() {});
      _checkEndState();
      _restartHintTimer();
    } else if (game.phase == Phase.clear) {
      if (_isAnimatingClear) return;
      setState(() {
        game.toggleSelectForClear(i);
        if (game.selectedForClear.length == 2) {
          if (game.canClearSelection) {
            _doClear();
          } else {
            if (game.isSuddenDeath) {
              final errorIdxs = game.selectedForClear.toList();
              game.selectedForClear.clear();
              Future.microtask(() => _doubleFlashAndGameOver(errorIdxs));
            } else {
              _flashError(game.selectedForClear.toList());
              game.selectedForClear.clear();
            }
          }
        }
      });
      _restartHintTimer();
    }
  }

  void _doClear() {
    if (!game.canClearSelection) return;
    final indices = game.selectedForClear.toList()..sort();
    final cards = [for (final i in indices) game.cells[i]!];
    final previousPhase = game.phase;

    _isAnimatingClear = true;
    _animateClearToPile(indices, cards, () {
      if (!mounted) return;
      _pushUndo();
      setState(() {
        game.performClear();
        _isAnimatingClear = false;
        _clearedAtLeastOnePairThisPhase = true;
      });
      DailyGoalService.addProgress(GoalType.clearPair, 1);
      HapticService.success();
      _playPop();
      _maybeTriggerPhaseTransitionFeedback(previousPhase, game.phase);
      _checkEndState();
      _restartHintTimer();
    });
  }

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

  void _showRules() {
    final isWide = MediaQuery.of(context).size.width > 700;
    final content = Directionality(
      textDirection:
          _lang == AppLang.he ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        color: kBurgundyLight,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _l.rulesTitle,
              style: const TextStyle(
                  color: kGold,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1),
            ),
            const SizedBox(height: 16),
            Text(
              _l.rulesBody,
              style: const TextStyle(
                  color: kGoldLight, fontSize: 14, height: 1.7),
            ),
            const SizedBox(height: 24),
            Center(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: kGold,
                  side: const BorderSide(color: kGold),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  _inactivityTimer?.cancel();
                  _hintPulseCtrl.stop();
                  _hintCurrentCard = false;
                  _hintedPair.clear();
                  setState(() {
                    if (game.phase == Phase.clear) {
                      _showClearTutorial = true;
                    } else {
                      _showTutorial = true;
                    }
                  });
                },
                icon: const Icon(Icons.help_outline),
                label: Text(
                  _l.btnReplayTutorial,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (isWide) {
      showDialog(
        context: context,
        builder: (_) => Dialog(child: SizedBox(width: 460, child: content)),
      );
    } else {
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        backgroundColor: kBurgundyLight,
        builder: (_) => content,
      );
    }
  }

  void _showDailyGoal() {
    final goal = DailyGoalService.current;
    if (goal == null) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kBurgundyLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: kGold, width: 1.5),
        ),
        title: Row(
          children: [
            Icon(
              goal.isCompleted ? Icons.emoji_events : Icons.track_changes,
              color: goal.isCompleted ? Colors.greenAccent : kGold,
            ),
            const SizedBox(width: 10),
            const Text(
              'Daily Goal',
              style: TextStyle(color: kGold, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              goal.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              goal.description,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: goal.progress,
                minHeight: 12,
                backgroundColor: kBurgundy,
                color: goal.isCompleted ? Colors.greenAccent : kGoldLight,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                goal.isCompleted ? 'Completed! ✓' : goal.progressLabel,
                style: TextStyle(
                  color:
                      goal.isCompleted ? Colors.greenAccent : kGoldLight,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close',
                style: TextStyle(color: kGoldDark)),
          ),
        ],
      ),
    );
  }

  void _showThemeGallery() {
    showDialog(
      context: context,
      builder: (_) => _CosmeticsShopDialog(
        onChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Future<void> _shareOnWhatsApp(int totalScore) async {
    final diff = _difficultyLabel;
    final int elapsedSecs = (game.endTime ?? DateTime.now())
        .difference(game.startTime)
        .inSeconds;
    final m = (elapsedSecs ~/ 60).toString().padLeft(2, '0');
    final s = (elapsedSecs % 60).toString().padLeft(2, '0');
    final time = '$m:$s';
    final text =
        'I just won Royal Frame on $diff in $time with a score of $totalScore! '
        'Can you beat me? 👑 https://play.google.com/store/apps/details?id=com.royalframe.app';
    final encoded = Uri.encodeComponent(text);
    final uri = Uri.parse('https://wa.me/?text=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Card widget helpers ───────────────────────────────────────────────────

  static const double kCardW = 72.0;
  static const double kCardH = 100.0;

  int _deckStackLayers(int remaining) {
    if (remaining <= 0) return 0;
    if (remaining > 30) return 4;
    if (remaining >= 15) return 3;
    return 2;
  }

  Widget _playingCardFallback(CardModel c,
      {required double w, required double h}) {
    final faceColor = isRed(c.suit) ? kCardRed : kCardBlack;
    final large = w > kCardW;
    return Container(
      width: w,
      height: h,
      color: kCardWhite,
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
            style:
                TextStyle(fontSize: large ? 36.0 : 28.0, color: faceColor),
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
    final w = large ? 90.0 : kCardW;
    final h = large ? 126.0 : kCardH;
    final isRoyal = c.isK || c.isQ || c.isJ;
    final localImageName = '${c.assetRankName}_of_${c.assetSuitName}.png';

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: dimmed ? 0.45 : 1,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isRoyal ? kGold : kGoldDark,
            width: isRoyal ? 2.0 : 1.6,
          ),
          boxShadow: isRoyal
              ? [
                  BoxShadow(
                    color: kRoyalGlowColor.withOpacity(0.3),
                    blurRadius: 6,
                  )
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.asset(
            'assets/images/$localImageName',
            fit: BoxFit.fill,
            errorBuilder: (_, __, ___) => Container(
              color: kCardWhite,
              child: Center(
                child: Text(
                  c.label,
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

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

  Widget _cardBackImage() {
    final asset = XpService.equippedCardBackAsset;
    final fallback = XpService.equippedCardBackFallback;
    return Image.asset(
      asset,
      width: kCardW,
      height: kCardH,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => ColoredBox(color: fallback),
    );
  }

  Widget _cardBackLayer({int depth = 0}) {
    return Container(
      width: kCardW,
      height: kCardH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: depth == 0
              ? kGold.withOpacity(0.9)
              : kGoldDark.withOpacity(0.75),
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
      width: kCardW,
      height: kCardH,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: kGoldDark.withOpacity(0.55), width: 1.6),
      ),
    );
  }

  Widget _clearPileSlot() {
    final top = game.clearPileTop;
    return KeyedSubtree(
      key: _clearPileKey,
      child: top == null
          ? Container(
              width: kCardW,
              height: kCardH,
              decoration: BoxDecoration(
                color: kSlotFrame,
                border: Border.all(color: kSlotFrameBorder, width: 2.2),
                borderRadius: BorderRadius.circular(7),
              ),
            )
          : Container(
              width: kCardW,
              height: kCardH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kGoldDark, width: 1.6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _gridCardFace(top),
              ),
            ),
    );
  }

  Widget _stackedDeckWidget() {
    final remaining = game.cardsRemainingDisplay;
    return SizedBox(
      width: kDeckStackW,
      height: kDeckStackH,
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
                    bottom: i * kDeckLayerOffsetY,
                    left: i * kDeckLayerOffsetX,
                    child: _cardBackLayer(depth: i),
                  ),
              ],
            ),
    );
  }

  Widget _emptyCardWidget({required String label}) {
    return Container(
      width: 72,
      height: 100,
      decoration: BoxDecoration(
        color: kBurgundyLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kGoldDark, width: 1.2),
      ),
      child: Center(
        child: Text(label,
            style: const TextStyle(
                color: kGold, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _pileWithTag({
    required Widget base,
    required String tagText,
    Alignment baseAlign = Alignment.bottomLeft,
  }) {
    return SizedBox(
      width: kDeckStackW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DeckTag(text: tagText),
          const SizedBox(height: 4),
          SizedBox(
            width: kDeckStackW,
            height: kDeckStackH,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Align(alignment: baseAlign, child: base),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deckRow() {
    final curr = game.current;
    final peek = game.peekCard;
    final deckNotEmpty = game.drawPile.isNotEmpty;

    final Widget clearPile = _pileWithTag(
      tagText: _l.labelClearPile,
      baseAlign: Alignment.bottomCenter,
      base: _clearPileSlot(),
    );

    var deckTagText =
        '${_l.labelDeck}  ${game.cardsRemainingDisplay}';
    if (peek != null) {
      deckTagText +=
          '\n${_l.peekNext('${peek.label}${suitSymbol(peek.suit)}')}';
    }
    final Widget deckPile = _pileWithTag(
      tagText: deckTagText,
      baseAlign: Alignment.bottomCenter,
      base: _stackedDeckWidget(),
    );

    final Widget thirdBase;
    final String thirdTag;

    if (curr != null) {
      thirdTag = _l.labelCurrent;

      Widget currentCardChild = _playingCard(curr);

      if (_hintCurrentCard) {
        currentCardChild = AnimatedBuilder(
          animation: _hintPulseCtrl,
          builder: (context, child) => Opacity(
            opacity: 0.3 + (_hintPulseCtrl.value * 0.7),
            child: child,
          ),
          child: currentCardChild,
        );
      }

      thirdBase = Draggable<CardModel>(
        data: curr,
        feedback:
            Opacity(opacity: 0.9, child: _playingCard(curr, large: true)),
        childWhenDragging: _playingCard(curr, dimmed: true),
        onDragStarted: () {
          if (!_showTutorial) setState(() => _draggingCard = curr);
        },
        onDragEnd: (_) => setState(() => _draggingCard = null),
        onDraggableCanceled: (_, __) =>
            setState(() => _draggingCard = null),
        child: currentCardChild,
      );
    } else if (deckNotEmpty) {
      thirdTag = _l.labelHidden;
      thirdBase = _cardBackWidget();
    } else {
      thirdTag = _l.labelEmpty;
      thirdBase = _emptyDeckSlot();
    }

    final Widget thirdPile = _pileWithTag(
      tagText: thirdTag,
      baseAlign: Alignment.bottomCenter,
      base: thirdBase,
    );

    return KeyedSubtree(
      key: _deckRowKey,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          clearPile,
          const SizedBox(width: 8),
          deckPile,
          const SizedBox(width: 8),
          thirdPile,
        ],
      ),
    );
  }

  TextStyle _labelStyle({bool dimmed = false}) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: dimmed ? Colors.white38 : kGoldLight,
        fontStyle: dimmed ? FontStyle.italic : FontStyle.normal,
        letterSpacing: 0.4,
      );

  Widget _buildGrid(
    Set<int> dragHighlights, {
    required double gridW,
    required double gridH,
  }) {
    const double pad  = 6.0;
    const double gap  = 4.0;
    const int    cols = 4;
    const int    rows = 4;

    final double cellW =
        (gridW - pad * 2 - gap * (cols - 1)) / cols;
    final double cellH =
        (gridH - pad * 2 - gap * (rows - 1)) / rows;
    final double ratio = cellW / cellH;

    return KeyedSubtree(
      key: _gridKey,
      child: Container(
        width: gridW,
        height: gridH,
        decoration: BoxDecoration(
          color: kTableGreen,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 16,
              offset: const Offset(0, 4),
            )
          ],
        ),
        padding: const EdgeInsets.all(pad),
        child: GridView.count(
          crossAxisCount: cols,
          childAspectRatio: ratio,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          children: List.generate(16, (i) {
            final type      = game.layout[i];
            final card      = game.cells[i];
            final blocked   = game.isBlocked[i];
            final selected  = game.selectedForClear.contains(i);
            final isFrame   = type != SlotType.innerDump;
            final isDragTarget = dragHighlights.contains(i);

            final bool correctRoyal = card != null &&
                !blocked &&
                ((card.isK && type == SlotType.kingCorner) ||
                    (card.isQ && type == SlotType.queenEdge) ||
                    (card.isJ && type == SlotType.jackEdge));

            Color bgColor;
            Color borderColor;
            double borderWidth;
            List<BoxShadow>? shadows;
            Gradient? gradient;
            String text = '';

            if (card == null) {
              if (isDragTarget) {
                bgColor     = kDragTarget;
                borderColor = kDragTargetBorder;
                borderWidth = isFrame ? 3.0 : 2.4;
                text        = _l.slotLabel(type);
              } else if (isFrame) {
                bgColor     = kSlotFrame;
                borderColor = kSlotFrameBorder;
                borderWidth = 2.2;
                text        = _l.slotLabel(type);
              } else {
                bgColor     = kTableGreenMid.withOpacity(0.5);
                borderColor = kSlotDumpBorder;
                borderWidth = 1.0;
              }
              if (_errorHighlights.contains(i)) {
                bgColor     = kBlockedBg;
                borderColor = Colors.redAccent;
                borderWidth = 3.5;
              }
            } else {
              final isNumber = card.isNumOrAce;

              if (correctRoyal) {
                bgColor     = kRoyalGoldBg;
                borderColor = kRoyalGoldBorder;
                borderWidth = 2.8;
                gradient = const LinearGradient(
                  colors: [
                    Color(0xFF4A3200),
                    Color(0xFF2A1800),
                    Color(0xFF4A3200),
                  ],
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
              } else if (isNumber) {
                bgColor     = blocked ? kBlockedBg : kBurgundyLight;
                borderColor = kNumberSilverBorder;
                borderWidth = 2.2;
                shadows     = null;
              } else if (blocked) {
                bgColor     = kBlockedBg;
                borderColor = kBlockedBorder;
                borderWidth = isFrame ? 2.2 : 1.4;
                shadows     = null;
              } else {
                bgColor     = kBurgundyLight;
                borderColor = isFrame ? kSlotFrameBorder : kGoldDark;
                borderWidth = isFrame ? 2.2 : 1.4;
                shadows     = null;
              }

              if (_moveMode &&
                  _moveFromIndex == i &&
                  game.phase != Phase.clear) {
                borderColor = kGoldLight;
                borderWidth = 3.5;
              }

              if (game.phase == Phase.clear && selected) {
                borderColor = kSelectionHighlight;
                borderWidth = 3.5;
              }

              if (_errorHighlights.contains(i)) {
                borderColor = Colors.redAccent;
                borderWidth = 3.5;
              }
            }

            final isHinted = _hintedPair.contains(i);

            Widget cellContent = card == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isDragTarget
                                  ? kDragTargetBorder.withOpacity(0.95)
                                  : kSlotFrameBorder.withOpacity(0.85),
                              height: 1.1,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  )
                : _playingCard(card);

            if (isHinted) {
              cellContent = AnimatedBuilder(
                animation: _hintPulseCtrl,
                builder: (context, child) => Opacity(
                  opacity: 0.3 + (_hintPulseCtrl.value * 0.7),
                  child: child,
                ),
                child: cellContent,
              );
            }

            final bool isNumberCard = card != null && card.isNumOrAce;
            final bool shouldDim = game.phase == Phase.clear &&
                !isNumberCard &&
                !_showClearTutorial;

            final cellWidget = KeyedSubtree(
              key: _cellKeys[i],
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeInOut,
                opacity: shouldDim ? 0.35 : 1.0,
                child: InkWell(
                  onTap: () => _onTapCell(i),
                  borderRadius: BorderRadius.circular(7),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    decoration: BoxDecoration(
                      color: gradient == null ? bgColor : null,
                      gradient: gradient,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                          color: borderColor, width: borderWidth),
                      boxShadow: shadows,
                    ),
                    child: cellContent,
                  ),
                ),
              ),
            );

            // FIX 2: drag-and-drop also triggers sudden death on illegal placement
            return DragTarget<CardModel>(
              onWillAcceptWithDetails: (_) => true,
              onAccept: (_) {
                if (_showTutorial || _showClearTutorial) return;
                _unlockAudio();
                if (game.phase != Phase.fill || game.current == null) return;

                _pushUndo();
                final previousPhase = game.phase;
                final ok = game.tryPlaceAt(i, godMode: _godMode);

                if (ok) {
                  setState(() {});
                  HapticService.light();
                  _playPlace();
                  _maybeTriggerPhaseTransitionFeedback(
                      previousPhase, game.phase);
                  final placedCard = game.cells[i];
                  if (placedCard != null &&
                      (placedCard.isK ||
                          placedCard.isQ ||
                          placedCard.isJ)) {
                    DailyGoalService.addProgress(GoalType.placeRoyal, 1);
                  }
                  if (placedCard != null && placedCard.isQ) {
                    final queensOnBoard = game.cells
                        .whereType<CardModel>()
                        .where((c) => c.isQ)
                        .length;
                    if (queensOnBoard == 4) BadgeService.unlockQueenBadge();
                  }
                  _checkEndState();
                } else {
                  _undo.removeLast();
                  if (game.isSuddenDeath) {
                    _doubleFlashAndGameOver([i]);
                  } else {
                    _flashError([i]);
                  }
                }

                _restartHintTimer();
              },
              builder: (_, __, ___) => cellWidget,
            );
          }),
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Color get _difficultyColor => switch (_difficulty) {
        GameDifficulty.medium  => const Color(0xFF4CAF50),
        GameDifficulty.hard    => kGold,
        GameDifficulty.extreme => const Color(0xFFFF5252),
      };

  String get _difficultyLabel => switch (_difficulty) {
        GameDifficulty.medium  => 'MEDIUM',
        GameDifficulty.hard    => 'HARD',
        GameDifficulty.extreme => 'EXTREME',
      };

  @override
  Widget build(BuildContext context) {
    final dragHighlights = _computeDragHighlights();
    const double deckRowH = 150.0;
    const double innerGap = 6.0;

    final int elapsedSecs = (game.endTime ?? DateTime.now())
        .difference(game.startTime)
        .inSeconds;

    final bool isExtreme = game.difficulty == GameDifficulty.extreme;
    final int displaySecs =
        isExtreme ? max(0, _extremeSeconds - elapsedSecs) : elapsedSecs;
    final bool isCountdown = isExtreme;
    final bool timerCritical = isExtreme && displaySecs <= 30;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _pauseGameTimer();
        await _stopAllAudioNow();
        if (mounted) Navigator.of(context).pop(game);
      },
      child: Directionality(
        textDirection:
            _lang == AppLang.he ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          backgroundColor: XpService.equippedBoardColor,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: XpService.equippedBoardColorLight,
            titleSpacing: 6,
            title: Row(
              children: [
                // Title + difficulty badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichText(
                      text: const TextSpan(
                        children: [
                          TextSpan(
                            text: 'Royal ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 1,
                              color: kGoldLight,
                              height: 1.0,
                            ),
                          ),
                          TextSpan(
                            text: 'Frame',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              color: kGold,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: _difficultyColor.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _difficultyColor.withOpacity(0.55),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        _difficultyLabel,
                        style: TextStyle(
                          color: _difficultyColor,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),

                // Score + timer bar
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: kGoldDark.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.emoji_events,
                            size: 14, color: kGold),
                        const SizedBox(width: 4),
                        Text(
                          '${game.score}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          isCountdown
                              ? Icons.timer_outlined
                              : Icons.timer,
                          size: 14,
                          color: timerCritical
                              ? Colors.redAccent
                              : kGoldLight,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(displaySecs),
                          style: TextStyle(
                            color: timerCritical
                                ? Colors.redAccent
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // Action buttons — FittedBox scales down on narrow screens
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildCompactIcon(Icons.home, kGold, () {
                      if (game.phase == Phase.winner ||
                          game.phase == Phase.gameOver) {
                        Navigator.pop(context, game);
                      } else {
                        showDialog(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            backgroundColor: kBurgundyLight,
                            title: Text(
                              _l.dialogHomeTitle,
                              style:
                                  const TextStyle(color: kGold),
                            ),
                            content: Text(
                              _l.dialogHomeBody,
                              style: const TextStyle(
                                  color: Colors.white),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext),
                                child: Text(
                                  _l.btnNo,
                                  style: const TextStyle(
                                      color: kGoldDark),
                                ),
                              ),
                              FilledButton(
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  Navigator.pop(context, game);
                                },
                                child: Text(_l.btnYes),
                              ),
                            ],
                          ),
                        );
                      }
                    }),
                    const SizedBox(width: 2),
                    _buildCompactIcon(
                      Icons.undo,
                      _undo.isNotEmpty ? kGold : kGoldDark,
                      _undo.isNotEmpty ? _undoAction : null,
                    ),
                    const SizedBox(width: 2),
                    _buildCompactIcon(
                        Icons.refresh, kGold, _openDifficultyPicker),
                    const SizedBox(width: 2),

                    _buildCompactIcon(
                      DailyGoalService.current?.isCompleted == true
                          ? Icons.check_circle
                          : Icons.flag,
                      DailyGoalService.current?.isCompleted == true
                          ? Colors.greenAccent
                          : kGold,
                      _showDailyGoal,
                    ),
                    const SizedBox(width: 2),

                    SizedBox(
                      width: 32,
                      child: PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: kGold,
                          size: 24,
                        ),
                        padding: EdgeInsets.zero,
                        color: kBurgundyLight,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                              color: kGoldDark.withOpacity(0.5)),
                        ),
                        onSelected: (value) {
                          if (value == 'rules')
                            _showRules();
                          else if (value == 'difficulty')
                            _showDifficultyPicker();
                          else if (value == 'cosmetics')
                            _showThemeGallery();
                          else if (value == 'lang') {
                            final newLang = _lang == AppLang.he ? AppLang.en : AppLang.he;
                            setState(() => _lang = newLang);
                            L.saveLang(newLang);
                          }
                          else if (value == 'mute')
                            _toggleMute();
                          else if (value == 'haptic')
                            _toggleHaptic();
                          else if (value == 'optional_clearing')
                            _toggleOptionalClearing();
                          else if (value == 'debug')
                            setState(() =>
                                _showDebugTools = !_showDebugTools);
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'rules',
                            child: Row(children: [
                              const Icon(Icons.menu_book_rounded,
                                  color: kGold, size: 20),
                              const SizedBox(width: 12),
                              Text(_l.tooltipRules,
                                  style: const TextStyle(
                                      color: kGoldLight, fontSize: 14)),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'difficulty',
                            child: Row(children: [
                              const Icon(Icons.speed,
                                  color: kGold, size: 20),
                              const SizedBox(width: 12),
                              Text(
                                'Difficulty: $_difficultyLabel',
                                style: const TextStyle(
                                    color: kGoldLight, fontSize: 14),
                              ),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'cosmetics',
                            child: Row(children: const [
                              Icon(Icons.style,
                                  color: kGold, size: 20),
                              SizedBox(width: 12),
                              Text('Themes',
                                  style: TextStyle(
                                      color: kGoldLight, fontSize: 14)),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'lang',
                            child: Row(children: [
                              const Icon(Icons.language,
                                  color: kGold, size: 20),
                              const SizedBox(width: 12),
                              Text(_l.langToggleLabel,
                                  style: const TextStyle(
                                      color: kGoldLight, fontSize: 14)),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'mute',
                            child: Row(children: [
                              Icon(
                                  _isMuted
                                      ? Icons.volume_off
                                      : Icons.volume_up,
                                  color: kGold,
                                  size: 20),
                              const SizedBox(width: 12),
                              Text(_isMuted ? 'Unmute' : 'Mute',
                                  style: const TextStyle(
                                      color: kGoldLight, fontSize: 14)),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'haptic',
                            child: Row(children: [
                              Icon(
                                  HapticService.isEnabled
                                      ? Icons.vibration
                                      : Icons.phonelink_erase,
                                  color: kGold,
                                  size: 20),
                              const SizedBox(width: 12),
                              Text(
                                  HapticService.isEnabled
                                      ? 'Vibration: On'
                                      : 'Vibration: Off',
                                  style: const TextStyle(
                                      color: kGoldLight, fontSize: 14)),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'optional_clearing',
                            child: Row(children: [
                              Icon(
                                _optionalClearing
                                    ? Icons.skip_next
                                    : Icons.skip_next_outlined,
                                color: kGold,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _optionalClearing
                                    ? (_lang == AppLang.he
                                        ? 'פינוי חופשי: פועל'
                                        : 'Free Clearing: On')
                                    : (_lang == AppLang.he
                                        ? 'פינוי חופשי: כבוי'
                                        : 'Free Clearing: Off'),
                                style: const TextStyle(
                                    color: kGoldLight, fontSize: 14),
                              ),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'debug',
                            child: Row(children: [
                              Icon(
                                  _showDebugTools
                                      ? Icons.settings
                                      : Icons.settings_outlined,
                                  color: kGold,
                                  size: 20),
                              const SizedBox(width: 12),
                              Text(
                                  _showDebugTools
                                      ? _l.menuDebugHide
                                      : _l.menuDebugShow,
                                  style: const TextStyle(
                                      color: kGoldLight, fontSize: 14)),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ],
                  ),  // Row
                ),    // FittedBox
              ],
            ),
          ),

          body: Listener(
            onPointerDown: (_) => _restartHintTimer(),
            behavior: HitTestBehavior.translucent,
            child: SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      if (_moveMode)
                        Container(
                          color: kGoldDark.withOpacity(0.25),
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 12),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.open_with_rounded,
                                  size: 14, color: kGoldLight),
                              const SizedBox(width: 6),
                              Text(
                                _moveFromIndex == null
                                    ? _l.movePick
                                    : _l.moveDrop,
                                style: const TextStyle(
                                  color: kGoldLight,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_optionalClearing &&
                          game.phase == Phase.clear &&
                          game.hasAnyPairFor11 &&
                          _clearedAtLeastOnePairThisPhase &&
                          !_isAnimatingClear &&
                          !_showClearTutorial)
                        Container(
                          color: kBurgundy.withOpacity(0.85),
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 12),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Text(
                                _lang == AppLang.he
                                    ? 'פנה זוגות של 11'
                                    : 'Clear pairs summing to 11',
                                style: const TextStyle(
                                  color: kGoldLight,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () {
                                  _pushUndo();
                                  final ok = game.forceResumeFill();
                                  if (ok) {
                                    setState(() {});
                                    _maybeTriggerPhaseTransitionFeedback(
                                        Phase.clear, game.phase);
                                    _checkEndState();
                                    _restartHintTimer();
                                  } else {
                                    _undo.removeLast();
                                  }
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 3),
                                  decoration: BoxDecoration(
                                    color: kGoldDark.withOpacity(0.3),
                                    borderRadius:
                                        BorderRadius.circular(6),
                                    border: Border.all(
                                        color: kGoldDark, width: 1),
                                  ),
                                  child: Text(
                                    _lang == AppLang.he ? 'דלג' : 'Skip',
                                    style: const TextStyle(
                                      color: kGold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeInOut,
                        child: _showDebugTools
                            ? _buildDebugPanel()
                            : const SizedBox.shrink(),
                      ),

                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(
                              left: 8,
                              right: 8,
                              top: 4,
                              bottom: 28),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final double totalH =
                                  constraints.maxHeight;
                              final double totalW =
                                  constraints.maxWidth;

                              final double gridH =
                                  totalH - deckRowH - innerGap;
                              final double gridW =
                                  totalW.clamp(0.0, gridH * 1.4);

                              return Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  AnimatedOpacity(
                                    duration: const Duration(
                                        milliseconds: 450),
                                    curve: Curves.easeInOut,
                                    opacity: (game.phase ==
                                                Phase.clear &&
                                            !_showClearTutorial)
                                        ? 0.35
                                        : 1.0,
                                    child: SizedBox(
                                      height: deckRowH,
                                      child: Center(
                                          child: _deckRow()),
                                    ),
                                  ),
                                  SizedBox(height: innerGap),
                                  Center(
                                    child: _buildGrid(
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
                    ],
                  ),

                  if (game.phase == Phase.winner)
                    _buildWinnerOverlay(),

                  if (game.phase == Phase.gameOver &&
                      _showGameOverOverlay)
                    _buildGameOverOverlay(),

                  // Duel HUD — live opponent score + result banner
                  if (_duelSession != null)
                    _buildDuelHud(),

                  if (_showTutorial)
                    TutorialOverlay(
                      lang: _lang,
                      deckRowKey: _deckRowKey,
                      gridKey: _gridKey,
                      cellKeys: _cellKeys,
                      isClearPhase: false,
                      onFinish: ({bool skipped = false}) {
                        setState(() => _showTutorial = false);
                        _restartHintTimer();
                      },
                    ),

                  if (_showClearTutorial)
                    TutorialOverlay(
                      lang: _lang,
                      deckRowKey: _deckRowKey,
                      gridKey: _gridKey,
                      cellKeys: _cellKeys,
                      isClearPhase: true,
                      onFinish: ({bool skipped = false}) {
                        setState(() => _showClearTutorial = false);
                        _restartHintTimer();
                      },
                    ),

                  // Phase-transition pulse overlay
                  if (_showPhasePulse)
                    IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _phasePulseCtrl,
                        builder: (context, _) {
                          final t = _phasePulseCtrl.value;
                          final opacity = (t < 0.4
                                  ? (t / 0.4)
                                  : (1.0 - (t - 0.4) / 0.6))
                              .clamp(0.0, 1.0);
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Opacity(
                                opacity: opacity * 0.28,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      center: Alignment.center,
                                      radius: 0.85,
                                      colors: [
                                        kRoyalGoldBorder
                                            .withOpacity(0.0),
                                        kRoyalGoldBorder
                                            .withOpacity(0.7),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Opacity(
                                opacity: opacity,
                                child: Center(
                                  child: Text(
                                    _phaseLabel,
                                    style: const TextStyle(
                                      color: kGold,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 4,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black,
                                          blurRadius: 12,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                  Align(
                    alignment: Alignment.topCenter,
                    child: ConfettiWidget(
                      confettiController: _confettiCtrl,
                      blastDirectionality:
                          BlastDirectionality.explosive,
                      numberOfParticles: 40,
                      gravity: 0.25,
                      emissionFrequency: 0.05,
                      colors: const [
                        kGold,
                        kGoldLight,
                        Colors.white,
                        Color(0xFFE91E63),
                        Color(0xFF2196F3),
                      ],
                      shouldLoop: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDebugPanel() {
    return Container(
      color: kBurgundyLight.withOpacity(0.92),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
                child: _miniCard(
                    _l.dbgPhase, game.phase.name)),
            Expanded(
                child: _miniCard(
                    _l.dbgCurrent,
                    game.phase == Phase.clear
                        ? '—'
                        : (game.current?.label ?? '—'))),
            Expanded(
                child: _miniCard(_l.dbgDeck,
                    game.cardsRemainingDisplay.toString())),
            Expanded(
                child: _miniCard(_l.dbgRoyals,
                    '${game.royalsPlacedCorrect}/${game.totalRoyalSlots}')),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: game.royalsProgress.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: kBurgundy,
                color: kGold,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  _l.dbgGodMode,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _godMode ? kGoldLight : Colors.white38,
                  ),
                ),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
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
        color: kBurgundy,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Column(children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 10,
                    color: kGoldDark,
                    fontWeight: FontWeight.w600)),
            Text(value,
                style: const TextStyle(
                    fontSize: 12, color: kGoldLight)),
          ]),
        ),
      );

  Widget _buildDuelHud() {
    final session = _duelSession;
    if (session == null) return const SizedBox.shrink();

    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isHost = session.hostUid == myUid;
    final myScore = game.score;
    final opponentName = isHost
        ? (session.guestName ?? 'Opponent')
        : session.hostName;

    // Result banner when duel is finished
    if (session.isFinished) {
      final iWon = session.winnerId == myUid;
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Container(
            color: iWon
                ? kGold.withOpacity(0.88)
                : Colors.redAccent.withOpacity(0.82),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  iWon ? '  You Win the Duel!' : '  Opponent Wins the Duel',
                  style: TextStyle(
                    color: iWon ? Colors.black : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Live score HUD strip at the bottom
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withOpacity(0.65),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              // My score
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOU',
                      style: TextStyle(
                        color: kGoldLight,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      '$myScore',
                      style: const TextStyle(
                        color: kGold,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              // VS divider
              Container(
                width: 1,
                height: 32,
                color: kGoldDark.withOpacity(0.6),
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              // Opponent score
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      opponentName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      '$_opponentScore',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWinnerOverlay() {
    if (!_statsUpdatedThisGame) {
      _statsUpdatedThisGame = true;
      DbService().updatePlayerStats(game.score, true);
      DailyGoalService.addProgress(GoalType.scorePoints, game.score);
    }

    final int baseScore = game.score;
    const int winBonus = 1000;
    final int drawnWhenFilled =
        game.cardsDrawnWhenFrameFilled ?? 52;
    final int effBonus =
        max(0, (52 - drawnWhenFilled) * 50);
    final int seconds = (game.endTime ?? DateTime.now())
        .difference(game.startTime)
        .inSeconds;
    final int speedBonus = max(0, 5000 - (seconds * 5));
    final int rawTotal =
        baseScore + winBonus + effBonus + speedBonus;

    final double multiplier = switch (_difficulty) {
      GameDifficulty.medium  => 0.5,
      GameDifficulty.hard    => 1.0,
      GameDifficulty.extreme => 2.0,
    };
    final int totalScore = (rawTotal * multiplier).round();

    final int xpGained = switch (_difficulty) {
      GameDifficulty.medium  => 250,
      GameDifficulty.hard    => 500,
      GameDifficulty.extreme => 1000,
    };

    const textShadow = [
      Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 2)),
    ];

    return Container(
      color: Colors.black.withOpacity(0.72),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding:
              const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
          decoration: BoxDecoration(
            color: kBurgundyLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kGold, width: 2.5),
            boxShadow: [
              BoxShadow(
                  color: kGold.withOpacity(0.35),
                  blurRadius: 40,
                  spreadRadius: 4)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('👑', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text(
                _l.winTitle,
                style: const TextStyle(
                  color: kGold,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  shadows: textShadow,
                ),
              ),
              const SizedBox(height: 12),

              // Score breakdown
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: kGoldDark.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    _scoreRow(_l.winBaseScore, '+$baseScore'),
                    _scoreRow(_l.effBonus, '+$effBonus'),
                    _scoreRow(_l.speedBonus, '+$speedBonus'),
                    _scoreRow(_l.winBonus, '+$winBonus',
                        isGold: true),
                    if (multiplier != 1.0)
                      _scoreRow(
                        'Difficulty ×${multiplier.toStringAsFixed(1)}',
                        '',
                      ),
                    const Divider(color: kGoldDark, height: 24),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _l.totalScore,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$totalScore',
                          style: const TextStyle(
                              color: kGold,
                              fontSize: 20,
                              fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // XP badge
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: kGoldDark.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: kGold, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '+$xpGained XP',
                      style: const TextStyle(
                        color: kGold,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF25D366),
                  side: const BorderSide(color: Color(0xFF25D366), width: 1.5),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                ),
                onPressed: () => _shareOnWhatsApp(totalScore),
                icon: const Icon(Icons.share, size: 18),
                label: const Text(
                  'Share on WhatsApp',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 10),

              FilledButton.icon(
                onPressed: _restartCurrentGame,
                icon: const Icon(Icons.refresh),
                label: Text(_l.winBtn),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactIcon(
      IconData icon, Color color, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }

  Widget _scoreRow(String title, String value,
      {bool isGold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              color: isGold ? kGold : kGoldLight,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    if (!_statsUpdatedThisGame) {
      _statsUpdatedThisGame = true;
      DbService().updatePlayerStats(game.score, false);
      DailyGoalService.addProgress(GoalType.scorePoints, game.score);
    }
    final deckLeft = game.cardsRemainingDisplay;
    const textShadow = [
      Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 2)),
    ];

    final int xpGained = switch (_difficulty) {
      GameDifficulty.medium  => 25,
      GameDifficulty.hard    => 50,
      GameDifficulty.extreme => 100,
    };

    return Container(
      color: Colors.black.withOpacity(0.40),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding:
              const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBlockedBorder, width: 1.8),
            boxShadow: [
              BoxShadow(
                color: kBlockedBorder.withOpacity(0.28),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                game.isSuddenDeath ? '💣' : '💀',
                style: const TextStyle(fontSize: 48),
              ),
              const SizedBox(height: 10),
              Text(
                _l.lossTitle,
                style: const TextStyle(
                  color: kBlockedBorder,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  shadows: textShadow,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                game.isSuddenDeath
                    ? 'One wrong move — and that\'s it.'
                    : _l.lossSub,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    shadows: textShadow),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: kBurgundy.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: kGoldDark.withOpacity(0.5), width: 1),
                ),
                child: Text(
                  _l.lossCardsLeft(deckLeft),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: kGoldLight,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      shadows: textShadow),
                ),
              ),
              const SizedBox(height: 12),

              // XP consolation badge
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: kGoldDark.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_outline,
                        color: kGoldLight, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '+$xpGained XP  — keep going!',
                      style: const TextStyle(
                        color: kGoldLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: kBlockedBorder),
                onPressed: _restartCurrentGame,
                icon: const Icon(Icons.refresh),
                label: Text(_l.lossBtn),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIFFICULTY PICKER DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _DifficultyPickerDialog extends StatefulWidget {
  final GameDifficulty current;
  final void Function(GameDifficulty) onSelected;

  const _DifficultyPickerDialog({
    required this.current,
    required this.onSelected,
  });

  @override
  State<_DifficultyPickerDialog> createState() =>
      _DifficultyPickerDialogState();
}

class _DifficultyPickerDialogState
    extends State<_DifficultyPickerDialog> {
  late GameDifficulty _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  static const _data = [
    (
      diff: GameDifficulty.medium,
      emoji: '☀️',
      name: 'Medium',
      subtitle: 'No Kings — 8 dump slots.\nScore ×0.5',
      accentLight: Color(0xFF4CAF50),
      accentDark: Color(0xFF2E7D32),
    ),
    (
      diff: GameDifficulty.hard,
      emoji: '⚔️',
      name: 'Hard',
      subtitle: 'Standard rules.\nScore ×1.0',
      accentLight: Color(0xFFD4AF37),
      accentDark: Color(0xFF9A7B1A),
    ),
    (
      diff: GameDifficulty.extreme,
      emoji: '💣',
      name: 'Extreme',
      subtitle: '3-min bomb + Sudden Death.\nScore ×2.0',
      accentLight: Color(0xFFFF5252),
      accentDark: Color(0xFFB71C1C),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 28, vertical: 60),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: const Color(0xFF3A0D15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kGold, width: 1.8),
          boxShadow: [
            BoxShadow(
              color: kGold.withOpacity(0.15),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
              decoration: BoxDecoration(
                color: kBurgundyLight.withOpacity(0.5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune, color: kGold, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Choose Difficulty',
                      style: TextStyle(
                        color: kGold,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close,
                          color: kGoldDark, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // Difficulty tiles
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                children: _data.map((d) {
                  final isChosen = _selected == d.diff;
                  return GestureDetector(
                    onTap: () =>
                        setState(() => _selected = d.diff),
                    child: AnimatedContainer(
                      duration:
                          const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isChosen
                            ? d.accentDark.withOpacity(0.35)
                            : Colors.black.withOpacity(0.25),
                        borderRadius:
                            BorderRadius.circular(14),
                        border: Border.all(
                          color: isChosen
                              ? d.accentLight
                              : Colors.white12,
                          width: isChosen ? 2.0 : 1.0,
                        ),
                        boxShadow: isChosen
                            ? [
                                BoxShadow(
                                  color: d.accentLight
                                      .withOpacity(0.22),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          Text(d.emoji,
                              style: const TextStyle(
                                  fontSize: 30)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.name,
                                  style: TextStyle(
                                    color: isChosen
                                        ? d.accentLight
                                        : Colors.white,
                                    fontSize: 16,
                                    fontWeight:
                                        FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  d.subtitle,
                                  style: TextStyle(
                                    color: isChosen
                                        ? d.accentLight
                                            .withOpacity(0.75)
                                        : Colors.white38,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AnimatedOpacity(
                            duration: const Duration(
                                milliseconds: 150),
                            opacity: isChosen ? 1.0 : 0.0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: d.accentLight,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check,
                                  color: Colors.black, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Confirm button
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  onPressed: () =>
                      widget.onSelected(_selected),
                  icon: const Icon(Icons.play_arrow_rounded,
                      size: 22),
                  label: const Text('START GAME'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COSMETICS SHOP DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _CosmeticsShopDialog extends StatefulWidget {
  final VoidCallback onChanged;
  const _CosmeticsShopDialog({required this.onChanged});

  @override
  State<_CosmeticsShopDialog> createState() =>
      _CosmeticsShopDialogState();
}

class _CosmeticsShopDialogState extends State<_CosmeticsShopDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: const Color(0xFF3A0D15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kGold, width: 1.8),
          boxShadow: [
            BoxShadow(
                color: kGold.withOpacity(0.15),
                blurRadius: 32,
                spreadRadius: 2),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding:
                  const EdgeInsets.fromLTRB(20, 18, 16, 0),
              decoration: BoxDecoration(
                color: kBurgundyLight.withOpacity(0.5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.style,
                          color: kGold, size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Theme Gallery',
                          style: TextStyle(
                            color: kGold,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      // XP / level display
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius:
                              BorderRadius.circular(12),
                          border: Border.all(
                              color:
                                  kGoldDark.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star,
                                color: kGold, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              'Lv.${XpService.playerLevel}  '
                              '${XpService.xpInCurrentLevel}/${XpService.xpPerLevel} XP',
                              style: const TextStyle(
                                  color: kGoldLight,
                                  fontSize: 11,
                                  fontWeight:
                                      FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius:
                            BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close,
                              color: kGoldDark, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TabBar(
                    controller: _tabCtrl,
                    indicatorColor: kGold,
                    labelColor: kGold,
                    unselectedLabelColor: kGoldDark,
                    tabs: const [
                      Tab(text: 'Card Backs'),
                      Tab(text: 'Board Colors'),
                    ],
                  ),
                ],
              ),
            ),

            // Tab content
            SizedBox(
              height: 320,
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildItemGrid(XpService.cardBacks,
                      isCardBack: true),
                  _buildItemGrid(XpService.boardColors,
                      isCardBack: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemGrid(List<CosmeticItem> items,
      {required bool isCardBack}) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.75,
      ),
      itemCount: items.length,
      itemBuilder: (context, idx) {
        final item = items[idx];
        final isUnlocked = isCardBack
            ? XpService.isBackUnlocked(item.id)
            : XpService.isColorUnlocked(item.id);
        final isEquipped = isCardBack
            ? XpService.equippedBackId == item.id
            : XpService.equippedColorId == item.id;

        return GestureDetector(
          onTap: isUnlocked
              ? () async {
                  if (isCardBack) {
                    await XpService.equipCardBack(item.id);
                  } else {
                    await XpService.equipBoardColor(item.id);
                  }
                  setState(() {});
                  widget.onChanged();
                }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isEquipped
                    ? kGold
                    : (isUnlocked
                        ? Colors.white24
                        : Colors.white10),
                width: isEquipped ? 2.5 : 1.2,
              ),
              boxShadow: isEquipped
                  ? [
                      BoxShadow(
                          color: kGold.withOpacity(0.3),
                          blurRadius: 8)
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Preview
                  isCardBack
                      ? (item.assetPath != null
                          ? Image.asset(
                              item.assetPath!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  ColoredBox(
                                color: item.fallbackColor ??
                                    const Color(0xFFB71C1C),
                              ),
                            )
                          : ColoredBox(
                              color: item.fallbackColor ??
                                  const Color(0xFFB71C1C)))
                      : ColoredBox(
                          color: item.boardColor ?? kBurgundy),

                  // Lock overlay
                  if (!isUnlocked)
                    Container(
                      color: Colors.black.withOpacity(0.65),
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock,
                              color: Colors.white54, size: 22),
                          const SizedBox(height: 4),
                          Text(
                            'Lv.${item.levelRequired}',
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),

                  // Equipped checkmark
                  if (isEquipped)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                            color: kGold,
                            shape: BoxShape.circle),
                        child: const Icon(Icons.check,
                            color: Colors.black, size: 12),
                      ),
                    ),

                  // Name label
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 4),
                      color: Colors.black.withOpacity(0.55),
                      child: Text(
                        item.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isEquipped
                              ? kGold
                              : Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UI HELPERS (Tags & Flying Cards)
// ─────────────────────────────────────────────────────────────────────────────
class DeckTag extends StatelessWidget {
  final String text;
  const DeckTag({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kBurgundy.withOpacity(0.90),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: kGoldDark.withOpacity(0.8), width: 1.0),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: kGoldLight,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          height: 1.3,
        ),
      ),
    );
  }
}

class _FlyingClearCard extends StatefulWidget {
  final Offset from;
  final Offset to;
  final Widget card;
  final VoidCallback onComplete;

  const _FlyingClearCard({
    required this.from,
    required this.to,
    required this.card,
    required this.onComplete,
  });

  @override
  State<_FlyingClearCard> createState() => _FlyingClearCardState();
}

class _FlyingClearCardState extends State<_FlyingClearCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _ctrl.forward().then((_) {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = Curves.easeInOutCubic.transform(_ctrl.value);
        final pos = Offset.lerp(widget.from, widget.to, t)!;
        final scale = 1.0 - (t * 0.08);
        return Positioned(
          left: pos.dx - (72.0 * scale) / 2,
          top: pos.dy - (100.0 * scale) / 2,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Material(
        elevation: 10,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: widget.card,
      ),
    );
  }
}
