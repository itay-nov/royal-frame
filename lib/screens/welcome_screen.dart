import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme_constants.dart';
import '../utils/localization.dart';
import '../services/auth_service.dart';
import 'main_menu_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  // הגדרנו אנגלית כדי להפוך את הכל ל-Clean
  final AppLang _lang = AppLang.en; 
  L get _l => L(_lang);

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _startGame() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playerName', name);

    await _authService.signInAnonymously(name);

    setState(() {
      _isLoading = false;
    });

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainMenuScreen()),
    );
  }

  void _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userCred = await _authService.signInWithGoogle();

      if (userCred != null) {
        final name = userCred.user?.displayName ?? 'Player';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('playerName', name);

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainMenuScreen()),
        );
      } else {
        setState(() {
          _isLoading = false;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google Login cancelled by user.', style: TextStyle(color: Colors.white)),
            backgroundColor: kBurgundyLight,
          ),
        );
      }
    } catch (e) {
      // התיקון: נדפיס את השגיאה האמיתית כדי שנדע מה הבעיה
      setState(() {
        _isLoading = false;
      });
      print('DEBUG - Error during Google Login catch: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('DEBUG ERROR: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBurgundy,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('👑', style: TextStyle(fontSize: 80)),
              const SizedBox(height: 16),
              const Text(
                'ROYAL FRAME',
                style: TextStyle(
                  color: kGold,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 60),
              
              // שדה הזנת השם - הפכנו את הhintText לאנגלית
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: kGoldLight, fontSize: 18),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'Enter your name for Guest Login', 
                  hintStyle: TextStyle(color: kGoldDark.withOpacity(0.5)),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: kGoldDark),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: kGold, width: 2),
                  ),
                ),
                onSubmitted: (_) => _startGame(),
              ),
              const SizedBox(height: 40),
              
              _isLoading
                  ? const CircularProgressIndicator(color: kGold)
                  : Column(
                      children: [
                        // כפתור המשחק כאורח - הפכנו לאנגלית
                        FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                            backgroundColor: kBurgundyLight,
                            side: const BorderSide(color: kGold, width: 1),
                          ),
                          onPressed: _startGame,
                          child: const Text('Play as Guest', style: TextStyle(fontSize: 18, color: kGold)),
                        ),
                        
                        const SizedBox(height: 24),
                        const Text('— OR —', style: TextStyle(color: kGoldDark, fontSize: 14)),
                        const SizedBox(height: 24),
                        
                        // כפתור ההתחברות עם גוגל המעוצב
                        _buildGoogleSignInButton(),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // הפונקציה ליצירת כפתור גוגל נקי ומלכותי
  Widget _buildGoogleSignInButton() {
    return GestureDetector(
      onTap: _signInWithGoogle,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.black45, // רקע שחור עדין
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kGold.withOpacity(0.5), width: 1), // מסגרת זהב עדינה
          boxShadow: [BoxShadow(color: kGold.withOpacity(0.1), blurRadius: 10, spreadRadius: 1)],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min, // שיתאים לטקסט
          children: [
            // התיקון: G פשוטה, נקייה ומלכותית במקום תמונה מהרשת
            Text(
              'G',
              style: TextStyle(fontSize: 26, color: Colors.white, fontWeight: FontWeight.w900, fontFamily: 'Georgia'),
            ),
            const SizedBox(width: 16),
            const Text(
              'Connect with Google', 
              style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}