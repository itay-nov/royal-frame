import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme_constants.dart';
import '../models/game_model.dart';
import '../utils/localization.dart';
import 'board_screen.dart';
import 'duel_setup_screen.dart';
import 'welcome_screen.dart';
import '../services/db_service.dart';
import '../services/auth_service.dart';
import '../services/haptic_service.dart';
import '../services/streak_service.dart';
import '../services/tutorial_manager.dart';
import '../models/player_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MAIN MENU
// ─────────────────────────────────────────────────────────────────────────────
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  String _playerName = '';
  GameState? _activeGame;
  AppLang _lang = AppLang.en;
  L get _l => L(_lang);

  static const String _mutePrefKey = 'royalFrameMuted';
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _loadPlayerName();
    _loadMuteState();
    _loadSavedLang();
    HapticService.load();
    _loadStreak();
    // Sync tutorial status from Firestore so veteran users never re-see the
    // tutorial after a fresh install or local-storage wipe.
    TutorialManager.syncFromFirestore();
  }

  Future<void> _loadStreak() async {
    await StreakService.load();
    if (!mounted) return;
    setState(() {});
    if (StreakService.justExtended && StreakService.streak > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showStreakDialog());
    }
  }

  void _showStreakDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _StreakDialog(
        streak: StreakService.streak,
        lang: _lang,
      ),
    );
  }

  Future<void> _loadSavedLang() async {
    final lang = await L.loadLang();
    if (!mounted) return;
    setState(() => _lang = lang);
  }

  Future<void> _loadPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _playerName = prefs.getString('playerName') ?? 'Guest';
    });
  }

  Future<void> _loadMuteState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isMuted = prefs.getBool(_mutePrefKey) ?? false;
    });
  }

  Future<void> _toggleMute() async {
    final prefs = await SharedPreferences.getInstance();
    final newValue = !_isMuted;
    await prefs.setBool(_mutePrefKey, newValue);
    if (!mounted) return;
    setState(() => _isMuted = newValue);
  }

  Future<void> _toggleHaptic() async {
    await HapticService.setEnabled(!HapticService.isEnabled);
    if (mounted) setState(() {});
  }

  void _startOrResumeGame({bool isResume = false}) async {
    final returnedGame = await Navigator.of(context).push<GameState>(
      MaterialPageRoute(
        builder: (_) =>
            BoardScreen(
              existingGame: isResume ? _activeGame : null,
              showNewGamePicker: !isResume,
              initialLang: _lang,
            ),
      ),
    );

    setState(() {
      if (returnedGame != null &&
          returnedGame.phase != Phase.winner &&
          returnedGame.phase != Phase.gameOver) {
        _activeGame = returnedGame;
      } else {
        _activeGame = null;
      }
    });
  }

  void _startTutorial() async {
    final returnedGame = await Navigator.of(context).push<GameState>(
      MaterialPageRoute(
        builder: (_) =>
            BoardScreen(existingGame: _activeGame, forceTutorial: true, initialLang: _lang),
      ),
    );

    setState(() {
      if (returnedGame != null &&
          returnedGame.phase != Phase.winner &&
          returnedGame.phase != Phase.gameOver) {
        _activeGame = returnedGame;
      } else {
        _activeGame = null;
      }
    });
  }

  void _showLeaderboard() {
    showDialog(
      context: context,
      builder: (_) => const _LeaderboardDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBurgundy,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: kBurgundyLight,
        titleSpacing: 12,
        title: Row(
          children: [
            if (_lang == AppLang.he)
              RichText(
                textDirection: TextDirection.rtl,
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'Royal Frame\n',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        color: kGold,
                        height: 1.0,
                      ),
                    ),
                    TextSpan(
                      text: 'משחק הקלפים המלכותי',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.5,
                        color: kGoldLight,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              )
            else
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'Royal\n',
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
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        color: kGold,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            _buildLangToggle(),
            IconButton(
              tooltip: _isMuted ? 'Unmute' : 'Mute',
              icon: Icon(
                _isMuted ? Icons.volume_off : Icons.volume_up,
                color: kGold,
              ),
              onPressed: _toggleMute,
            ),
            IconButton(
              tooltip: HapticService.isEnabled
                  ? 'Vibration: On'
                  : 'Vibration: Off',
              icon: Icon(
                HapticService.isEnabled
                    ? Icons.vibration
                    : Icons.phonelink_erase,
                color: HapticService.isEnabled ? kGold : kGoldDark,
              ),
              onPressed: _toggleHaptic,
            ),
          ],
        ),
      ),
      body: Directionality(
        textDirection:
            _lang == AppLang.he ? TextDirection.rtl : TextDirection.ltr,
        child: SingleChildScrollView(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              const Text('👑', style: TextStyle(fontSize: 60)),
              const SizedBox(height: 8),
              const Text(
                'ROYAL FRAME',
                style: TextStyle(
                  color: kGold,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _l.welcomeBack(_playerName),
                style: const TextStyle(color: kGoldLight, fontSize: 18),
              ),
              const SizedBox(height: 16),
              _StreakBadge(streak: StreakService.streak, lang: _lang),
              const SizedBox(height: 32),

              if (_activeGame != null) ...[
                _buildMenuButton(
                  _l.menuResume,
                  Icons.play_arrow,
                  () => _startOrResumeGame(isResume: true),
                  isHighlight: true,
                ),
                const SizedBox(height: 16),
              ],

              _buildMenuButton(
                _l.menuNewGame,
                Icons.add_circle_outline,
                () => _startOrResumeGame(isResume: false),
              ),
              const SizedBox(height: 16),
              _buildMenuButton(
                _l.menuLeaderboard,
                Icons.leaderboard,
                _showLeaderboard,
              ),
              const SizedBox(height: 16),
              _buildMenuButton(
                _l.menuTutorial,
                Icons.school_outlined,
                _startTutorial,
              ),
              const SizedBox(height: 16),
              _buildMenuButton(
                _l.menuDuelMode,
                Icons.sports_kabaddi,
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DuelSetupScreen(lang: _lang),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              TextButton.icon(
                onPressed: () async {
                  await AuthService().signOut();
                  if (!mounted) return;
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  );
                },
                icon: const Icon(Icons.person, color: kGoldDark),
                label: Text(
                  _l.menuChangePlayer,
                  style: const TextStyle(color: kGoldDark),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildLangToggle() {
    final targetLabel = _lang == AppLang.he ? 'English' : 'עברית';
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.black.withOpacity(0.35),
        foregroundColor: kGold,
        side: const BorderSide(color: kGold, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      onPressed: () {
        final newLang = _lang == AppLang.he ? AppLang.en : AppLang.he;
        setState(() => _lang = newLang);
        L.saveLang(newLang);
      },
      icon: const Icon(Icons.language, size: 18, color: kGold),
      label: Text(
        targetLabel,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: kGold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    String text,
    IconData icon,
    VoidCallback onPressed, {
    bool isHighlight = false,
  }) {
    return SizedBox(
      width: 260,
      height: 50,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: isHighlight
              ? const Color(0xFF2A5C1A)
              : kBurgundyLight,
          foregroundColor: kGold,
          side: BorderSide(
            color: isHighlight ? kSlotFrameBorder : kGold,
            width: isHighlight ? 2 : 1,
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(
          text,
          style: const TextStyle(fontSize: 16, letterSpacing: 1),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STREAK BADGE  (shown inline in the menu)
// ─────────────────────────────────────────────────────────────────────────────
class _StreakBadge extends StatelessWidget {
  final int streak;
  final AppLang lang;
  const _StreakBadge({required this.streak, required this.lang});

  @override
  Widget build(BuildContext context) {
    if (streak <= 0) return const SizedBox.shrink();
    final isHe = lang == AppLang.he;
    final label = isHe ? 'יום $streak ברצף 🔥' : '🔥 $streak-day streak';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: kBurgundyLight,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: kGold.withOpacity(0.7), width: 1.5),
        boxShadow: [BoxShadow(color: kGold.withOpacity(0.15), blurRadius: 10)],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: kGold,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STREAK DIALOG  (shown on new-day login)
// ─────────────────────────────────────────────────────────────────────────────
class _StreakDialog extends StatelessWidget {
  final int streak;
  final AppLang lang;
  const _StreakDialog({required this.streak, required this.lang});

  @override
  Widget build(BuildContext context) {
    final isHe = lang == AppLang.he;
    final title = isHe ? 'רצף יומי! 🔥' : 'Daily Streak! 🔥';
    final body  = isHe
        ? 'כל הכבוד! $streak ימים ברצף.\nהמשך לשחק כדי לא לאבד את הרצף!'
        : 'Amazing! $streak days in a row.\nKeep playing to protect your streak!';
    final btn   = isHe ? 'יאללה!' : "Let's go!";

    return Dialog(
      backgroundColor: kBurgundyLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🔥', style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kGold,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kGoldLight,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(btn),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEADERBOARD DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _LeaderboardDialog extends StatelessWidget {
  const _LeaderboardDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kBurgundyLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kGold, width: 2),
      ),
      child: SizedBox(
        width: 420,
        height: 560,
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events, color: kGold, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Leaderboard',
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
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.close, color: kGoldDark, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TabBar(
                indicatorColor: kGold,
                labelColor: kGold,
                unselectedLabelColor: kGoldDark,
                tabs: const [
                  Tab(icon: Icon(Icons.emoji_events), text: 'High Score'),
                  Tab(icon: Icon(Icons.military_tech), text: 'Most Wins'),
                  Tab(icon: Icon(Icons.stars), text: 'Total Score'),
                ],
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _LeaderboardTabContent(orderBy: 'highScore'),
                    _LeaderboardTabContent(orderBy: 'wins'),
                    _LeaderboardTabContent(orderBy: 'totalScore'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEADERBOARD TAB CONTENT — handles pagination & user anchoring
// ─────────────────────────────────────────────────────────────────────────────
class _LeaderboardTabContent extends StatefulWidget {
  final String orderBy;
  const _LeaderboardTabContent({required this.orderBy});

  @override
  State<_LeaderboardTabContent> createState() => _LeaderboardTabContentState();
}

class _LeaderboardTabContentState extends State<_LeaderboardTabContent>
    with AutomaticKeepAliveClientMixin {
  // Keep each tab's state alive while switching between tabs.
  @override
  bool get wantKeepAlive => true;

  static const int _initialLimit = 10;
  static const int _moreLimit = 50;

  List<PlayerModel> _players = [];
  QueryDocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  PlayerModel? _currentUserData;
  int _currentUserRank = 0;
  final String? _currentUid = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loadingInitial = true;
      _error = null;
    });

    try {
      final db = DbService();

      // Fire all three requests concurrently.
      final pageFuture = db.getLeaderboardPage(
        orderBy: widget.orderBy,
        limit: _initialLimit,
      );
      final userDataFuture = db.getCurrentUserData();
      final rankFuture = _currentUid != null
          ? db.getUserRank(uid: _currentUid!, orderBy: widget.orderBy)
          : Future<int>.value(0);

      final page = await pageFuture;
      final userData = await userDataFuture;
      final rank = await rankFuture;

      if (!mounted) return;
      setState(() {
        _players = page.players;
        _lastDoc = page.lastDocument;
        _hasMore = page.players.length >= _initialLimit &&
            page.lastDocument != null;
        _currentUserData = userData;
        _currentUserRank = rank;
        _loadingInitial = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingInitial = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _lastDoc == null || !_hasMore) return;

    setState(() => _loadingMore = true);

    try {
      final page = await DbService().getLeaderboardNextPage(
        lastDocument: _lastDoc!,
        orderBy: widget.orderBy,
        limit: _moreLimit,
      );

      if (!mounted) return;
      setState(() {
        _players.addAll(page.players);
        _lastDoc = page.lastDocument;
        _hasMore = page.players.length >= _moreLimit &&
            page.lastDocument != null;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  bool get _currentUserInList =>
      _currentUid != null &&
      _players.any((p) => p.uid == _currentUid);

  bool get _shouldShowAnchor =>
      _currentUserData != null &&
      _currentUserRank > 0 &&
      !_currentUserInList;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loadingInitial) {
      return const Center(child: CircularProgressIndicator(color: kGold));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, color: kGoldDark, size: 36),
              const SizedBox(height: 12),
              const Text(
                'Could not load leaderboard',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loadInitial,
                child: const Text(
                  'Retry',
                  style: TextStyle(color: kGold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_players.isEmpty) {
      return const Center(
        child: Text(
          'No data yet — play a game!',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      // extra items: optional separator row, optional anchor row, load-more button
      itemCount: _players.length +
          (_shouldShowAnchor ? 2 : 0) + // separator + anchor
          1, // load-more / end label
      itemBuilder: (context, index) {
        // ── Regular player rows ──────────────────────────────────────────
        if (index < _players.length) {
          return _buildPlayerRow(
            player: _players[index],
            rank: index + 1,
          );
        }

        final extra = index - _players.length;

        // ── Separator + anchor (only when user is off-screen) ────────────
        if (_shouldShowAnchor) {
          if (extra == 0) return _buildSeparator();
          if (extra == 1) {
            return _buildPlayerRow(
              player: _currentUserData!,
              rank: _currentUserRank,
              isAnchor: true,
            );
          }
        }

        // ── Load-more button / end label ─────────────────────────────────
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _hasMore
              ? Center(
                  child: _loadingMore
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: kGold,
                            strokeWidth: 2,
                          ),
                        )
                      : OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kGoldLight,
                            side: const BorderSide(color: kGoldDark),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                          ),
                          onPressed: _loadMore,
                          icon: const Icon(Icons.expand_more, size: 18),
                          label: const Text(
                            'Load 50 More Players',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                )
              : const Center(
                  child: Text(
                    '— end of leaderboard —',
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildPlayerRow({
    required PlayerModel player,
    required int rank,
    bool isAnchor = false,
  }) {
    final isCurrentUser = player.uid == _currentUid;
    final isTop3 = rank <= 3 && !isAnchor;
    final score = widget.orderBy == 'totalScore'
        ? player.totalScore
        : widget.orderBy == 'wins'
            ? player.wins
            : player.highScore;

    // Medal emoji for top 3
    final String rankLabel;
    if (rank == 1) {
      rankLabel = '🥇';
    } else if (rank == 2) {
      rankLabel = '🥈';
    } else if (rank == 3) {
      rankLabel = '🥉';
    } else {
      rankLabel = '#$rank';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? kGold.withOpacity(0.10)
            : Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrentUser
              ? kGold
              : (isTop3 ? kGoldDark : Colors.white12),
          width: isCurrentUser ? 2.0 : 1.0,
        ),
        boxShadow: isCurrentUser
            ? [
                BoxShadow(
                  color: kGold.withOpacity(0.18),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: SizedBox(
          width: 36,
          child: Center(
            child: Text(
              rankLabel,
              style: TextStyle(
                color: isTop3 ? kGoldLight : Colors.white54,
                fontSize: rank <= 3 ? 20 : 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                player.displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isCurrentUser ? kGold : Colors.white,
                  fontWeight: isCurrentUser
                      ? FontWeight.w900
                      : FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            if (isCurrentUser)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: kGold.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: kGold.withOpacity(0.55)),
                ),
                child: const Text(
                  'YOU',
                  style: TextStyle(
                    color: kGold,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          'Wins: ${player.wins}  ·  Games: ${player.totalGames}',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        trailing: Text(
          _formatScore(score),
          style: TextStyle(
            color: isCurrentUser ? kGold : kGoldLight,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: kGoldDark.withOpacity(0.35),
              thickness: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '·  ·  ·',
              style: TextStyle(
                color: kGoldDark.withOpacity(0.55),
                fontSize: 16,
                letterSpacing: 4,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: kGoldDark.withOpacity(0.35),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  String _formatScore(int score) {
    if (score >= 1000000) return '${(score / 1000000).toStringAsFixed(1)}M';
    if (score >= 1000) return '${(score / 1000).toStringAsFixed(1)}K';
    return '$score';
  }
}
