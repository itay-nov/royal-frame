import 'package:shared_preferences/shared_preferences.dart';

class StreakService {
  StreakService._();

  static const _keyStreak     = 'streak_count';
  static const _keyLastDate   = 'streak_last_date';

  static int _streak = 0;
  static bool _justExtended = false;

  static int  get streak        => _streak;
  /// True only the first time [load] is called today and it extends the streak.
  static bool get justExtended  => _justExtended;

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
  }

  /// Call once per session (e.g. in MainMenuScreen.initState).
  static Future<void> load() async {
    _justExtended = false;
    final prefs    = await SharedPreferences.getInstance();
    final today    = _today();
    final lastDate = prefs.getString(_keyLastDate) ?? '';
    final saved    = prefs.getInt(_keyStreak) ?? 0;

    if (lastDate == today) {
      // Already checked in today — just restore.
      _streak = saved;
      return;
    }

    // Check if yesterday was the last date.
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2,'0')}-${yesterday.day.toString().padLeft(2,'0')}';

    if (lastDate == yStr) {
      // Consecutive day — extend streak.
      _streak = saved + 1;
      _justExtended = true;
    } else if (lastDate.isEmpty) {
      // First ever login.
      _streak = 1;
      _justExtended = true;
    } else {
      // Missed a day — reset.
      _streak = 1;
    }

    await prefs.setInt(_keyStreak, _streak);
    await prefs.setString(_keyLastDate, today);
  }

  static Future<void> reset() async {
    _streak = 0;
    _justExtended = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyStreak);
    await prefs.remove(_keyLastDate);
  }
}
