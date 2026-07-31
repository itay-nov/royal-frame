import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme_constants.dart';
import '../utils/app_feedback.dart';
import '../utils/app_route.dart';
import '../utils/localization.dart';
import '../utils/phone_verification_attempt.dart';
import '../utils/player_name_policy.dart';
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
  const WelcomeScreen({super.key, this.authService});

  final AuthService? authService;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  late final AuthService _authService;
  bool _isLoading = false;
  bool _phoneFlowInProgress = false;
  AppLang _lang = AppLang.en;
  L get _l => L(_lang);

  // Title entrance animation
  bool _visible = false;
  Timer? _entranceTimer;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _loadSavedLang();
    _entranceTimer = Timer(const Duration(milliseconds: 150), () {
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
    _entranceTimer?.cancel();
    _nameCtrl.dispose();
    super.dispose();
  }

  // ─── Navigation helper ────────────────────────────────────────────────────

  void _goToMainMenu() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(appRoute(const MainMenuScreen()));
  }

  void _showError(String message) {
    if (!mounted) return;
    showAppSnack(context, message, isError: true);
  }

  void _showInfo(String message) {
    if (!mounted) return;
    showAppSnack(context, message);
  }

  String _boundedPlayerName(String? value) {
    return PlayerNamePolicy.sanitize(value);
  }

  // ─── Guest login ──────────────────────────────────────────────────────────

  void _startGame() async {
    final name = PlayerNamePolicy.normalize(_nameCtrl.text);
    if (!PlayerNamePolicy.isValid(name) && name.isEmpty) {
      _showError(_l.errEnterName);
      return;
    }
    if (!PlayerNamePolicy.isValid(name)) {
      _showError(_l.errNameTooLong(PlayerNamePolicy.maxCharacters));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = await _authService.signInAnonymously(name);
      if (!mounted) return;

      final uid = credential?.user?.uid;
      if (uid == null) {
        setState(() => _isLoading = false);
        _showError(_l.errGuestSignIn);
        return;
      }

      await DbService().ensurePlayerDoc(uid, name);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playerName', name);
      if (!mounted) return;

      setState(() => _isLoading = false);
      _goToMainMenu();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_l.errProfileSetup);
    }
  }

  // ─── Google login ─────────────────────────────────────────────────────────

  void _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final userCred = await _authService.signInWithGoogle();
      if (!mounted) return;

      if (userCred != null) {
        final user = userCred.user;
        if (user == null) {
          setState(() => _isLoading = false);
          _showError(_l.errProfileSetup);
          return;
        }

        final name = _boundedPlayerName(user.displayName);
        await DbService().ensurePlayerDoc(user.uid, name);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('playerName', name);
        if (!mounted) return;
        _goToMainMenu();
      } else {
        setState(() => _isLoading = false);
        _showInfo(_l.infoGoogleCancelled);
      }
    } on GoogleSignInInterruptedException {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showInfo(_l.infoGoogleInterrupted);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_l.errGoogleSignIn);
    }
  }

  // ─── Phone login ──────────────────────────────────────────────────────────

  void _signInWithPhone() async {
    if (_phoneFlowInProgress) return;
    _phoneFlowInProgress = true;
    final previousUid = _authService.currentUser?.uid;

    try {
      final phone = await _showPhoneInputDialog();
      if (!mounted || phone == null || phone.isEmpty) return;

      setState(() => _isLoading = true);

      if (kIsWeb) {
        await _handlePhoneWeb(phone, previousUid: previousUid);
      } else {
        await _handlePhoneNative(phone, previousUid: previousUid);
      }
    } finally {
      _phoneFlowInProgress = false;
    }
  }

  /// Web path: Firebase handles reCAPTCHA internally.
  Future<void> _handlePhoneWeb(
    String phoneNumber, {
    required String? previousUid,
  }) async {
    final confirmationResult = await _authService.sendSmsCodeWeb(phoneNumber);
    if (!mounted) return;

    setState(() => _isLoading = false);

    if (confirmationResult == null) {
      _showError(_l.errPhoneCodeSend);
      return;
    }

    final smsCode = await _showSmsCodeDialog();
    if (!mounted || smsCode == null || smsCode.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userCred = await _authService.confirmSmsCodeWeb(
        confirmationResult,
        smsCode,
      );
      if (!mounted) return;
      if (userCred != null) {
        await _savePhonePlayerAndNavigate(
          userCred,
          previousUid: previousUid,
        );
      }
    } on FirebaseAuthException {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_l.errInvalidVerificationCode);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_l.errVerificationFailed);
    }
  }

  /// Native (Android / iOS) path.
  Future<void> _handlePhoneNative(
    String phoneNumber, {
    required String? previousUid,
  }) async {
    final attempt = PhoneVerificationAttempt();

    try {
      await _authService.sendSmsCodeNative(
        phoneNumber: phoneNumber,
        onCodeSent: (verificationId, _) async {
          if (!mounted) {
            attempt.complete();
            return;
          }
          if (attempt.authenticationStarted || attempt.codeDialogOpen) return;
          await _confirmNativeSmsCode(
            verificationId,
            attempt,
            previousUid: previousUid,
          );
        },
        onAutoVerified: (userCred) async {
          if (!mounted) {
            attempt.complete();
            return;
          }
          if (!attempt.claimAuthentication()) return;
          if (attempt.codeDialogOpen) {
            Navigator.of(context, rootNavigator: true).pop();
          }
          await _savePhonePlayerAndNavigate(
            userCred,
            previousUid: previousUid,
          );
          attempt.complete();
        },
        onError: (_) {
          if (!mounted) {
            attempt.complete();
            return;
          }
          if (attempt.authenticationStarted) return;
          setState(() => _isLoading = false);
          _showError(_l.errVerificationFailed);
          attempt.complete();
        },
      );
      await attempt.done;
    } catch (_) {
      attempt.complete();
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_l.errVerificationFailed);
    }
  }

  Future<void> _confirmNativeSmsCode(
    String verificationId,
    PhoneVerificationAttempt attempt, {
    required String? previousUid,
  }) async {
    if (!mounted) {
      attempt.complete();
      return;
    }
    setState(() => _isLoading = false);

    attempt.codeDialogOpen = true;
    final String? smsCode;
    try {
      smsCode = await _showSmsCodeDialog();
    } finally {
      attempt.codeDialogOpen = false;
    }

    if (!mounted) {
      attempt.complete();
      return;
    }
    if (smsCode == null || smsCode.isEmpty) {
      if (!attempt.authenticationStarted) attempt.complete();
      return;
    }
    if (!attempt.claimAuthentication()) return;

    setState(() => _isLoading = true);

    try {
      final userCred = await _authService.confirmSmsCodeNative(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      if (!mounted) return;
      if (userCred == null) {
        setState(() => _isLoading = false);
        _showError(_l.errVerificationFailed);
        return;
      }
      await _savePhonePlayerAndNavigate(
        userCred,
        previousUid: previousUid,
      );
    } on FirebaseAuthException {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_l.errInvalidVerificationCode);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_l.errVerificationFailed);
    } finally {
      attempt.complete();
    }
  }

  /// Called after every successful phone sign-in (both web & native).
  ///
  /// Phone auth never provides a display name, so we check if one is
  /// missing (null, empty, or the generic "player" fallback) and show a
  /// mandatory name-picker dialog before proceeding to the main menu.
  Future<void> _savePhonePlayerAndNavigate(
    UserCredential userCred, {
    required String? previousUid,
  }) async {
    final user = userCred.user;
    if (user == null) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(_l.errProfileSetup);
      }
      return;
    }

    try {
      final rawExistingName = user.displayName?.trim() ?? '';
      final needsName =
          rawExistingName.isEmpty || rawExistingName.toLowerCase() == 'player';

      late final String finalName;
      if (needsName) {
        setState(() => _isLoading = false);

        final chosenName = await _showPlayerNameDialog();
        if (!mounted) return;

        if (chosenName == null || chosenName.trim().isEmpty) {
          await _authService.rollbackNewPhoneSession(
            previousUid: previousUid,
            authenticatedUid: user.uid,
          );
          if (mounted) setState(() => _isLoading = false);
          return;
        }

        setState(() => _isLoading = true);
        finalName = _boundedPlayerName(chosenName);
        await user.updateDisplayName(finalName);
      } else {
        finalName = _boundedPlayerName(rawExistingName);
      }

      await DbService().ensurePlayerDoc(user.uid, finalName);
      await DbService().updateDisplayName(user.uid, finalName);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playerName', finalName);
      if (!mounted) return;

      setState(() => _isLoading = false);
      _goToMainMenu();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_l.errProfileSetup);
    }
  }

  // ─── Dialogs ──────────────────────────────────────────────────────────────

  Widget _withDialogDirection(Widget child) {
    return Directionality(
      textDirection: _lang == AppLang.he
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: child,
    );
  }

  Future<String?> _showPhoneInputDialog() {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => _withDialogDirection(
        _RoyalDialog(
          title: _l.phoneNumberTitle,
          subtitle: _l.phoneNumberSubtitle,
        hintText: '+972 50 123 4567',
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[+\d\s\-]')),
        ],
          confirmLabel: _l.btnSendCode,
          cancelLabel: _l.btnCancel,
          onConfirm: (value) => Navigator.of(ctx).pop(value),
        onCancel: () => Navigator.of(ctx).pop(null),
        ),
      ),
    );
  }

  Future<String?> _showSmsCodeDialog() {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => _withDialogDirection(
        _RoyalDialog(
          title: _l.verificationCodeTitle,
          subtitle: _l.verificationCodeSubtitle,
        hintText: '000000',
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
          confirmLabel: _l.btnVerify,
          cancelLabel: _l.btnCancel,
          onConfirm: (value) => Navigator.of(ctx).pop(value),
        onCancel: () => Navigator.of(ctx).pop(null),
        ),
      ),
    );
  }

  /// Mandatory name-picker shown after phone sign-in.
  /// [barrierDismissible] is false so the user must pick a name or cancel.
  Future<String?> _showPlayerNameDialog() {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => _withDialogDirection(
        _RoyalDialog(
          title: _l.chooseNameTitle,
          subtitle: _l.chooseNameSubtitle,
          hintText: _l.chooseNameHint,
        keyboardType: TextInputType.name,
          inputFormatters: [
            LengthLimitingTextInputFormatter(PlayerNamePolicy.maxCharacters),
          ],
          confirmLabel: _l.btnConfirm,
          cancelLabel: _l.btnCancel,
          onConfirm: (name) {
          if (name.isNotEmpty) Navigator.of(ctx).pop(name);
        },
        onCancel: () => Navigator.of(ctx).pop(null),
        ),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  void _toggleLang() {
    final newLang = _lang == AppLang.he ? AppLang.en : AppLang.he;
    setState(() => _lang = newLang);
    L.saveLang(newLang);
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: kBurgundy,
      body: Directionality(
        textDirection: _lang == AppLang.he
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: Stack(
        children: [
          // ── Subtle radial glow decoration ──────────────────────────────────
          Positioned(top: -80, left: -60, child: _glowCircle(340)),
          Positioned(bottom: -100, right: -80, child: _glowCircle(380)),

          Center(
            child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 32,
                ),
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
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(
                            PlayerNamePolicy.maxCharacters,
                          ),
                        ],
                      style: const TextStyle(color: kGoldLight, fontSize: 17),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: _l.welcomeHint,
                        hintStyle: TextStyle(
                          color: kGoldDark.withValues(alpha: 0.55),
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
          Positioned(top: topInset + 8, right: 16, child: _buildLangToggle()),
        ],
        ),
      ),
    );
  }

  Widget _glowCircle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kGold.withValues(alpha: 0.04),
      ),
    );
  }

  Widget _buildLangToggle() {
    // Shows the *target* language (the one you'll switch TO) so the player
    // instantly sees "עברית" if the app is in English, or "English" if in Hebrew.
    final targetLabel = _lang == AppLang.he ? 'English' : 'עברית';
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        foregroundColor: kGold,
        side: const BorderSide(color: kGold, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
        _buildPrimaryButton(label: _l.btnPlayAsGuest, onPressed: _startGame),

        const SizedBox(height: 28),
        _buildOrDivider(),
        const SizedBox(height: 24),

        _buildSocialLoginButton(
          label: _l.btnContinueGoogle,
          icon: _buildGoogleIcon(),
          onPressed: _signInWithGoogle,
        ),

        const SizedBox(height: 14),

        _buildSocialLoginButton(
          label: _l.btnContinuePhone,
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
          backgroundColor: Colors.black.withValues(alpha: 0.30),
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
            child: Divider(
              color: kGoldDark.withValues(alpha: 0.45),
              thickness: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'OR',
              style: TextStyle(
                color: kGoldDark.withValues(alpha: 0.70),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: kGoldDark.withValues(alpha: 0.45),
              thickness: 1,
            ),
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

class _RoyalDialog extends StatefulWidget {
  const _RoyalDialog({
    required this.title,
    required this.subtitle,
    required this.hintText,
    required this.keyboardType,
    required this.inputFormatters,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
  });

  final String title;
  final String subtitle;
  final String hintText;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final String confirmLabel;
  final String cancelLabel;
  final ValueChanged<String> onConfirm;
  final VoidCallback onCancel;

  @override
  State<_RoyalDialog> createState() => _RoyalDialogState();
}

class _RoyalDialogState extends State<_RoyalDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() => widget.onConfirm(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: SingleChildScrollView(
      child: Container(
        width: 320,
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
        decoration: BoxDecoration(
          color: kBurgundy,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kGoldDark, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                widget.title,
              style: const TextStyle(
                color: kGold,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
                widget.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kGoldDark.withValues(alpha: 0.75),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),

            TextField(
                controller: _controller,
                keyboardType: widget.keyboardType,
                inputFormatters: widget.inputFormatters,
              autofocus: true,
              style: const TextStyle(
                color: kGoldLight,
                fontSize: 18,
                letterSpacing: 2,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                  hintText: widget.hintText,
                hintStyle: TextStyle(
                  color: kGoldDark.withValues(alpha: 0.45),
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
                onSubmitted: (_) => _confirm(),
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
                        side: BorderSide(
                          color: kGoldDark.withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                        onPressed: widget.onCancel,
                        child: Text(
                          widget.cancelLabel,
                          style: const TextStyle(fontSize: 14),
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
                        onPressed: _confirm,
                      child: Text(
                          widget.confirmLabel,
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
      ),
    );
  }
}
