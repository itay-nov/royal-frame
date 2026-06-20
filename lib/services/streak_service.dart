import 'secure_storage_service.dart';

class StreakService {
  StreakService._();

  static const _keyStreak   = 'streak_count';
  static const _keyLastDate = 'streak_last_date';

  static int  _streak       = 0;
  static bool _justExtended = false;

  static int  get streak       => _streak;
  static bool get justExtended => _justExtended;

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static Future<void> load() async {
    _justExtended = false;
    final today    = _today();
    final lastDate = await SecureStorageService.read(_keyLastDate) ?? '';
    final saved    = await SecureStorageService.readInt(_keyStreak) ?? 0;

    if (lastDate == today) {
      _streak = saved;
      return;
    }

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    if (lastDate == yStr) {
      _streak = saved + 1;
      _justExtended = true;
    } else if (lastDate.isEmpty) {
      _streak = 1;
      _justExtended = true;
    } else {
      _streak = 1;
    }

    await SecureStorageService.writeInt(_keyStreak, _streak);
    await SecureStorageService.write(_keyLastDate, today);
  }

  static Future<void> reset() async {
    _streak = 0;
    _justExtended = false;
    await SecureStorageService.delete(_keyStreak);
    await SecureStorageService.delete(_keyLastDate);
  }
}
