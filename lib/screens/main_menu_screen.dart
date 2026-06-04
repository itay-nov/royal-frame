import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme_constants.dart';
import '../models/game_model.dart';
import '../utils/localization.dart';
import 'board_screen.dart';
import 'welcome_screen.dart';
import '../services/db_service.dart';
import '../services/auth_service.dart';
import '../models/player_model.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  String _playerName = '';
  GameState? _activeGame; 
  final AppLang _lang = AppLang.en;
  L get _l => L(_lang);

  @override
  void initState() {
    super.initState();
    _loadPlayerName();
  }

  Future<void> _loadPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _playerName = prefs.getString('playerName') ?? 'Guest';
    });
  }

  void _startOrResumeGame({bool isResume = false}) async {
    final returnedGame = await Navigator.of(context).push<GameState>(
      MaterialPageRoute(
        builder: (_) => BoardScreen(existingGame: isResume ? _activeGame : null),
      ),
    );
    
    setState(() {
      if (returnedGame != null && returnedGame.phase != Phase.winner && returnedGame.phase != Phase.gameOver) {
        _activeGame = returnedGame;
      } else {
        _activeGame = null;
      }
    });
  }

  void _showLeaderboard() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: kBurgundyLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: kGold, width: 2)),
        child: SizedBox(
          width: 400,
          height: 500,
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  indicatorColor: kGold,
                  labelColor: kGold,
                  unselectedLabelColor: kGoldDark,
                  tabs: [
                    Tab(text: _l.tabHighScore, icon: const Icon(Icons.emoji_events)),
                    Tab(text: _l.tabTotalScore, icon: const Icon(Icons.stars)),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildLeaderboardList(isTotalScore: false), // טאב שיא משחק בודד
                      _buildLeaderboardList(isTotalScore: true),  // טאב סך הכל מצטבר
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboardList({required bool isTotalScore}) {
    return FutureBuilder<List<PlayerModel>>(
      future: DbService().getLeaderboard(orderBy: isTotalScore ? 'totalScore' : 'highScore'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: kGold));
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text('שגיאה בטעינת הנתונים', style: TextStyle(color: Colors.white)),
          );
        }

        final players = snapshot.data ?? [];
        if (players.isEmpty) {
          return const Center(
            child: Text('אין עדיין נתונים בטבלה', style: TextStyle(color: Colors.white)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: players.length,
          itemBuilder: (context, index) {
            final player = players[index];
            final isTop3 = index < 3;
            
            final scoreToDisplay = isTotalScore ? player.totalScore : player.highScore;
            
            return Card(
              color: Colors.black45,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: isTop3 ? kGold : kGoldDark.withOpacity(0.3)),
              ),
              child: ListTile(
                leading: Text('#${index + 1}', style: TextStyle(color: isTop3 ? kGoldLight : Colors.white54, fontSize: 18, fontWeight: FontWeight.bold)),
                title: Text(player.displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('Wins: ${player.wins} | Games: ${player.totalGames}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: Text('$scoreToDisplay', style: const TextStyle(color: kGold, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBurgundy,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('👑', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 8),
            const Text('ROYAL FRAME', style: TextStyle(color: kGold, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 3)),
            const SizedBox(height: 24),
            Text(_l.welcomeBack(_playerName), style: const TextStyle(color: kGoldLight, fontSize: 18)),
            const SizedBox(height: 48),
            
            if (_activeGame != null) ...[
              _buildMenuButton(_l.menuResume, Icons.play_arrow, () => _startOrResumeGame(isResume: true), isHighlight: true),
              const SizedBox(height: 16),
            ],
            
            _buildMenuButton(_l.menuNewGame, Icons.add_circle_outline, () => _startOrResumeGame(isResume: false)),
            const SizedBox(height: 16),
            _buildMenuButton(_l.menuLeaderboard, Icons.leaderboard, _showLeaderboard),
            const SizedBox(height: 16),
            
            TextButton.icon(
              onPressed: () async {
                // התיקון: מתנתקים רשמית מפיירבייס כדי שהשחקן הבא יקבל חשבון אנונימי חדש לגמרי
                await AuthService().signOut();
                if (!mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                );
              },
              icon: const Icon(Icons.person, color: kGoldDark),
              label: Text(_l.menuChangePlayer, style: const TextStyle(color: kGoldDark)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(String text, IconData icon, VoidCallback onPressed, {bool isHighlight = false}) {
    return SizedBox(
      width: 260,
      height: 50,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: isHighlight ? const Color(0xFF2A5C1A) : kBurgundyLight,
          foregroundColor: kGold,
          side: BorderSide(color: isHighlight ? kSlotFrameBorder : kGold, width: isHighlight ? 2 : 1),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(text, style: const TextStyle(fontSize: 16, letterSpacing: 1)),
      ),
    );
  }
}