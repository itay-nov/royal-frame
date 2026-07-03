import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme_constants.dart';
import '../utils/localization.dart';
import '../services/auth_service.dart';
import '../services/db_service.dart';
import 'main_menu_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────
const double _kButtonWidth = 280.0;
const double _kButtonHeight = 52.0;
const double _kButtonRadius = 10.0;
const double _kIconSize = 22.0;
const double _kLabelFontSize = 16.0;

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  AppLang _lang = AppLang.en;
  L get _l => L(_lang);

  // Title entrance animation
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _loadSavedLang();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  Future<void> _loadSavedLang() async {
    final lang = await L.loadLang();
    if (!mounted) return;
    setState(() => _lang = lang);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ─── Navigation helper ────────────────────────────────────────────────────

  void _goToMainMenu() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainMenuScreen()),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.red.shade800,
      ),
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: kBurgundyLight,
      ),
    );
  }

  // ─── Guest login ──────────────────────────────────────────────────────────

  void _startGame() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError('Please enter a name');
      return;
    }

    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playerName', name);
    final credential = await _authService.signInAnonymously(name);

    // Create the player document immediately so a guest who hasn't finished
    // a game yet still has a valid backend record. This keeps the startup
    // session validation from treating them as stale on the next launch.
    final uid = credential?.user?.uid;
    if (uid != null) {
      await DbService().ensurePlayerDoc(uid, name);
    }

    setState(() => _isLoading = false);
    _goToMainMenu();
  }

  // ─── Google login ─────────────────────────────────────────────────────────

  void _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final userCred = await _authService.signInWithGoogle();

      if (userCred != null) {
        final name = userCred.user?.displayName ?? 'Player';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('playerName', name);
        _goToMainMenu();
      } else {
        setState(() => _isLoading = false);
        _showInfo('Google Login cancelled by user.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('DEBUG ERROR: $e');
    }
  }

  // ─── Apple login (hidden, preserved for future use) ───────────────────────

  void _signInWithApple() async {
    setState(() => _isLoading = true);
    try {
      final userCred = await _authService.signInWithApple();
      if (userCred != null) {
        final name =
            userCred.user?.displayName ??
            userCred.user?.email?.split('@').first ??
            'Player';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('playerName', name);
        _goToMainMenu();
      } else {
        setState(() => _isLoading = false);
        _showInfo('Apple Login cancelled or failed.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('DEBUG ERROR: $e');
    }
  }

  // ─── Phone login ──────────────────────────────────────────────────────────

  void _signInWithPhone() async {
    final phone = await _showPhoneInputDialog();
    if (phone == null || phone.isEmpty) return;

    setState(() => _isLoading = true);

    if (kIsWeb) {
      await _handlePhoneWeb(phone);
    } else {
      await _handlePhoneNative(phone);
    }
  }

  /// Web path: Firebase handles reCAPTCHA internally.
  Future<void> _handlePhoneWeb(String phoneNumber) async {
    final confirmationResult = await _authService.sendSmsCodeWeb(phoneNumber);

    setState(() => _isLoading = false);

    if (confirmationResult == null) {
      _showError(
        'Failed to send verification code. Check the number and try again.',
      );
      return;
    }

    final smsCode = await _showSmsCodeDialog();
    if (smsCode == null || smsCode.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userCred = await _authService.confirmSmsCodeWeb(
        confirmationResult,
        smsCode,
      );
      if (userCred != null) {
        await _savePhonePlayerAndNavigate(userCred);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      _showError(e.message ?? 'Invalid verification code.');
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Verification failed: $e');
    }
  }

  /// Native (Android / iOS) path.
  Future<void> _handlePhoneNative(String phoneNumber) async {
    String? verificationId;
    bool autoVerified = false;

    await _authService.sendSmsCodeNative(
      phoneNumber: phoneNumber,
      onCodeSent: (id, _) {
        verificationId = id;
      },
      onAutoVerified: (userCred) async {
        autoVerified = true;
        await _savePhonePlayerAndNavigate(userCred);
      },
      onError: (error) {
        setState(() => _isLoading = false);
        _showError(error);
      },
    );

    if (autoVerified) return;

    setState(() => _isLoading = false);

    if (verificationId == null) return;

    final smsCode = await _showSmsCodeDialog();
    if (smsCode == null || smsCode.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userCred = await _authService.confirmSmsCodeNative(
        verificationId: verificationId!,
        smsCode: smsCode,
      );
      if (userCred != null) {
        await _savePhonePlayerAndNavigate(userCred);
      } else {
        setState(() => _isLoading = false);
        _showError('Verification failed. Please try again.');
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      _showError(e.message ?? 'Invalid verification code.');
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Verification failed: $e');
    }
  }

  /// Called after every successful phone sign-in (both web & native).
  ///
  /// Phone auth never provides a display name, so we check if one is
  /// missing (null, empty, or the generic "player" fallback) and show a
  /// mandatory name-picker dialog before proceeding to the main menu.
  Future<void> _savePhonePlayerAndNavigate(UserCredential userCred) async {
    final user = userCred.user;
    final existingName = user?.displayName ?? '';

    final needsName =
        existingName.isEmpty ||
        existingName.toLowerCase() == 'player';

    if (needsName) {
      setState(() => _isLoading = false);

      final chosenName = await _showPlayerNameDialog();
      if (!mounted) return;

      // User dismissed the dialog without providing a name — abort login.
      if (chosenName == null || chosenName.trim().isEmpty) return;

      setState(() => _isLoading = true);

      // Persist the name in Firebase Auth + Firestore.
      await user?.updateDisplayName(chosenName.trim());
      if (user != null) {
        await DbService().updateDisplayName(user.uid, chosenName.trim());
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playerName', chosenName.trim());
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playerName', existingName);
    }

    setState(() => _isLoading = false);
    _goToMainMenu();
  }

  // ─── Dialogs ──────────────────────────────────────────────────────────────

  Future<String?> _showPhoneInputDialog() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) => _RoyalDialog(
        title: 'Phone Number',
        subtitle: 'Enter in international format',
        hintText: '+972 50 123 4567',
        controller: ctrl,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[+\d\s\-]')),
        ],
        confirmLabel: 'Send Code',
        onConfirm: () => Navigator.of(ctx).pop(ctrl.text.trim()),
        onCancel: () => Navigator.of(ctx).pop(null),
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<String?> _showSmsCodeDialog() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) => _RoyalDialog(
        title: 'Verification Code',
        subtitle: 'Enter the 6-digit code sent to your phone',
        hintText: '000000',
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        confirmLabel: 'Verify',
        onConfirm: () => Navigator.of(ctx).pop(ctrl.text.trim()),
        onCancel: () => Navigator.of(ctx).pop(null),
      ),
    );
    ctrl.dispose();
    return result;
  }

  /// Mandatory name-picker shown after phone sign-in.
  /// [barrierDismissible] is false so the user must pick a name or cancel.
  Future<String?> _showPlayerNameDialog() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) => _RoyalDialog(
        title: 'Choose Your Name',
        subtitle: 'This will be your name on the leaderboard',
        hintText: 'e.g. King Arthur',
        controller: ctrl,
        keyboardType: TextInputType.name,
        inputFormatters: [LengthLimitingTextInputFormatter(20)],
        confirmLabel: 'Confirm',
        onConfirm: () {
          final name = ctrl.text.trim();
          if (name.isNotEmpty) Navigator.of(ctx).pop(name);
        },
        onCancel: () => Navigator.of(ctx).pop(null),
      ),
    );
    ctrl.dispose();
    return result;
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  void _toggleLang() {
    final newLang = _lang == AppLang.he ? AppLang.en : AppLang.he;
    setState(() => _lang = newLang);
    L.saveLang(newLang);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBurgundy,
      body: Stack(
        children: [
          // ── Subtle radial glow decoration ──────────────────────────────────
          Positioned(
            top: -80,
            left: -60,
            child: _glowCircle(340),
          ),
          Positioned(
            bottom: -100,
            right: -80,
            child: _glowCircle(380),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Animated title block ─────────────────────────────────
                  AnimatedOpacity(
                    opacity: _visible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 600),
                    child: AnimatedSlide(
                      offset: _visible ? Offset.zero : const Offset(0, -0.15),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOut,
                      child: Column(
                        children: [
                          const Text('👑', style: TextStyle(fontSize: 80)),
                          const SizedBox(height: 12),
                          const Text(
                            'ROYAL FRAME',
                            style: TextStyle(
                              color: kGold,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // ── Card suit symbols ──────────────────────────
                          const Text(
                            '♠  ♥  ♦  ♣',
                            style: TextStyle(
                              color: kGold,
                              fontSize: 18,
                              letterSpacing: 6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // ── Tagline ────────────────────────────────────
                          Text(
                            _l.welcomeTagline,
                            style: const TextStyle(
                              fontSize: 13,
                              color: kGoldDark,
                              letterSpacing: 1.5,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 56),

                  SizedBox(
                    width: _kButtonWidth,
                    child: TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(color: kGoldLight, fontSize: 17),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: _l.welcomeHint,
                        hintStyle: TextStyle(
                          color: kGoldDark.withOpacity(0.55),
                          fontSize: 15,
                        ),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: kGoldDark),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: kGold, width: 2),
                        ),
                      ),
                      onSubmitted: (_) => _startGame(),
                    ),
                  ),

                  const SizedBox(height: 28),

                  _isLoading
                      ? const CircularProgressIndicator(color: kGold)
                      : _buildButtonGroup(),
                ],
              ),
            ),
          ),
          // Prominent language toggle pinned to top-right
          Positioned(
            top: 48,
            right: 16,
            child: _buildLangToggle(),
          ),
        ],
      ),
    );
  }

  Widget _glowCircle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kGold.withOpacity(0.04),
      ),
    );
  }

  Widget _buildLangToggle() {
    // Shows the *target* language (the one you'll switch TO) so the player
    // instantly sees "עברית" if the app is in English, or "English" if in Hebrew.
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
      onPressed: _toggleLang,
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

  // ─── Button group ──────────────────────────────────────────────────────────

  Widget _buildButtonGroup() {
    return Column(
      children: [
        _buildPrimaryButton(label: 'Play as Guest', onPressed: _startGame),

        const SizedBox(height: 28),
        _buildOrDivider(),
        const SizedBox(height: 24),

        _buildSocialLoginButton(
          label: 'Continue with Google',
          icon: _buildGoogleIcon(),
          onPressed: _signInWithGoogle,
        ),

        const SizedBox(height: 14),

        _buildSocialLoginButton(
          label: 'Continue with Phone',
          icon: const Icon(Icons.phone, size: _kIconSize, color: Colors.white),
          onPressed: _signInWithPhone,
        ),
      ],
    );
  }

  // ─── Reusable button builders ─────────────────────────────────────────────

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: _kButtonWidth,
      height: _kButtonHeight,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: kBurgundyLight,
          side: const BorderSide(color: kGold, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_kButtonRadius),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: _kLabelFontSize,
            fontWeight: FontWeight.w700,
            color: kGold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildSocialLoginButton({
    required String label,
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: _kButtonWidth,
      height: _kButtonHeight,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          backgroundColor: Colors.black.withOpacity(0.30),
          foregroundColor: Colors.white,
          side: const BorderSide(color: kGoldDark, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_kButtonRadius),
          ),
        ),
        onPressed: onPressed,
        icon: SizedBox(
          width: _kIconSize,
          height: _kIconSize,
          child: Center(child: icon),
        ),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: _kLabelFontSize,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildOrDivider() {
    return SizedBox(
      width: _kButtonWidth,
      child: Row(
        children: [
          Expanded(
            child: Divider(color: kGoldDark.withOpacity(0.45), thickness: 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'OR',
              style: TextStyle(
                color: kGoldDark.withOpacity(0.70),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Expanded(
            child: Divider(color: kGoldDark.withOpacity(0.45), thickness: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleIcon() {
    return const Text(
      'G',
      style: TextStyle(
        fontSize: _kIconSize,
        fontWeight: FontWeight.w900,
        color: Colors.white,
        height: 1.0,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Royal-themed reusable dialog
// ─────────────────────────────────────────────────────────────────────────────

class _RoyalDialog extends StatelessWidget {
  const _RoyalDialog({
    required this.title,
    required this.subtitle,
    required this.hintText,
    required this.controller,
    required this.keyboardType,
    required this.inputFormatters,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
  });

  final String title;
  final String subtitle;
  final String hintText;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
        decoration: BoxDecoration(
          color: kBurgundy,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kGoldDark, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: kGold,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kGoldDark.withOpacity(0.75),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: controller,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              autofocus: true,
              style: const TextStyle(
                color: kGoldLight,
                fontSize: 18,
                letterSpacing: 2,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(
                  color: kGoldDark.withOpacity(0.45),
                  fontSize: 15,
                  letterSpacing: 1,
                ),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: kGoldDark),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: kGold, width: 2),
                ),
              ),
              onSubmitted: (_) => onConfirm(),
            ),
            const SizedBox(height: 28),

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kGoldDark,
                        side: BorderSide(color: kGoldDark.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: onCancel,
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kBurgundyLight,
                        side: const BorderSide(color: kGold, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: onConfirm,
                      child: Text(
                        confirmLabel,
                        style: const TextStyle(
                          color: kGold,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
