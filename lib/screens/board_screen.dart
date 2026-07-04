import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme_constants.dart';
import '../models/game_model.dart';
import '../utils/localization.dart';
import '../widgets/tutorial_overlay.dart';
import '../widgets/floating_hint.dart';
import '../widgets/duel_result_overlay.dart';
import '../widgets/rules_dialog.dart';
import '../widgets/banner_ad_widget.dart';
import '../services/tutorial_manager.dart';
import '../services/db_service.dart';
import '../services/haptic_service.dart';
import '../services/duel_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/daily_goal_service.dart';
import '../services/xp_service.dart';
import '../services/badge_service.dart';
import '../utils/app_feedback.dart';
import '../widgets/board/deck_tag.dart';
import '../widgets/dialogs/cosmetics_shop_dialog.dart';
import '../widgets/dialogs/difficulty_picker_dialog.dart';
import '../widgets/board/flying_clear_card.dart';
import '../widgets/board/game_over_overlay.dart';
import '../widgets/board/winner_overlay.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TUTORIAL HINT TYPES
// ─────────────────────────────────────────────────────────────────────────────
enum _HintType {
  none,
  numberCard,
  royalCard,
  clearStart,
  clearFirstDone,
}

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
  GameDifficulty _difficulty = GameDifficulty.classic;
  static const String _difficultyPrefKey = 'royalFrameDifficulty';

  Timer? _inactivityTimer;
  Timer? _uiTimer;

  // Duel mode state
  DuelSession? _duelSession;
  StreamSubscription<DuelSession?>? _duelSub;
  int _opponentScore = 0;
  bool _duelFinishedReported = false;
  bool _showDuelResult = false;
  bool _myRematchReady = false;
  int _myFinalElapsedSeconds = 0;
  int _myFinalRoyals = 0;

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

  final ScreenshotController _screenshotCtrl = ScreenshotController();

  Set<int> _hintedPair = {};
  bool _hintCurrentCard = false;
  late AnimationController _hintPulseCtrl;

  // Phase-transition pulse
  late AnimationController _phasePulseCtrl;
  bool _showPhasePulse = false;
  // Tracks whether the hint pulse was animating when the app was backgrounded,
  // so it can be restored on resume.
  bool _wasPulsingBeforePause = false;
  // Suppresses pop.mp3 for the entire duration of the phase-change banner so
  // the two sounds never overlap.
  bool _phaseTransitionBlocking = false;
  String _phaseLabel = '';
  String _phaseSubLabel = '';

  bool _moveMode = false;
  int? _moveFromIndex;
  bool _godMode = false;

  CardModel? _draggingCard;

  late AppLang _lang;
  L get _l => L(_lang);

  bool _showGameOverOverlay = false;
  bool _isAnimatingClear = false;
  final Set<int> _errorHighlights = {};

  // Tutorial (Phase A = blocking modals, Phase B/C = floating hints)
  bool _showWelcomeModals = false;
  bool _phaseAComplete = false; // guards against hints spawning during modals
  bool _pendingTutorialStart = false;
  _HintType _activeHint = _HintType.none;
  int _clearHintStep = 0;
  Timer? _hintAutoTimer;

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
  Future<void>? _unlockFuture;

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
      duration: const Duration(milliseconds: 2400),
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
    _initTutorial();
    _startUITimer();
    // Fire-and-forget by design (the UI renders sensible defaults until
    // they land), but failures must be visible in debug builds.
    DailyGoalService.load().catchError((e) => logError('dailyGoal.load', e));
    XpService.load().catchError((e) => logError('xp.load', e));
    BadgeService.load().catchError((e) => logError('badge.load', e));
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
      _onDuelUpdate(updated);
    });
  }

  Future<void> _onDuelUpdate(DuelSession updated) async {
    setState(() {
      _duelSession = updated;
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final isHost = updated.hostUid == myUid;
      _opponentScore = isHost ? updated.guestScore : updated.hostScore;
    });

    if (updated.isFinished && updated.abandonedBy == null && !_showDuelResult) {
      setState(() => _showDuelResult = true);
    }

    if (_showDuelResult && updated.isActive && updated.abandonedBy == null) {
      _executeRematch(updated.seed);
    }

    if (updated.abandonedBy != null && !_showDuelResult) {
      final name = updated.abandonedBy!;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _lang == AppLang.he
                  ? '$name עזב את המשחק'
                  : '$name has left the game',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            backgroundColor: kDanger,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        // Treat the remaining player as winner
        game.phase = Phase.winner;
        game.endTime ??= DateTime.now();
        setState(() => _duelSession = null);
        _checkEndState();
      }
    }
  }

  void _onPlayAgainTapped() {
    final session = _duelSession;
    if (session == null) return;
    setState(() => _myRematchReady = true);
    final isHost = session.hostUid == FirebaseAuth.instance.currentUser?.uid;
    final newSeed = isHost ? Random().nextInt(0x7FFFFFFF) : null;
    DuelService.signalRematch(
      session.duelId,
      isHost: isHost,
      newSeed: newSeed,
    ).catchError((e) {
      logError('duel.signalRematch', e);
      if (mounted) setState(() => _myRematchReady = false);
    });
  }

  void _executeRematch(int newSeed) {
    final session = _duelSession;
    if (session == null) return;

    setState(() {
      _showDuelResult = false;
      _myRematchReady = false;
      _duelFinishedReported = false;
      _xpAwardedThisGame = false;
      _statsUpdatedThisGame = false;
      _myFinalElapsedSeconds = 0;
      _myFinalRoyals = 0;
      _opponentScore = 0;
      _undo.clear();
      _redo.clear();
      _clearedAtLeastOnePairThisPhase = false;
      game = GameState.newGame(seed: newSeed);
      game.evaluateGameOverInFill();
    });
  }

  Future<void> _syncDuelScore() async {
    if (_duelSession == null) return;
    // Periodic sync: a false return (offline blip) heals on the next sync,
    // and syncScore logs its own failures.
    await DuelService.syncScore(_duelSession!.duelId, game.score);
  }

  /// Reports this player's final duel result with one retry (markFinished
  /// is transactional and keyed by uid, so retrying is safe). If the result
  /// still can't be recorded the player is told — otherwise the duel winner
  /// could be decided without their final score.
  Future<void> _reportDuelFinished(String duelId, int score) async {
    var ok = await DuelService.markFinished(
      duelId,
      score,
      elapsedSeconds: _myFinalElapsedSeconds,
      royalsPlaced: _myFinalRoyals,
    );
    ok = ok ||
        await DuelService.markFinished(
          duelId,
          score,
          elapsedSeconds: _myFinalElapsedSeconds,
          royalsPlaced: _myFinalRoyals,
        );
    if (!mounted) return;
    if (ok) {
      _duelFinishedReported = true;
    } else {
      // TODO(l10n): move into L class (Phase 7).
      showAppSnack(
        context,
        _lang == AppLang.he
            ? 'בעיית חיבור — ייתכן שתוצאת הדו-קרב לא נשמרה.'
            : 'Connection issue — your duel result may not be recorded.',
        isError: true,
      );
    }
  }

  Future<void> _loadSavedDifficulty() async {
    if (widget.existingGame != null) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_difficultyPrefKey) ?? 'classic';
    if (!mounted) return;
    setState(() {
      _difficulty = switch (saved) {
        'easy'               => GameDifficulty.easy,
        'medium'             => GameDifficulty.medium,
        'classic' || 'hard'  => GameDifficulty.classic,
        'expert' || 'extreme'=> GameDifficulty.expert,
        _                    => GameDifficulty.classic,
      };
    });
  }

  Future<void> _loadSavedLang() async {
    if (widget.initialLang != null) return;
    final lang = await L.loadLang();
    if (!mounted) return;
    setState(() => _lang = lang);
  }

  // ── Tutorial system ────────────────────────────────────────────────────────

  Future<void> _initTutorial() async {
    if (widget.existingGame != null && !widget.forceTutorial) return;
    await TutorialManager.syncFromFirestore();
    final shouldRun =
        await TutorialManager.init(force: widget.forceTutorial);
    if (!mounted) return;
    if (shouldRun) {
      if (widget.showNewGamePicker) {
        _pendingTutorialStart = true;
      } else {
        setState(() => _showWelcomeModals = true);
        _inactivityTimer?.cancel();
        _hintPulseCtrl.stop();
        _hintCurrentCard = false;
        _hintedPair.clear();
      }
    }
  }

  /// Called after welcome modals close and after every card placement
  /// during Phase B. Updates the floating hint based on game.current.
  void _evaluateFillHint() {
    if (!mounted) return;
    if (!_phaseAComplete) return;
    if (TutorialManager.phase != TutorialPhase.fillHints) return;
    if (game.phase != Phase.fill) return; // transition handled elsewhere

    final current = game.current;
    if (current == null) {
      setState(() => _activeHint = _HintType.none);
      return;
    }
    setState(() => _activeHint =
        current.isNumOrAce ? _HintType.numberCard : _HintType.royalCard);
  }

  /// Called when fill->clear transition happens while tutorial is active.
  void _onClearPhaseStarted() {
    if (!_phaseAComplete) return;
    if (TutorialManager.phase != TutorialPhase.fillHints) return;
    TutorialManager.advance(TutorialPhase.clearHints);
    setState(() {
      _activeHint = _HintType.clearStart;
      _clearHintStep = 0;
    });
  }

  /// Called after each successful pair clear during Phase C.
  void _advanceClearHint() {
    if (TutorialManager.phase != TutorialPhase.clearHints) return;
    if (_clearHintStep != 0) return; // only fire on the first clear

    _clearHintStep = 1;
    setState(() => _activeHint = _HintType.clearFirstDone);

    _hintAutoTimer?.cancel();
    _hintAutoTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _activeHint = _HintType.none);
      TutorialManager.complete();
    });
  }

  /// True when all 4 inner dump slots (indices 5, 6, 9, 10) are occupied.
  bool get _centerSlotsFull =>
      game.cells[5] != null &&
      game.cells[6] != null &&
      game.cells[9] != null &&
      game.cells[10] != null;

  /// Current hint message (localised).
  String get _hintMessage {
    final isHe = _lang == AppLang.he;
    return switch (_activeHint) {
      _HintType.numberCard => _centerSlotsFull
          ? (isHe
              ? 'קלף מספר! המרכז מלא, מקם אותו בחוכמה במסגרת החיצונית.'
              : 'You drew a number! Now place it carefully on the outer frame.')
          : (isHe
              ? 'קלף מספר! כדאי למקם אותו ב-4 משבצות המרכז.'
              : 'You drew a number! Best to place it in the center 4 slots.'),
      _HintType.royalCard => isHe
          ? 'קלף מלוכה! מקם אותו על המשבצת המתאימה במסגרת החיצונית.'
          : 'A Royal card! Place it on its matching slot in the outer frame.',
      _HintType.clearStart => isHe
          ? 'הלוח מלא! בחר שני קלפים שסכומם 11 (למשל 6 ו-5, או 8 ו-3).'
          : 'Board is full! Select two cards that sum to 11 (e.g. 6 and 5, or 8 and 3).',
      _HintType.clearFirstDone => isHe
          ? 'מצוין! המשך לפנות זוגות.'
          : 'Great! Keep clearing pairs.',
      _ => '',
    };
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

    if (_showWelcomeModals) return;

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
            !_showWelcomeModals) {
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
        if (mounted && game.phase == Phase.fill && !_showWelcomeModals) {
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
              FlyingClearCard(
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
      await _phasePlayer.setSourceAsset('audio/phase_change.mp3');
      _isAudioInitialized = true;
    } catch (_) {}
  }

  void _unlockAudio() {
    if (_audioUnlocked) return;
    _audioUnlocked = true;
    _unlockFuture = _doUnlock();
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
    _hintAutoTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pauseGameTimer();
      _stopAllAudioNow();
      _duelSub?.cancel();
      _duelSub = null;
      _hintAutoTimer?.cancel();
      _wasPulsingBeforePause = _hintPulseCtrl.isAnimating;
      _hintPulseCtrl.stop();
      _phasePulseCtrl.stop();
      _confettiCtrl.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (_duelSession != null) {
        _duelSub = DuelService.watchDuel(_duelSession!.duelId).listen((updated) {
          if (!mounted || updated == null) return;
          _onDuelUpdate(updated);
        });
      }
      _resumeGameTimer();
      if (_wasPulsingBeforePause) {
        _hintPulseCtrl.repeat(reverse: true);
        _wasPulsingBeforePause = false;
      }
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
    if (_isMuted || !mounted || _phaseTransitionBlocking) return;
    try {
      if (!_isAudioInitialized) await _initAudio();
      if (_unlockFuture != null) await _unlockFuture;
      await _popPlayer.setVolume(1.0);
      await _popPlayer.seek(Duration.zero);
      if (!mounted) return;
      await _popPlayer.resume();
    } catch (_) {}
  }

  Future<void> _playPlace() async {
    if (_isMuted || !mounted) return;
    try {
      if (!_isAudioInitialized) await _initAudio();
      if (_unlockFuture != null) await _unlockFuture;
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
    if (TutorialManager.isActive) {
      _hintAutoTimer?.cancel();
      setState(() => _activeHint = _HintType.none);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _evaluateFillHint());
    }
  }

  // ── New-game flow ──────────────────────────────────────────────────────────

  // Shows the difficulty picker. On selection, calls _executeNewGame.
  // Used by: AppBar refresh icon, "New Game" in main menu, difficulty menu item.
  void _openDifficultyPicker() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => DifficultyPickerDialog(
        current: _difficulty,
        lang: _lang,
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
    // Clear any lingering tutorial state when starting a new game.
    _hintAutoTimer?.cancel();
    _clearHintStep = 0;
    TutorialManager.isActive = false;
    TutorialManager.phase = TutorialPhase.done;
    setState(() {
      _showWelcomeModals = false;
      _activeHint = _HintType.none;
    });
    _restartHintTimer();
    _startUITimer();
    if (_pendingTutorialStart) {
      _pendingTutorialStart = false;
      _inactivityTimer?.cancel();
      _hintPulseCtrl.stop();
      _hintCurrentCard = false;
      _hintedPair.clear();
      setState(() => _showWelcomeModals = true);
    }
  }

  // ── End-state ──────────────────────────────────────────────────────────────

  void _checkEndState() {
    if (game.phase == Phase.winner) {
      _inactivityTimer?.cancel();
      _hintAutoTimer?.cancel();
      _hintPulseCtrl.stop();
      setState(() {
        _hintedPair.clear();
        _hintCurrentCard = false;
        _activeHint = _HintType.none;
      });
      DailyGoalService.addProgress(GoalType.finishMatch, 1);
      if (!_xpAwardedThisGame) {
        _xpAwardedThisGame = true;
        final xp = switch (_difficulty) {
          GameDifficulty.easy    => 125,
          GameDifficulty.medium  => 250,
          GameDifficulty.classic => 500,
          GameDifficulty.expert  => 1000,
        };
        XpService.addXP(xp);
      }
      // Duel: report final score as winner
      if (_duelSession != null && !_duelFinishedReported) {
        final duelId = _duelSession!.duelId;
        final score = game.score;
        _myFinalElapsedSeconds =
            (game.endTime ?? DateTime.now()).difference(game.startTime).inSeconds;
        _myFinalRoyals = game.royalsPlacedCorrect;
        _reportDuelFinished(duelId, score);
      }
      setState(() => _showGameOverOverlay = false);
      _confettiCtrl.play();
      _playWin();
    } else if (game.phase == Phase.gameOver) {
      _inactivityTimer?.cancel();
      _hintAutoTimer?.cancel();
      _hintPulseCtrl.stop();
      setState(() {
        _hintedPair.clear();
        _hintCurrentCard = false;
        _activeHint = _HintType.none;
      });
      DailyGoalService.addProgress(GoalType.finishMatch, 1);
      if (!_xpAwardedThisGame) {
        _xpAwardedThisGame = true;
        final xp = switch (_difficulty) {
          GameDifficulty.easy    => 12,
          GameDifficulty.medium  => 25,
          GameDifficulty.classic => 50,
          GameDifficulty.expert  => 100,
        };
        XpService.addXP(xp);
      }
      // Duel: report final score as loser
      if (_duelSession != null && !_duelFinishedReported) {
        final duelId = _duelSession!.duelId;
        final score = game.score;
        _myFinalElapsedSeconds =
            (game.endTime ?? DateTime.now()).difference(game.startTime).inSeconds;
        _myFinalRoyals = game.royalsPlacedCorrect;
        _reportDuelFinished(duelId, score);
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

  void _showOccupiedSlotWarning() {
    HapticService.heavy();
    final isHe = _lang == AppLang.he;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isHe
              ? 'לא ניתן להניח קלף על משבצת תפוסה!'
              : 'You cannot place a card on top of another card!',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        backgroundColor: kDanger,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1800),
        margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
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
    if (isFillToClear) {
      _clearedAtLeastOnePairThisPhase = false;
      _onClearPhaseStarted();
    }
    _triggerPhaseTransitionFeedback(isFillToClear: isFillToClear);
  }

  void _triggerPhaseTransitionFeedback({required bool isFillToClear}) {
    HapticService.success();

    if (!_isMuted) {
      _phasePlayer.setVolume(1.0).then((_) {
        return _phasePlayer.seek(Duration.zero);
      }).then((_) {
        if (!mounted) return;
        _phasePlayer.resume().catchError((_) {});
      }).catchError((_) {});
    }

    if (!mounted) return;
    setState(() {
      _showPhasePulse = true;
      if (isFillToClear) {
        _phaseLabel = _lang == AppLang.he ? 'שלב הניקוי!' : 'CLEAR PHASE!';
        _phaseSubLabel = _lang == AppLang.he
            ? 'מצא זוגות שסכומם 11'
            : 'Find pairs that sum to 11';
      } else {
        _phaseLabel = _lang == AppLang.he ? 'שלב המילוי!' : 'FILL PHASE!';
        _phaseSubLabel = _lang == AppLang.he
            ? 'הנח קלפים על הלוח'
            : 'Draw cards to fill the board';
      }
    });
    _phaseTransitionBlocking = true;
    _phasePulseCtrl.forward(from: 0).then((_) {
      if (mounted) {
        setState(() => _showPhasePulse = false);
        _phaseTransitionBlocking = false;
      }
    });
  }

  // ── Input handlers ────────────────────────────────────────────────────────

  void _onTapCell(int i) {
    if (_showWelcomeModals) return;
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
      // Easy mode: tapping an occupied numOrAce cell toggles it for pair-clearing.
      if (game.difficulty == GameDifficulty.easy && game.cells[i] != null) {
        if (_isAnimatingClear) return;
        setState(() {
          game.toggleSelectForClear(i);
          if (game.selectedForClear.length == 2) {
            if (game.canClearSelection) {
              _doClear();
            } else {
              _flashError(game.selectedForClear.toList());
              game.selectedForClear.clear();
            }
          }
        });
        _restartHintTimer();
        return;
      }

      if (game.cells[i] != null && !_moveMode) {
        _showOccupiedSlotWarning();
        return;
      }
      _pushUndo();
      final previousPhase = game.phase;
      final ok = game.tryPlaceAt(i, godMode: _godMode);

      if (ok) {
        HapticService.light();
        final phaseWillChange = previousPhase != game.phase;
        if (!phaseWillChange) _playPlace();
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

      setState(() {});
      _checkEndState();
      _restartHintTimer();
      _evaluateFillHint();
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
      final isPhaseChange = previousPhase != game.phase;
      if (!isPhaseChange) _playPop();
      _maybeTriggerPhaseTransitionFeedback(previousPhase, game.phase);
      _checkEndState();
      _restartHintTimer();
      _advanceClearHint();
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
      builder: (_) => CosmeticsShopDialog(
        onChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  // Returns the correct store / web link for the current platform.
  static String get _shareLink {
    if (kIsWeb) return 'https://royal-frame.netlify.app';
    if (Platform.isAndroid) {
      return 'https://play.google.com/store/apps/details?id=com.itay.royalframegame';
    }
    return 'https://royal-frame.netlify.app';
  }

  /// Captures the current screen, writes it to a temp file, and shares it
  /// together with [text]. Falls back to text-only on web (browsers rarely
  /// support Web Share API Level 2 file sharing).
  Future<void> _captureAndShare(String text) async {
    try {
      final imageBytes = await _screenshotCtrl.capture(pixelRatio: 2.0);
      if (imageBytes == null) throw Exception('capture returned null');

      if (kIsWeb) {
        try {
          await SharePlus.instance.share(
            ShareParams(
              text: text,
              files: [XFile.fromData(imageBytes, mimeType: 'image/png', name: 'royal_frame_result.png')],
            ),
          );
        } catch (_) {
          await SharePlus.instance.share(ShareParams(text: text));
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/royal_frame_result.png');
      await file.writeAsBytes(imageBytes);

      await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: [XFile(file.path, mimeType: 'image/png')],
        ),
      );
    } catch (_) {
      // If screenshot or file I/O fails, share text only.
      await SharePlus.instance.share(ShareParams(text: text));
    }
  }

  Future<void> _shareVictory(int totalScore) async {
    final int elapsedSecs = (game.endTime ?? DateTime.now())
        .difference(game.startTime)
        .inSeconds;
    final m = (elapsedSecs ~/ 60).toString().padLeft(2, '0');
    final s = (elapsedSecs % 60).toString().padLeft(2, '0');
    await _captureAndShare(_l.shareVictory('$m:$s', totalScore, _shareLink));
  }

  Future<void> _shareGameOver() async {
    await _captureAndShare(_l.shareGameOver(game.score, _shareLink));
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
                    color: kRoyalGlowColor.withValues(alpha: 0.3),
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
              ? kGold.withValues(alpha: 0.9)
              : kGoldDark.withValues(alpha: 0.75),
          width: depth == 0 ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30 + depth * 0.06),
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
            Border.all(color: kGoldDark.withValues(alpha: 0.55), width: 1.6),
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
          : _playingCard(top),
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
          if (!_showWelcomeModals) setState(() => _draggingCard = curr);
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
              color: Colors.black.withValues(alpha: 0.45),
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
                bgColor     = kTableGreenMid.withValues(alpha: 0.5);
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
                    kRoyalCellGradEdge,
                    kRoyalCellGradMid,
                    kRoyalCellGradEdge,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                );
                shadows = [
                  BoxShadow(
                    color: kRoyalGlowColor.withValues(alpha: 0.55),
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

              if (selected && (game.phase == Phase.clear || (game.phase == Phase.fill && game.difficulty == GameDifficulty.easy))) {
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
                                  ? kDragTargetBorder.withValues(alpha: 0.95)
                                  : kSlotFrameBorder.withValues(alpha: 0.85),
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
                !isNumberCard;

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
              onAcceptWithDetails: (_) {
                if (_showWelcomeModals) return;
                _unlockAudio();
                if (game.phase != Phase.fill || game.current == null) return;
                if (game.cells[i] != null) {
                  _showOccupiedSlotWarning();
                  return;
                }

                _pushUndo();
                final previousPhase = game.phase;
                final ok = game.tryPlaceAt(i, godMode: _godMode);

                if (ok) {
                  setState(() {});
                  HapticService.light();
                  final phaseWillChange = previousPhase != game.phase;
                  if (!phaseWillChange) _playPlace();
                  _maybeTriggerPhaseTransitionFeedback(previousPhase, game.phase);
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
                  _evaluateFillHint();
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

  // Canonical difficulty accents (easy=green, medium=blue) — this badge
  // previously had easy/medium swapped relative to the difficulty picker.
  Color get _difficultyColor => switch (_difficulty) {
        GameDifficulty.easy    => kDiffEasy,
        GameDifficulty.medium  => kDiffMedium,
        GameDifficulty.classic => kGold,
        GameDifficulty.expert  => kDiffExpert,
      };

  String get _difficultyLabel => switch (_difficulty) {
        GameDifficulty.easy    => _lang == AppLang.he ? 'קל'     : 'EASY',
        GameDifficulty.medium  => _lang == AppLang.he ? 'בינוני' : 'MEDIUM',
        GameDifficulty.classic => _lang == AppLang.he ? 'קלאסי'  : 'CLASSIC',
        GameDifficulty.expert  => _lang == AppLang.he ? 'מומחה'  : 'EXPERT',
      };

  @override
  Widget build(BuildContext context) {
    final dragHighlights = _computeDragHighlights();
    const double deckRowH = 150.0;
    const double innerGap = 6.0;

    final int elapsedSecs = (game.endTime ?? DateTime.now())
        .difference(game.startTime)
        .inSeconds;

    final bool isExtreme = game.difficulty == GameDifficulty.expert;
    final int displaySecs =
        isExtreme ? max(0, _extremeSeconds - elapsedSecs) : elapsedSecs;
    final bool isCountdown = isExtreme;
    final bool timerCritical = isExtreme && displaySecs <= 30;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _pauseGameTimer();
        final navigator = Navigator.of(context);
        await _stopAllAudioNow();
        if (!mounted) return;
        navigator.pop(game);
      },
      child: Directionality(
        textDirection:
            _lang == AppLang.he ? TextDirection.rtl : TextDirection.ltr,
        child: Screenshot(
          controller: _screenshotCtrl,
          child: Scaffold(
          backgroundColor: XpService.equippedBoardColor,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: XpService.equippedBoardColorLight,
            titleSpacing: 0,
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
                        color: _difficultyColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _difficultyColor.withValues(alpha: 0.55),
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
                const SizedBox(width: 4),

                // Score + timer bar
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: kGoldDark.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.emoji_events,
                            size: 18, color: kGold),
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
                          size: 18,
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
                const SizedBox(width: 2),

                // Action buttons — Flexible lets this section yield space
                // to the score/timer Expanded; FittedBox scales icons down
                // proportionally when the screen is narrow.
                Flexible(
                  child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildCompactIcon(Icons.home, kGold, () {
                      if (game.phase == Phase.winner ||
                          game.phase == Phase.gameOver) {
                        Navigator.pop(context, game);
                        return;
                      }
                      if (_duelSession != null) {
                        showDialog(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            backgroundColor: kBurgundyLight,
                            title: Text(
                              _lang == AppLang.he
                                  ? 'לעזוב את הדו-קרב?'
                                  : 'Leave the Duel?',
                              style: const TextStyle(color: kGold),
                            ),
                            content: Text(
                              _lang == AppLang.he
                                  ? 'אם תעזוב, תפסיד את הדו-קרב והיריב יוכרז כמנצח.'
                                  : 'If you leave, you forfeit the duel and your opponent wins.',
                              style: const TextStyle(color: Colors.white),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: Text(
                                  _lang == AppLang.he ? 'ביטול' : 'Cancel',
                                  style: const TextStyle(color: kGoldDark),
                                ),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: kDanger,
                                    foregroundColor: Colors.white),
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  final name = FirebaseAuth
                                          .instance.currentUser?.displayName ??
                                      (_lang == AppLang.he ? 'יריב' : 'Opponent');
                                  DuelService.markAbandoned(
                                      _duelSession!.duelId, name);
                                  _duelSub?.cancel();
                                  Navigator.pop(context, game);
                                },
                                child: Text(
                                  _lang == AppLang.he ? 'עזוב' : 'Leave',
                                ),
                              ),
                            ],
                          ),
                        );
                        return;
                      }
                      // Solo mode: show the existing confirmation dialog
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

                    DailyGoalService.current?.isCompleted == true
                        ? _buildDailyGoalCompletedBadge()
                        : _buildCompactIcon(Icons.flag, kGold, _showDailyGoal),
                    const SizedBox(width: 2),

                    SizedBox(
                      width: 38,
                      child: PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.settings_outlined,
                          color: kGold,
                          size: 22,
                        ),
                        padding: EdgeInsets.zero,
                        color: kBurgundyLight,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                              color: kGoldDark.withValues(alpha: 0.5)),
                        ),
                        onSelected: (value) {
                          if (value == 'rules') {
                            showDialog(
                                context: context,
                                builder: (_) => RulesDialog(
                                  lang: _lang,
                                  onReplayTutorial: () {
                                    _inactivityTimer?.cancel();
                                    _hintPulseCtrl.stop();
                                    _hintCurrentCard = false;
                                    _hintedPair.clear();
                                    TutorialManager.isActive = true;
                                    TutorialManager.phase = TutorialPhase.modals;
                                    setState(() => _showWelcomeModals = true);
                                  },
                                ));
                          } else if (value == 'difficulty') {
                            _showDifficultyPicker();
                          } else if (value == 'cosmetics') {
                            _showThemeGallery();
                          } else if (value == 'lang') {
                            final newLang = _lang == AppLang.he ? AppLang.en : AppLang.he;
                            setState(() => _lang = newLang);
                            L.saveLang(newLang);
                          } else if (value == 'mute') {
                            _toggleMute();
                          } else if (value == 'haptic') {
                            _toggleHaptic();
                          } else if (value == 'optional_clearing') {
                            _toggleOptionalClearing();
                          }
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
                                (_lang == AppLang.he ? 'רמה: ' : 'Difficulty: ') + _difficultyLabel,
                                style: const TextStyle(
                                    color: kGoldLight, fontSize: 14),
                              ),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'cosmetics',
                            child: Row(children: [
                              const Icon(Icons.style, color: kGold, size: 20),
                              const SizedBox(width: 12),
                              Text(
                                _lang == AppLang.he ? 'ערכות נושא' : 'Themes',
                                style: const TextStyle(color: kGoldLight, fontSize: 14),
                              ),
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
                              Text(_isMuted
                                  ? (_lang == AppLang.he ? 'בטל השתקה' : 'Unmute')
                                  : (_lang == AppLang.he ? 'השתק' : 'Mute'),
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
                                      ? (_lang == AppLang.he ? 'רטט: פועל' : 'Vibration: On')
                                      : (_lang == AppLang.he ? 'רטט: כבוי' : 'Vibration: Off'),
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
                        ],
                      ),
                    ),
                  ],
                  ),  // Row
                ),    // FittedBox
                ),    // Flexible
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
                          color: kGoldDark.withValues(alpha: 0.25),
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
                          true)
                        Container(
                          color: kBurgundy.withValues(alpha: 0.85),
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
                                    color: kGoldDark.withValues(alpha: 0.3),
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
                                  // Deck-row dimming during the clear phase
                                  // was intentionally disabled; render at
                                  // full opacity.
                                  SizedBox(
                                    height: deckRowH,
                                    child: Center(
                                        child: _deckRow()),
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
                    _winnerOverlayHost(),

                  if (game.phase == Phase.gameOver &&
                      _showGameOverOverlay)
                    _gameOverOverlayHost(),

                  // Duel HUD — live opponent score + result banner
                  if (_duelSession != null &&
                      game.phase != Phase.winner &&
                      game.phase != Phase.gameOver)
                    _buildDuelHud(),

                  // Duel comparison screen — shown when both players finish
                  if (_duelSession != null && _showDuelResult &&
                      _duelSession!.abandonedBy == null)
                    Positioned.fill(
                      child: DuelResultOverlay(
                        session: _duelSession!,
                        myUid: FirebaseAuth.instance.currentUser?.uid ?? '',
                        myElapsedSeconds: _myFinalElapsedSeconds,
                        myRoyals: _myFinalRoyals,
                        myRematchReady: _myRematchReady,
                        onPlayAgain: _onPlayAgainTapped,
                      ),
                    ),

                  // Floating contextual hints (Phase B & C) — non-blocking,
                  // anchored top-left so they never cover the grid center.
                  if (_activeHint != _HintType.none)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: FloatingHint(
                        key: ValueKey(_activeHint),
                        message: _hintMessage,
                      ),
                    ),

                  // Welcome modals (Phase A) — blocking, always on top
                  if (_showWelcomeModals)
                    TutorialOverlay(
                      lang: _lang,
                      deckRowKey: _deckRowKey,
                      gridKey: _gridKey,
                      cellKeys: _cellKeys,
                      onFinish: ({bool skipped = false}) {
                        setState(() {
                          _showWelcomeModals = false;
                          _phaseAComplete = true;
                        });
                        TutorialManager.advance(TutorialPhase.fillHints);
                        TutorialManager.complete();
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _evaluateFillHint(),
                        );
                        _restartHintTimer();
                      },
                    ),

                  // Phase-transition banner overlay
                  if (_showPhasePulse)
                    IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _phasePulseCtrl,
                        builder: (context, child) {
                          final t = _phasePulseCtrl.value;
                          // Fade in 0→0.12, hold 0.12→0.72, fade out 0.72→1.0
                          final double opacity;
                          if (t < 0.12) {
                            opacity = t / 0.12;
                          } else if (t < 0.72) {
                            opacity = 1.0;
                          } else {
                            opacity = 1.0 - (t - 0.72) / 0.28;
                          }
                          // Elastic scale-in over first 16%, then hold at 1.0
                          final double scale;
                          if (t < 0.16) {
                            final tn = (t / 0.16).clamp(0.0, 1.0);
                            scale = 0.62 +
                                0.38 *
                                    Curves.elasticOut.transform(tn);
                          } else {
                            scale = 1.0;
                          }
                          return Center(
                            child: Opacity(
                              opacity: opacity.clamp(0.0, 1.0),
                              child: Transform.scale(
                                scale: scale,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          constraints:
                              const BoxConstraints(maxWidth: 320),
                          margin: const EdgeInsets.symmetric(
                              horizontal: 28),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.black.withValues(alpha: 0.30),
                                Colors.black.withValues(alpha: 0.22),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: kGold.withValues(alpha: 0.75),
                                width: 1.8),
                            boxShadow: [
                              BoxShadow(
                                color: kGold.withValues(alpha: 0.35),
                                blurRadius: 36,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _phaseLabel,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: kGold,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3.5,
                                  shadows: [
                                    Shadow(
                                      color: kGold,
                                      blurRadius: 22,
                                    ),
                                    Shadow(
                                      color: Colors.black,
                                      blurRadius: 10,
                                      offset: Offset(0, 2),
                                    ),
                                    Shadow(
                                      color: Colors.black,
                                      blurRadius: 3,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _phaseSubLabel,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.90),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.4,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
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
                      // Brand palette — replaces the off-brand pink/blue.
                      colors: kConfettiColors,
                      shouldLoop: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: buildBannerAd(),
          ),      // Screenshot
        ),
      ),
    );
  }

  Widget _buildDuelHud() {
    if (_showDuelResult) return const SizedBox.shrink();
    final session = _duelSession;
    if (session == null) return const SizedBox.shrink();

    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isHost = session.hostUid == myUid;
    final myScore = game.score;
    final opponentName = isHost
        ? (session.guestName ?? 'Opponent')
        : session.hostName;

    // Result banner when duel is finished
    if (session.isFinished && session.abandonedBy == null) {
      final iWon = session.winnerId == myUid;
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Container(
            color: iWon
                ? kGold.withValues(alpha: 0.88)
                : Colors.redAccent.withValues(alpha: 0.82),
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
          color: Colors.black.withValues(alpha: 0.65),
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
                color: kGoldDark.withValues(alpha: 0.6),
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


  Widget _buildCompactIcon(
      IconData icon, Color color, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        child: Icon(icon, size: 26, color: color),
      ),
    );
  }

  /// Fixed-size golden badge shown in the AppBar when the daily goal is done.
  /// Constrained to the same footprint as _buildCompactIcon so it never
  /// overflows the AppBar row.
  Widget _buildDailyGoalCompletedBadge() {
    return InkWell(
      onTap: _showDailyGoal,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: SizedBox(
          width: 26,
          height: 26,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [kStreakBadgeStart, kStreakBadgeEnd],
              ),
              boxShadow: const [
                BoxShadow(
                  color: kStreakBadgeGlow,
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.check, size: 16, color: kBurgundyDeep),
            ),
          ),
        ),
      ),
    );
  }


  /// Hosts [WinnerOverlay]. Keeps the one-shot stats side effect with the
  /// screen state and computes the score breakdown at end-state time; the
  /// overlay itself is pure visual.
  // TODO(defect-report): this write fires during build (guarded by
  // _statsUpdatedThisGame). Pre-existing behavior, intentionally preserved.
  Widget _winnerOverlayHost() {
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
      GameDifficulty.easy    => 0.25,
      GameDifficulty.medium  => 0.5,
      GameDifficulty.classic => 1.0,
      GameDifficulty.expert  => 2.0,
    };
    final int totalScore = (rawTotal * multiplier).round();

    final int xpGained = switch (_difficulty) {
      GameDifficulty.easy    => 125,
      GameDifficulty.medium  => 250,
      GameDifficulty.classic => 500,
      GameDifficulty.expert  => 1000,
    };

    return WinnerOverlay(
      stats: (
        baseScore: baseScore,
        winBonus: winBonus,
        effBonus: effBonus,
        speedBonus: speedBonus,
        multiplier: multiplier,
        totalScore: totalScore,
        xpGained: xpGained,
      ),
      lang: _lang,
      onPlayAgain: _restartCurrentGame,
      onChangeDifficulty: _openDifficultyPicker,
      onShare: () => _shareVictory(totalScore),
      onMainMenu: () => Navigator.of(context).pop(),
    );
  }

  /// Hosts [GameOverOverlay]. Keeps the one-shot stats side effect with the
  /// screen state; the overlay itself is pure visual.
  // TODO(defect-report): this write fires during build (guarded by
  // _statsUpdatedThisGame). Pre-existing behavior, intentionally preserved —
  // see the sprint's final defect report before changing.
  Widget _gameOverOverlayHost() {
    if (!_statsUpdatedThisGame) {
      _statsUpdatedThisGame = true;
      DbService().updatePlayerStats(game.score, false);
      DailyGoalService.addProgress(GoalType.scorePoints, game.score);
    }
    return GameOverOverlay(
      game: game,
      lang: _lang,
      xpGained: switch (_difficulty) {
        GameDifficulty.easy    => 12,
        GameDifficulty.medium  => 25,
        GameDifficulty.classic => 50,
        GameDifficulty.expert  => 100,
      },
      onTryAgain: _restartCurrentGame,
      onChangeDifficulty: _openDifficultyPicker,
      onShare: _shareGameOver,
      onMainMenu: () => Navigator.of(context).pop(),
    );
  }
}
