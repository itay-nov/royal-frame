import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme_constants.dart';
import '../models/game_model.dart';
import '../utils/localization.dart';
import '../widgets/tutorial_overlay.dart';
import '../services/db_service.dart';
// ─────────────────────────────────────────────────────────────────────────────
// BOARD SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class BoardScreen extends StatefulWidget {
  final GameState? existingGame; // מקבל משחק קיים אם יש
  const BoardScreen({super.key, this.existingGame});
  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> with TickerProviderStateMixin {
  late GameState game;
  final List<GameState> _undo = [];
  final List<GameState> _redo = [];

  Timer? _inactivityTimer;
  Timer? _uiTimer; // טיימר שמעדכן את מדד הזמן למעלה
  Set<int> _hintedPair  = {};
  bool _hintCurrentCard = false;
  late AnimationController _hintPulseCtrl;
  
  bool _moveMode        = false;
  int? _moveFromIndex;
  bool _showDebugTools  = false;

  bool _godMode         = false;

  CardModel? _draggingCard;

  AppLang _lang = AppLang.en;
  L get _l => L(_lang);

  bool _showGameOverOverlay = false;
  bool _isAnimatingClear    = false;
  Set<int> _errorHighlights = {};
  
  bool _showTutorial = false; 
  bool _showClearTutorial = false;
  bool _hasSeenInitialTutorial = false;
  bool _hasSeenClearTutorial = false;

  // Audio
  bool _isMuted = false;
  final AudioPlayer _winPlayer   = AudioPlayer();
  final AudioPlayer _lossPlayer  = AudioPlayer();
  final AudioPlayer _popPlayer   = AudioPlayer();
  final AudioPlayer _placePlayer = AudioPlayer();
  bool _audioUnlocked = false;

  // Confetti
  late ConfettiController _confettiCtrl;

  final GlobalKey _clearPileKey = GlobalKey();
  final GlobalKey _deckRowKey = GlobalKey();
  final GlobalKey _gridKey = GlobalKey();
  late final List<GlobalKey> _cellKeys;

  @override
  void initState() {
    super.initState();
    _cellKeys = List.generate(16, (_) => GlobalKey());
    _confettiCtrl = ConfettiController(duration: const Duration(seconds: 6));
    _hintPulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    game = widget.existingGame ?? GameState.newGame();
    game.evaluateGameOverInFill();
    _initAudio();
    _loadTutorialState();
    
    // מפעילים את שעון המשחק שמעדכן את ה-UI כל שנייה
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (game.phase != Phase.winner && game.phase != Phase.gameOver) {
        setState(() {});
      }
    });
  }

  Future<void> _loadTutorialState() async {
    final prefs = await SharedPreferences.getInstance();
    _hasSeenInitialTutorial = prefs.getBool('hasSeenTutorialV2') ?? false;
    _hasSeenClearTutorial = prefs.getBool('hasSeenClearTutorialV2') ?? false;
    
    if (!_hasSeenInitialTutorial) {
      setState(() => _showTutorial = true);
      _inactivityTimer?.cancel();
      _hintPulseCtrl.stop();
      _hintCurrentCard = false;
      _hintedPair.clear();
      await prefs.setBool('hasSeenTutorialV2', true);
    }
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
      _inactivityTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && game.phase == Phase.clear && !_isAnimatingClear && !_showClearTutorial) {
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
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
      ));

      await _winPlayer.setReleaseMode(ReleaseMode.stop);
      await _lossPlayer.setReleaseMode(ReleaseMode.stop);
      await _popPlayer.setReleaseMode(ReleaseMode.stop);
      await _placePlayer.setReleaseMode(ReleaseMode.stop);
      await _winPlayer.setSourceAsset('audio/win_cheer.mp3');
      await _lossPlayer.setSourceAsset('audio/game_over.mp3');
      await _popPlayer.setSourceAsset('audio/pop.mp3');
      await _placePlayer.setSourceAsset('audio/place_card.mp3');
    } catch (_) {}
  }

  void _unlockAudio() {
    if (_audioUnlocked) return;
    _audioUnlocked = true;
    _doUnlock();
  }
  
  Future<void> _doUnlock() async {
    try {
      for (final p in [_winPlayer, _lossPlayer, _popPlayer, _placePlayer]) {
        await p.setVolume(0); await p.resume(); await p.stop(); await p.setVolume(1);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _uiTimer?.cancel();
    _hintPulseCtrl.dispose();
    _confettiCtrl.dispose();
    _winPlayer.dispose(); _lossPlayer.dispose(); _popPlayer.dispose(); _placePlayer.dispose();
    super.dispose();
  }

  Future<void> _playWin()   async { if (_isMuted) return; try { await _winPlayer.stop();   await _winPlayer.play(AssetSource('audio/win_cheer.mp3')); } catch (_) {} }
  Future<void> _playLoss()  async { if (_isMuted) return; try { await _lossPlayer.stop();  await _lossPlayer.play(AssetSource('audio/game_over.mp3')); } catch (_) {} }
  Future<void> _playPop()   async { if (_isMuted) return; try { await _popPlayer.stop();   await _popPlayer.play(AssetSource('audio/pop.mp3')); } catch (_) {} }
  Future<void> _playPlace() async { if (_isMuted) return; try { await _placePlayer.stop(); await _placePlayer.play(AssetSource('audio/place_card.mp3')); } catch (_) {} }

  void _pushUndo() { _undo.add(game.clone()); _redo.clear(); }

  void _undoAction() {
    if (_undo.isEmpty) return;
    _redo.add(game.clone());
    setState(() {
      game = _undo.removeLast();
      _moveMode = false; _moveFromIndex = null;
      _showGameOverOverlay = game.phase == Phase.gameOver;
    });
    _restartHintTimer();
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    _undo.add(game.clone());
    setState(() {
      game = _redo.removeLast();
      _moveMode = false; _moveFromIndex = null;
      _showGameOverOverlay = game.phase == Phase.gameOver;
    });
    _restartHintTimer();
  }

  void _newGame({int? seed}) {
    _confettiCtrl.stop();
    _winPlayer.stop();
    _lossPlayer.stop();
    _popPlayer.stop();
    _placePlayer.stop();

    setState(() {
      _undo.clear(); _redo.clear();
      game = GameState.newGame(seed: seed);
      game.evaluateGameOverInFill();
      _moveMode = false; _moveFromIndex = null;
      _showGameOverOverlay = false;
      _godMode = false;
      _isAnimatingClear = false;
      _errorHighlights.clear();
    });
    _restartHintTimer();
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

  void _flashError(List<int> indices) {
    _errorHighlights.addAll(indices);
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() => _errorHighlights.removeAll(indices));
      }
    });
  }

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
          _restartHintTimer();
        } else {
          setState(() => _moveFromIndex = i);
        }
      }
      return;
    }

    if (game.phase == Phase.fill) {
      _pushUndo();
      final ok = game.tryPlaceAt(i, godMode: _godMode);
      if (ok) {
        HapticFeedback.lightImpact();
        _playPlace();
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
            _flashError(game.selectedForClear.toList());
            game.selectedForClear.clear();
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

    _isAnimatingClear = true;
    _animateClearToPile(indices, cards, () {
      if (!mounted) return;
      _pushUndo();
      setState(() {
        game.performClear(); 
        _isAnimatingClear = false;
      });
      HapticFeedback.selectionClick();
      _playPop();
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
            const SizedBox(height: 24),
            Center(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: kGold,
                  side: const BorderSide(color: kGold),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                label: Text(_l.btnReplayTutorial, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
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

  static const double kCardW = 72.0;
  static const double kCardH = 100.0;

  int _deckStackLayers(int remaining) {
    if (remaining <= 0) return 0;
    if (remaining > 30) return 4;
    if (remaining >= 15) return 3;
    return 2;
  }

  Widget _playingCardFallback(CardModel c, {required double w, required double h}) {
    final faceColor = isRed(c.suit) ? kCardRed : kCardBlack;
    final large = w > kCardW;
    return Container(
      width: w, height: h,
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
            style: TextStyle(fontSize: large ? 36.0 : 28.0, color: faceColor),
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
          border: Border.all(color: isRoyal ? kGold : kGoldDark, width: isRoyal ? 2.0 : 1.6),
          boxShadow: isRoyal ? [BoxShadow(color: kRoyalGlowColor.withOpacity(0.3), blurRadius: 6)] : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.asset(
            'assets/images/$localImageName', 
            fit: BoxFit.fill,
            errorBuilder: (_, __, ___) => Container(
              color: kCardWhite, 
              child: Center(child: Text(c.label, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))
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
    return Image.asset(
      kCardBackAsset,
      width: kCardW,
      height: kCardH,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) =>
          const ColoredBox(color: Color(0xFFB71C1C)),
    );
  }

  Widget _cardBackLayer({int depth = 0}) {
    return Container(
      width: kCardW,
      height: kCardH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: depth == 0 ? kGold.withOpacity(0.9) : kGoldDark.withOpacity(0.75),
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
        border: Border.all(color: kGoldDark.withOpacity(0.55), width: 1.6),
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
      width: 72, height: 100,
      decoration: BoxDecoration(
        color: kBurgundyLight, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kGoldDark, width: 1.2),
      ),
      child: Center(child: Text(label,
          style: const TextStyle(color: kGold, fontWeight: FontWeight.bold))),
    );
  }

  Widget _pileWithTag({
    required Widget base,
    required String tagText,
    Alignment baseAlign = Alignment.bottomLeft,
  }) {
    return SizedBox(
      width: kDeckStackW,
      height: kDeckStackH,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Align(alignment: baseAlign, child: base),
          Positioned(top: 4, right: 2, child: DeckTag(text: tagText)),
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

    var deckTagText = '${_l.labelDeck}\n${game.cardsRemainingDisplay}';
    if (peek != null) {
      deckTagText += '\n${_l.peekNext('${peek.label}${suitSymbol(peek.suit)}')}';
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
        feedback: Opacity(opacity: 0.9, child: _playingCard(curr, large: true)),
        childWhenDragging: _playingCard(curr, dimmed: true),
        onDragStarted:       () { if (!_showTutorial) setState(() => _draggingCard = curr); },
        onDragEnd:           (_)    => setState(() => _draggingCard = null),
        onDraggableCanceled: (_, __) => setState(() => _draggingCard = null),
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
    fontSize: 11, fontWeight: FontWeight.w600,
    color: dimmed ? Colors.white38 : kGoldLight,
    fontStyle: dimmed ? FontStyle.italic : FontStyle.normal,
    letterSpacing: 0.4,
  );

  Widget _buildGrid(
    Set<int> dragHighlights, {
    required double gridW,
    required double gridH,
  }) {
    const double pad     = 6.0;
    const double gap     = 4.0;
    const int    cols    = 4;
    const int    rows    = 4;

    final double cellW = (gridW - pad * 2 - gap * (cols - 1)) / cols;
    final double cellH = (gridH - pad * 2 - gap * (rows - 1)) / rows;
    final double ratio = cellW / cellH;

    return KeyedSubtree(
      key: _gridKey,
      child: Container(
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
                borderWidth = isFrame ? 3.0 : 2.4;
                text = _l.slotLabel(type);
              } else if (isFrame) {
                bgColor = kSlotFrame;
                borderColor = kSlotFrameBorder;
                borderWidth = 2.2;
                text = _l.slotLabel(type);
              } else {
                bgColor = kTableGreenMid.withOpacity(0.5);
                borderColor = kSlotDumpBorder;
                borderWidth = 1.0;
              }
            } else {
              final isNumber = card.isNumOrAce;
      
              if (correctRoyal) {
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
      
              if (_moveMode && _moveFromIndex == i && game.phase != Phase.clear) {
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
                ? Center(
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDragTarget
                            ? kDragTargetBorder.withOpacity(0.9)
                            : (isFrame
                                ? kSlotFrameBorder.withOpacity(0.85)
                                : Colors.transparent),
                        height: 1.15,
                      ),
                    ),
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
            final bool shouldDim = game.phase == Phase.clear && !isNumberCard && !_showClearTutorial;
      
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
                      border: Border.all(color: borderColor, width: borderWidth),
                      boxShadow: shadows,
                    ),
                    child: cellContent,
                  ),
                ),
              ),
            );
      
            return DragTarget<CardModel>(
              onWillAcceptWithDetails: (_) => true,
              onAccept: (_) {
                if (_showTutorial || _showClearTutorial) return;
                _unlockAudio();
                if (game.phase != Phase.fill || game.current == null) return;
                _pushUndo();
                final ok = game.tryPlaceAt(i, godMode: _godMode);
                setState(() {});
                if (ok) { HapticFeedback.lightImpact(); _playPlace(); _checkEndState(); }
                else { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_l.snackIllegal))); }
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

  @override
  Widget build(BuildContext context) {
    if (game.phase == Phase.clear && !_hasSeenClearTutorial && !_showTutorial && !_showClearTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _showClearTutorial = true;
            _hasSeenClearTutorial = true;
          });
          _inactivityTimer?.cancel();
          _hintPulseCtrl.stop();
          _hintCurrentCard = false;
          _hintedPair.clear();
          SharedPreferences.getInstance().then((p) => p.setBool('hasSeenClearTutorialV2', true));
        }
      });
    }

    final dragHighlights  = _computeDragHighlights();
    const double deckRowH = 110.0;
    const double innerGap = 6.0;

    // חישוב הזמן (אם המשחק נגמר מציגים את הזמן שעצרנו, אחרת את הזמן הנוכחי)
    final int elapsedSecs = (game.endTime ?? DateTime.now()).difference(game.startTime).inSeconds;

    return Directionality(
      textDirection: _lang == AppLang.he ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: kBurgundy,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: kBurgundyLight,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                text: const TextSpan(children: [
                  TextSpan(text: 'Royal ', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w300, letterSpacing: 1.5, color: kGoldLight)),
                  TextSpan(text: 'Frame', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: kGold)),
                ]),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kGoldDark.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.emoji_events, size: 14, color: kGold), 
                    const SizedBox(width: 4),
                    Text('${game.score}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 12),
                    const Icon(Icons.timer, size: 14, color: kGoldLight), 
                    const SizedBox(width: 4),
                    Text(_formatTime(elapsedSecs), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: _l.menuResume, 
              onPressed: () {
                // אם המשחק כבר נגמר, אין טעם בשאלות - חוזרים ישר לתפריט הראשי
                if (game.phase == Phase.winner || game.phase == Phase.gameOver) {
                  Navigator.pop(context, game);
                } else {
                  // משחק פעיל - מציגים את דיאלוג האזהרה
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: kBurgundyLight,
                      title: Text(_l.dialogHomeTitle, style: const TextStyle(color: kGold)),
                      content: Text(_l.dialogHomeBody, style: const TextStyle(color: Colors.white)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: Text(_l.btnNo, style: const TextStyle(color: kGoldDark))),
                        FilledButton(
                          onPressed: () {
                            Navigator.pop(context); // סוגר את הדיאלוג
                            Navigator.pop(context, game); // סוגר את מסך המשחק
                          },
                          child: Text(_l.btnYes),
                        ),
                      ],
                    ),
                  );
                }
              },
              icon: const Icon(Icons.home, size: 24, color: kGold)
            ),
            // כפתור חזור
            IconButton(
              tooltip: _l.tooltipUndo, 
              onPressed: _undo.isNotEmpty ? _undoAction : null,
              icon: Icon(Icons.undo, size: 22, color: _undo.isNotEmpty ? kGold : kGoldDark)
            ),
            // כפתור משחק חדש (ריפרש)
            IconButton(
              tooltip: _l.tooltipNewGame, 
              onPressed: () => _newGame(),
              icon: const Icon(Icons.refresh, size: 22, color: kGold)
            ),
            // תפריט פעולות נוספות (מנקז אליו את כל שאר הכפתורים)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: kGold),
              color: kBurgundyLight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: kGoldDark.withOpacity(0.5)),
              ),
              onSelected: (value) {
                if (value == 'rules') _showRules();
                else if (value == 'lang') setState(() => _lang = _lang == AppLang.he ? AppLang.en : AppLang.he);
                else if (value == 'mute') setState(() => _isMuted = !_isMuted);
                else if (value == 'debug') setState(() => _showDebugTools = !_showDebugTools);
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem(
                  value: 'rules',
                  child: Row(children: [const Icon(Icons.menu_book_rounded, color: kGold, size: 20), const SizedBox(width: 12), Text(_l.tooltipRules, style: const TextStyle(color: kGoldLight, fontSize: 14))]),
                ),
                PopupMenuItem(
                  value: 'lang',
                  child: Row(children: [const Icon(Icons.language, color: kGold, size: 20), const SizedBox(width: 12), Text(_l.langToggleLabel, style: const TextStyle(color: kGoldLight, fontSize: 14))]),
                ),
                PopupMenuItem(
                  value: 'mute',
                  child: Row(children: [Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: kGold, size: 20), const SizedBox(width: 12), Text(_isMuted ? 'Unmute' : 'Mute', style: const TextStyle(color: kGoldLight, fontSize: 14))]),
                ),
                PopupMenuItem(
                  value: 'debug',
                  child: Row(children: [Icon(_showDebugTools ? Icons.settings : Icons.settings_outlined, color: kGold, size: 20), const SizedBox(width: 12), Text(_showDebugTools ? _l.menuDebugHide : _l.menuDebugShow, style: const TextStyle(color: kGoldLight, fontSize: 14))]),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
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
                        padding: const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 28),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final double totalH = constraints.maxHeight;
                            final double totalW = constraints.maxWidth;

                            final double gridH = totalH - deckRowH - innerGap;
                            final double gridW = totalW.clamp(0.0, gridH * 1.4);

                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedOpacity(
                                  duration: const Duration(milliseconds: 450),
                                  curve: Curves.easeInOut,
                                  opacity: (game.phase == Phase.clear && !_showClearTutorial) ? 0.35 : 1.0,
                                  child: SizedBox(
                                    height: deckRowH,
                                    child: Center(child: _deckRow()),
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

                if (game.phase == Phase.winner) _buildWinnerOverlay(),

                if (game.phase == Phase.gameOver && _showGameOverOverlay)
                  _buildGameOverOverlay(),

                if (_showTutorial)
                  TutorialOverlay(
                    lang: _lang,
                    deckRowKey: _deckRowKey,
                    gridKey: _gridKey,
                    cellKeys: _cellKeys,
                    isClearPhase: false,
                    onFinish: () {
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
                    onFinish: () {
                      setState(() => _showClearTutorial = false);
                      _restartHintTimer();
                    },
                  ),

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

  Widget _buildWinnerOverlay() {
    // קודם כל: חישובי הניקוד הסופיים
    final int baseScore = game.score;
    const int winBonus  = 1000;
    final int drawnWhenFilled = game.cardsDrawnWhenFrameFilled ?? 52;
    final int effBonus  = max(0, (52 - drawnWhenFilled) * 50);
    final int seconds   = (game.endTime ?? DateTime.now()).difference(game.startTime).inSeconds;
    final int speedBonus = max(0, 5000 - (seconds * 5));
    final int totalScore = baseScore + winBonus + effBonus + speedBonus;

    // התיקון: רק עכשיו, כשיש לנו את הניקוד המלא, שולחים לענן
    DbService().updatePlayerStats(totalScore, true);

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
            Text(_l.winTitle, style: const TextStyle(color: kGold, fontSize: 26,
                fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 8),
            
            // פירוט החשבונית המלכותית
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kGoldDark.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  _scoreRow(_l.winBaseScore, '+$baseScore'),
                  _scoreRow(_l.effBonus, '+$effBonus'),
                  _scoreRow(_l.speedBonus, '+$speedBonus'),
                  _scoreRow(_l.winBonus, '+$winBonus', isGold: true),
                  const Divider(color: kGoldDark, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_l.totalScore, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('$totalScore', style: const TextStyle(color: kGold, fontSize: 20, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ],
              ),
            ),
            
            FilledButton.icon(onPressed: () => _newGame(),
                icon: const Icon(Icons.refresh), label: Text(_l.winBtn)),
          ]),
        ),
      ),
    );
  }

  Widget _scoreRow(String title, String value, {bool isGold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          Text(value, style: TextStyle(color: isGold ? kGold : kGoldLight, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    DbService().updatePlayerStats(game.score, false);
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

// ─────────────────────────────────────────────────────────────────────────────
// UI HELPERS (Tags & Flying Cards)
// ─────────────────────────────────────────────────────────────────────────────
class DeckTag extends StatelessWidget {
  final String text;
  const DeckTag({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: kBurgundy.withOpacity(0.82),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: kGoldDark.withOpacity(0.6), width: 0.8),
      ),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: const TextStyle(
          color: kGoldLight,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          height: 1.25,
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