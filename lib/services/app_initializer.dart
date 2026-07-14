import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_feedback.dart';
import 'auth_service.dart';
import 'db_service.dart';

/// Owns app startup: App Check activation + guest-session validation.
///
/// Guards against Android Auto-Backup restoring stale SharedPreferences after
/// a reinstall. Live Firebase identities are preserved and missing player
/// documents are healed; only cached sessions with no authenticated user are
/// replaced with a fresh anonymous identity.
class AppInitializer {
  AppInitializer._();

  /// Call after [Firebase.initializeApp]. Returns the player name the app
  /// should boot with, or null → route to WelcomeScreen.
  static Future<String?> initialize() async {
    await _activateAppCheck();
    return _validateGuestSession();
  }

  // ── App Check ──────────────────────────────────────────────────────────────

  static Future<void> _activateAppCheck() async {
    await FirebaseAppCheck.instance.activate(
      // Android/iOS: Play Integrity / App Attest in release; debug provider in debug.
      providerAndroid: kReleaseMode
          ? AndroidPlayIntegrityProvider()
          : AndroidDebugProvider(),
      providerApple: kReleaseMode
          ? AppleAppAttestWithDeviceCheckFallbackProvider()
          : AppleDebugProvider(),
      // Web: always pass the reCAPTCHA provider.
      // In debug/dev the JS global `self.FIREBASE_APPCHECK_DEBUG_TOKEN = true`
      // (set in web/index.html for localhost) intercepts the request before it
      // reaches reCAPTCHA, so no real token exchange happens and no 403 is thrown.
      providerWeb: ReCaptchaV3Provider(
        '6LfKGSctAAAAAJ6Lk2FwIHMlemfc_BhiPAHjeXt9',
      ),
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

  // ── Guest-session validation ───────────────────────────────────────────────

  /// Returns the validated player name, or null if there is no session
  /// (fresh install, or recovery failed and the user must re-onboard).
  static Future<String?> _validateGuestSession() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedName = prefs.getString('playerName');
    if (savedName == null) return null; // Fresh install — nothing to validate.

    final auth = FirebaseAuth.instance;
    return validateSessionStateForTesting(
      savedName: savedName,
      authenticatedUid: auth.currentUser?.uid,
      playerDocExists: _playerDocExistsOnServer,
      ensurePlayerDoc: (uid, name) => DbService().ensurePlayerDoc(uid, name),
      recoverSession: _recoverSession,
    );
  }

  /// Purely dependency-driven session policy, exposed so identity migration
  /// behavior can be tested without initializing Firebase platform channels.
  @visibleForTesting
  static Future<String?> validateSessionStateForTesting({
    required String? savedName,
    required String? authenticatedUid,
    required Future<bool?> Function(String uid) playerDocExists,
    required Future<void> Function(String uid, String name) ensurePlayerDoc,
    required Future<String?> Function(String savedName) recoverSession,
  }) async {
    if (savedName == null) return null;

    if (authenticatedUid != null) {
      final bool? exists = await playerDocExists(authenticatedUid);

      // Network error / timeout — assume the session is valid rather than
      // wiping a legitimate user who happens to be offline.
      if (exists == null) return savedName;

      if (exists) return savedName; // Healthy session.

      // Preserve a live Firebase identity. Older builds did not create the
      // player document until the first completed game, so treating a missing
      // document as stale could silently replace Google/phone users with an
      // anonymous account.
      try {
        await ensurePlayerDoc(authenticatedUid, savedName);
      } catch (error, stack) {
        // The user is still authenticated; fail open just as we do for an
        // unknown server result and let later writes heal the missing record.
        logError('startup.ensurePlayerDoc', error, stack);
      }
      return savedName;
    }
    // else: Auto-Backup restored prefs but no auth user survived — stale.

    return recoverSession(savedName);
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

  /// Wipes stale local state and silently starts a fresh guest session,
  /// preserving the player's display name. Returns null if recovery fails
  /// (e.g. offline) so the app falls back to the WelcomeScreen.
  static Future<String?> _recoverSession(String savedName) async {
    try {
      await AuthService.clearLocalUserData();

      final credential = await AuthService().signInAnonymously(savedName);
      final uid = credential?.user?.uid;
      if (uid == null) return null;

      await DbService().ensurePlayerDoc(uid, savedName);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playerName', savedName);
      return savedName;
    } catch (_) {
      return null; // Silent — user simply re-onboards via WelcomeScreen.
    }
  }
}
