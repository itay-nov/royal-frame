import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'streak_service.dart';
import 'tutorial_manager.dart';
import 'daily_goal_service.dart';
import 'xp_service.dart';
import 'badge_service.dart';
import '../utils/player_name_policy.dart';

enum GoogleSignInFailureKind { canceled, interrupted, failure }

class GoogleSignInInterruptedException implements Exception {
  const GoogleSignInInterruptedException();
}

class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  static Future<void>? _googleInitialization;

  User? get currentUser => _auth.currentUser;

  // ─── Anonymous ─────────────────────────────────────────────────────────────

  Future<UserCredential?> signInAnonymously(String displayName) async {
    try {
      final credential = await _auth.signInAnonymously();
      await credential.user?.updateDisplayName(
        PlayerNamePolicy.sanitize(displayName),
      );
      return credential;
    } catch (_) {
      return null;
    }
  }

  // ─── Google ────────────────────────────────────────────────────────────────

  Future<UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      try {
        final googleProvider = GoogleAuthProvider()
          ..setCustomParameters({
            'client_id':
                '961421919288-1oqcid53ipgtshukmvkp90cu2g1i21g2.apps.googleusercontent.com',
          });
        return await runWebGoogleSignInForTesting(
          () => _auth.signInWithPopup(googleProvider),
        );
      } catch (_) {
        rethrow;
      }
    }

    try {
      await _ensureGoogleSignInInitialized();
      final googleUser = await GoogleSignIn.instance.authenticate();

      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      return await _auth.signInWithCredential(credential);
    } on GoogleSignInException catch (error) {
      switch (classifyGoogleSignInFailure(error)) {
        case GoogleSignInFailureKind.canceled:
          return null;
        case GoogleSignInFailureKind.interrupted:
          throw const GoogleSignInInterruptedException();
        case GoogleSignInFailureKind.failure:
          rethrow;
      }
    }
  }

  @visibleForTesting
  static GoogleSignInFailureKind classifyGoogleSignInFailure(
    GoogleSignInException error,
  ) {
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled => GoogleSignInFailureKind.canceled,
      GoogleSignInExceptionCode.interrupted =>
        GoogleSignInFailureKind.interrupted,
      _ => GoogleSignInFailureKind.failure,
    };
  }

  @visibleForTesting
  static GoogleSignInFailureKind classifyWebGoogleFailureCode(String code) {
    final normalized = code.startsWith('auth/') ? code.substring(5) : code;
    return switch (normalized) {
      'popup-closed-by-user' || 'web-context-cancelled' =>
        GoogleSignInFailureKind.canceled,
      'cancelled-popup-request' => GoogleSignInFailureKind.interrupted,
      _ => GoogleSignInFailureKind.failure,
    };
  }

  @visibleForTesting
  static Future<T?> runWebGoogleSignInForTesting<T>(
    Future<T> Function() authenticate,
  ) async {
    try {
      return await authenticate();
    } on FirebaseAuthException catch (error) {
      switch (classifyWebGoogleFailureCode(error.code)) {
        case GoogleSignInFailureKind.canceled:
          return null;
        case GoogleSignInFailureKind.interrupted:
          throw const GoogleSignInInterruptedException();
        case GoogleSignInFailureKind.failure:
          rethrow;
      }
    }
  }

  Future<bool> rollbackNewPhoneSession({
    required String? previousUid,
    required String authenticatedUid,
  }) {
    return rollbackNewPhoneSessionForTesting(
      previousUid: previousUid,
      authenticatedUid: authenticatedUid,
      currentUid: _auth.currentUser?.uid,
      signOut: _auth.signOut,
    );
  }

  @visibleForTesting
  static Future<bool> rollbackNewPhoneSessionForTesting({
    required String? previousUid,
    required String authenticatedUid,
    required String? currentUid,
    required Future<void> Function() signOut,
  }) async {
    final isNewSession = previousUid != authenticatedUid;
    if (!isNewSession || currentUid != authenticatedUid) return false;
    await signOut();
    return true;
  }

  static Future<void> _ensureGoogleSignInInitialized() async {
    final initialization = _googleInitialization ??= GoogleSignIn.instance
        .initialize();
    try {
      await initialization;
    } catch (_) {
      if (identical(_googleInitialization, initialization)) {
        _googleInitialization = null;
      }
      rethrow;
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
          } catch (_) {
            onError('verification-failed');
          }
        },
        verificationFailed: (_) {
          onError('verification-failed');
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // No-op: the user can still enter the code manually.
        },
      );
    } catch (_) {
      onError('verification-failed');
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
        await _ensureGoogleSignInInitialized();
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
