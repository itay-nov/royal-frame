import 'package:shared_preferences/shared_preferences.dart';

class BadgeService {
  static const String _keyHasPlacedAllQueens = 'badge_hasPlacedAllQueens';

  static SharedPreferences? _prefs;

  static bool get hasPlacedAllQueens =>
      _prefs?.getBool(_keyHasPlacedAllQueens) ?? false;

  // Convenience getter for external reads (e.g. future badge UI).
  static bool get isQueenBadgeUnlocked =>
      _prefs?.getBool(_keyHasPlacedAllQueens) ?? false;

  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<void> unlockQueenBadge() async {
    if (isQueenBadgeUnlocked) return;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_keyHasPlacedAllQueens, true);
  }
}
