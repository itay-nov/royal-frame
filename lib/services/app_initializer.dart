import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'db_service.dart';
import '../utils/player_name_policy.dart';

/// Owns app startup: App Check activation + guest-session validation.
///
/// Reconciles cached identity with live Firebase and Firestore state without
/// destroying a valid authenticated session when the server is unavailable.
class AppInitializer {
  AppInitializer._();

  static Future<void>? _appCheckActivation;

  /// Call after [Firebase.initializeApp]. Returns the player name the app
  /// should boot with, or null → route to WelcomeScreen.
  static Future<String?> initialize() async {
    await _activateAppCheck();
    return _validateGuestSession();
  }

  // ── App Check ──────────────────────────────────────────────────────────────

  static Future<void> _activateAppCheck() {
    return activateAppCheckOnceForTesting(_activateAppCheckUncached);
  }

  static Future<void> _activateAppCheckUncached() async {
    if (kIsWeb && kDebugMode) return;

    await FirebaseAppCheck.instance.activate(
      // Android/iOS: Play Integrity / App Attest in release; debug provider in debug.
      providerAndroid: kReleaseMode ? AndroidPlayIntegrityProvider() : AndroidDebugProvider(),
      providerApple: kReleaseMode ? AppleAppAttestWithDeviceCheckFallbackProvider() : AppleDebugProvider(),
      // Web: always pass the reCAPTCHA provider.
      // In debug/dev the JS global `self.FIREBASE_APPCHECK_DEBUG_TOKEN = true`
      // (set in web/index.html for localhost) intercepts the request before it
      // reaches reCAPTCHA, so no real token exchange happens and no 403 is thrown.
      providerWeb: ReCaptchaV3Provider('6LfKGSctAAAAAJ6Lk2FwIHMlemfc_BhiPAHjeXt9'),
    );

    if (kDebugMode) {
      debugPrint(
        '[AppCheck] Debug provider active. The native SDK prints the debug '
        'token to logcat (Android: "Enter this debug secret into the allow '
        'list...") or the Xcode console. Register it in Firebase Console → '
        'App Check → Apps → Manage debug tokens, or requests stay "Invalid".',
      );
    }
  }

  @visibleForTesting
  static Future<void> activateAppCheckOnceForTesting(
    Future<void> Function() activate,
  ) async {
    final activation = _appCheckActivation ??= activate();
    try {
      await activation;
    } catch (_) {
      if (identical(_appCheckActivation, activation)) {
        _appCheckActivation = null;
      }
      rethrow;
    }
  }

  @visibleForTesting
  static void resetAppCheckActivationForTesting() {
    _appCheckActivation = null;
  }

  // ── Guest-session validation ───────────────────────────────────────────────

  /// Returns the validated player name, or null if there is no session
  /// (fresh install, or recovery failed and the user must re-onboard).
  static Future<String?> _validateGuestSession() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedName = prefs.getString('playerName');
    final user = FirebaseAuth.instance.currentUser;
    return validateSessionStateForTesting(
      savedName: savedName,
      authenticatedUid: user?.uid,
      authenticatedDisplayName: user?.displayName,
      playerDocExists: _playerDocExistsOnServer,
      ensurePlayerDoc: (uid, name) => DbService().ensurePlayerDoc(uid, name),
      persistPlayerName: (name) => prefs.setString('playerName', name),
      recoverSession: _recoverSession,
    );
  }

  @visibleForTesting
  static Future<String?> validateSessionStateForTesting({
    required String? savedName,
    required String? authenticatedUid,
    required String? authenticatedDisplayName,
    required Future<bool?> Function(String uid) playerDocExists,
    required Future<void> Function(String uid, String name) ensurePlayerDoc,
    required Future<void> Function(String name) persistPlayerName,
    required Future<String?> Function(String savedName) recoverSession,
  }) async {
    if (authenticatedUid != null) {
      final effectiveName = PlayerNamePolicy.sanitize(
        savedName ?? authenticatedDisplayName,
      );
      final bool? exists = await playerDocExists(authenticatedUid);

      // An unavailable server must never destroy a valid Firebase identity.
      if (exists == null) return effectiveName;

      if (!exists) {
        try {
          await ensurePlayerDoc(authenticatedUid, effectiveName);
        } catch (_) {
          debugPrint(
            '[AppInitializer] Could not heal the authenticated profile.',
          );
          return effectiveName;
        }
      }

      // Persist a recovered or normalized name only after required backend
      // state exists. Unknown server state already returned above.
      if (savedName != effectiveName) {
        try {
          await persistPlayerName(effectiveName);
        } catch (_) {
          debugPrint(
            '[AppInitializer] Could not persist the recovered player name.',
          );
        }
      }
      return effectiveName;
    }

    if (savedName == null) return null;
    return recoverSession(PlayerNamePolicy.sanitize(savedName));
  }

  /// Server-driven existence check. Returns null when the answer is unknown
  /// (offline, timeout, permission error) so the caller can fail open.
  static Future<bool?> _playerDocExistsOnServer(String uid) async {
    try {
      return await DbService()
          .playerDocExists(uid)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }

  /// Replaces a cached session that no longer has an authenticated user.
  ///
  /// Local progress is cleared only after authentication and the replacement
  /// player document have both succeeded, so an offline recovery attempt is
  /// non-destructive.
  static Future<String?> _recoverSession(String savedName) async {
    final safeName = PlayerNamePolicy.sanitize(savedName);
    try {
      final credential = await AuthService().signInAnonymously(safeName);
      final uid = credential?.user?.uid;
      if (uid == null) return null;

      await DbService().ensurePlayerDoc(uid, safeName);
      await AuthService.clearLocalUserData();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playerName', safeName);
      return safeName;
    } catch (_) {
      return null;
    }
  }
}
