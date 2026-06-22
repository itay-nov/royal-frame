import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TutorialPhase { none, modals, fillHints, clearHints, done }

/// Singleton that tracks tutorial state across the session.
/// Call [init] once when BoardScreen loads. All other methods
/// are synchronous so they can be called freely from UI code.
///
/// Firestore is the source of truth for veteran users:
///   - [syncFromFirestore] is called at app startup / login.
///   - [complete] writes to both local storage AND Firestore.
class TutorialManager {
  TutorialManager._();

  static const _prefKey = 'royalFrameTutorialV3Done';
  static const _firestoreField = 'hasSeenTutorial';

  static bool isActive = false;
  static TutorialPhase phase = TutorialPhase.none;

  /// Returns true if the tutorial should run (first game ever, or force).
  /// Always check local storage first; Firestore sync happens earlier at login.
  static Future<bool> init({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(_prefKey) ?? false;
    if (force || !done) {
      isActive = true;
      phase = TutorialPhase.modals;
      return true;
    }
    isActive = false;
    phase = TutorialPhase.done;
    return false;
  }

  static void advance(TutorialPhase next) {
    phase = next;
    if (next == TutorialPhase.done) isActive = false;
  }

  /// Marks the tutorial as done locally AND in Firestore (fire-and-forget).
  static Future<void> complete() async {
    isActive = false;
    phase = TutorialPhase.done;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    _persistToFirestore();
  }

  /// Called at app startup / login. Reads the user's Firestore document and,
  /// if `hasSeenTutorial == true`, writes the flag to local storage so [init]
  /// will skip the tutorial even if local storage was cleared.
  ///
  /// Safe to call when the user is not authenticated — it's a no-op then.
  static Future<void> syncFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('players')
          .doc(uid)
          .get();

      if (!doc.exists) return;
      final done = doc.data()?[_firestoreField] as bool? ?? false;
      if (!done) return;

      // Firestore says veteran — update local storage so tutorial is skipped.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
      isActive = false;
      phase = TutorialPhase.done;
    } catch (_) {
      // Network / permission failure — fall back to local storage silently.
    }
  }

  /// Dev helper — resets the tutorial so it runs again next launch.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    isActive = true;
    phase = TutorialPhase.modals;
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  /// Fire-and-forget write. Errors are intentionally swallowed — a failed
  /// Firestore write doesn't break the game; the local flag is already set.
  static void _persistToFirestore() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('players')
        .doc(uid)
        .set({_firestoreField: true}, SetOptions(merge: true))
        .catchError((_) {});
  }
}
