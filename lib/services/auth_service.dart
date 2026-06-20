import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'streak_service.dart';
import 'tutorial_manager.dart';
import 'daily_goal_service.dart';
import 'xp_service.dart';
import 'badge_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  // ─── Anonymous ─────────────────────────────────────────────────────────────

  Future<UserCredential?> signInAnonymously(String displayName) async {
    try {
      final credential = await _auth.signInAnonymously();
      await credential.user?.updateDisplayName(displayName);
      return credential;
    } catch (_) {
      return null;
    }
  }

  // ─── Google ────────────────────────────────────────────────────────────────

  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();
        return await _auth.signInWithPopup(googleProvider);
      } else {
        await GoogleSignIn.instance.initialize();
        final googleUser = await GoogleSignIn.instance.authenticate();
        if (googleUser == null) return null;

        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );
        return await _auth.signInWithCredential(credential);
      }
    } catch (_) {
      return null;
    }
  }

  // ─── Apple (hidden, kept for future use) ──────────────────────────────────

  Future<UserCredential?> signInWithApple() async {
    try {
      final appleProvider = AppleAuthProvider();
      if (kIsWeb) {
        return await _auth.signInWithPopup(appleProvider);
      } else {
        return await _auth.signInWithProvider(appleProvider);
      }
    } catch (_) {
      return null;
    }
  }

  // ─── Phone ─────────────────────────────────────────────────────────────────

  /// Web: triggers Firebase's built-in reCAPTCHA flow and returns a
  /// [ConfirmationResult] that you pass to [confirmSmsCodeWeb].
  ///
  /// Returns `null` on error; the caller is responsible for showing feedback.
  Future<ConfirmationResult?> sendSmsCodeWeb(String phoneNumber) async {
    assert(kIsWeb, 'sendSmsCodeWeb must only be called on Web');
    try {
      return await _auth.signInWithPhoneNumber(phoneNumber);
    } catch (_) {
      return null;
    }
  }

  /// Web: confirm the 6-digit code returned by [sendSmsCodeWeb].
  Future<UserCredential?> confirmSmsCodeWeb(
    ConfirmationResult confirmationResult,
    String smsCode,
  ) async {
    assert(kIsWeb, 'confirmSmsCodeWeb must only be called on Web');
    try {
      return await confirmationResult.confirm(smsCode);
    } catch (_) {
      rethrow;
    }
  }

  /// Native (Android / iOS): triggers [FirebaseAuth.verifyPhoneNumber].
  ///
  /// Callbacks:
  /// - [onCodeSent]   – called when Firebase successfully sends the SMS;
  ///                    receives (verificationId, resendToken).
  /// - [onAutoVerified] – called when Android auto-reads the SMS and
  ///                      produces a [UserCredential] immediately.
  /// - [onError]      – called with a human-readable error string.
  Future<void> sendSmsCodeNative({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(UserCredential credential) onAutoVerified,
    required void Function(String error) onError,
  }) async {
    assert(!kIsWeb, 'sendSmsCodeNative must only be called on Android/iOS');
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Android auto-retrieval or instant validation
          try {
            final userCred = await _auth.signInWithCredential(credential);
            onAutoVerified(userCred);
          } catch (e) {
            onError(e.toString());
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          onError(e.message ?? 'Verification failed.');
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // No-op: the user can still enter the code manually.
        },
      );
    } catch (e) {
      onError(e.toString());
    }
  }

  /// Native: confirm the 6-digit SMS code using a [verificationId] from
  /// [sendSmsCodeNative]'s [onCodeSent] callback.
  Future<UserCredential?> confirmSmsCodeNative({
    required String verificationId,
    required String smsCode,
  }) async {
    assert(!kIsWeb, 'confirmSmsCodeNative must only be called on Android/iOS');
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return await _auth.signInWithCredential(credential);
  }

  // ─── Sign out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      if (!kIsWeb) {
        await GoogleSignIn.instance.signOut();
      }
    } catch (_) {
      // ignore
    }
    await clearLocalUserData();
  }

  /// Wipes all user-specific local state so the next login starts clean.
  /// Called automatically on sign-out; can also be called explicitly.
  static Future<void> clearLocalUserData() async {
    // SharedPreferences: player name + tutorial flag
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('playerName');
    await TutorialManager.reset();   // clears royalFrameTutorialV3Done

    // SecureStorage: game progress
    await StreakService.reset();
    await DailyGoalService.reset();
    await XpService.reset();
    await BadgeService.reset();
  }
}
