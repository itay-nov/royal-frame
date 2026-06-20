import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import '../utils/web_vibrate_stub.dart'
    if (dart.library.js_interop) '../utils/web_vibrate_web.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HAPTIC SERVICE
// Uses the `vibration` package for precise amplitude/duration control on
// Android, falls back to web navigator.vibrate on Web, and is a no-op on
// platforms without a vibrator.
//
// Usage:
//   await HapticService.load();          // once, in initState
//   HapticService.light();               // card tap / selection
//   HapticService.heavy();               // invalid move / error
//   HapticService.success();             // clear pair / good action
//   HapticService.selection();           // undo / move confirm
//   await HapticService.setEnabled(v);   // toggle + persist
// ─────────────────────────────────────────────────────────────────────────────

class HapticService {
  HapticService._();

  static const String _prefKey = 'royalFrameHapticsEnabled';

  static bool isEnabled   = true;
  static bool _hasVibrator = false;

  // ── Init ─────────────────────────────────────────────────────────────────

  /// Call once at app start. Loads the saved toggle and checks hardware caps.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isEnabled = prefs.getBool(_prefKey) ?? true;

    if (!kIsWeb) {
      _hasVibrator = await Vibration.hasVibrator();
    }
  }

  static Future<void> setEnabled(bool value) async {
    isEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }

  // ── Internal helper ───────────────────────────────────────────────────────

  static void _vibrate({required int duration, required int amplitude}) {
    if (!isEnabled) return;
    if (kIsWeb) {
      webVibrate(duration);
      return;
    }
    if (!_hasVibrator) return;
    Vibration.vibrate(duration: duration, amplitude: amplitude);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Light tap — card selection, normal placement.
  static void light() => _vibrate(duration: 30, amplitude: 60);

  /// Heavy buzz — invalid move, error flash, game over.
  static void heavy() => _vibrate(duration: 80, amplitude: 255);

  /// Medium pulse — successful clear pair, phase transition.
  static void success() => _vibrate(duration: 50, amplitude: 140);

  /// Crisp click — undo, move-card confirm.
  static void selection() => _vibrate(duration: 20, amplitude: 80);
}
