import 'package:shared_preferences/shared_preferences.dart';

enum TutorialPhase { none, modals, fillHints, clearHints, done }

/// Singleton that tracks tutorial state across the session.
/// Call [init] once when BoardScreen loads. All other methods
/// are synchronous so they can be called freely from UI code.
class TutorialManager {
  TutorialManager._();

  static const _prefKey = 'royalFrameTutorialV3Done';

  static bool isActive = false;
  static TutorialPhase phase = TutorialPhase.none;

  /// Returns true if the tutorial should run (first game ever, or force).
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

  static Future<void> complete() async {
    isActive = false;
    phase = TutorialPhase.done;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  /// Dev helper — resets the tutorial so it runs again next launch.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    isActive = true;
    phase = TutorialPhase.modals;
  }
}
