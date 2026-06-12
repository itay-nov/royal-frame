import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HAPTIC SERVICE
// Centralises all haptic feedback for Royal Frame.
//
// Usage:
//   await HapticService.load();          // once, in main() or initState
//   HapticService.light();               // tap / selection
//   HapticService.heavy();               // illegal move / error
//   HapticService.success();             // clear pair / good action
//   await HapticService.setEnabled(v);   // toggle + persist
// ─────────────────────────────────────────────────────────────────────────────

class HapticService {
  HapticService._(); // non-instantiable

  static const String _prefKey = 'royalFrameHapticsEnabled';

  /// Master switch. Read this anywhere; toggle via [setEnabled].
  static bool isEnabled = true;

  // ── Persistence ─────────────────────────────────────────────────────────

  /// Load the saved preference. Call once at app start (or in BoardScreen's
  /// initState). Safe to call multiple times.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isEnabled = prefs.getBool(_prefKey) ?? true;
  }

  /// Persist the new value and update [isEnabled].
  static Future<void> setEnabled(bool value) async {
    isEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }

  // ── Feedback methods ─────────────────────────────────────────────────────

  /// Light impact — use for: cell tap, card selection, toggle press.
  static void light() {
    if (!isEnabled) return;
    if (kIsWeb) {
      // ignore: avoid_print
      print('📳 haptic: light');
      return;
    }
    HapticFeedback.lightImpact();
  }

  /// Heavy impact — use for: illegal move, error flash.
  static void heavy() {
    if (!isEnabled) return;
    if (kIsWeb) {
      // ignore: avoid_print
      print('💥 haptic: heavy');
      return;
    }
    HapticFeedback.heavyImpact();
  }

  /// Medium impact — use for: successful clear pair, phase transition.
  /// Named [success] to communicate intent at the call site.
  static void success() {
    if (!isEnabled) return;
    if (kIsWeb) {
      // ignore: avoid_print
      print('✨ haptic: success');
      return;
    }
    HapticFeedback.mediumImpact();
  }

  /// Selection click — use for: undo/redo, move-card confirm.
  static void selection() {
    if (!isEnabled) return;
    if (kIsWeb) {
      // ignore: avoid_print
      print('📳 haptic: selection');
      return;
    }
    HapticFeedback.selectionClick();
  }
}
