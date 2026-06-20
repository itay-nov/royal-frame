import 'secure_storage_service.dart';

class BadgeService {
  static const String _keyHasPlacedAllQueens = 'badge_hasPlacedAllQueens';

  static bool _queenBadgeUnlocked = false;

  static bool get hasPlacedAllQueens  => _queenBadgeUnlocked;
  static bool get isQueenBadgeUnlocked => _queenBadgeUnlocked;

  static Future<void> load() async {
    _queenBadgeUnlocked =
        await SecureStorageService.readBool(_keyHasPlacedAllQueens) ?? false;
  }

  static Future<void> reset() async {
    _queenBadgeUnlocked = false;
    await SecureStorageService.delete(_keyHasPlacedAllQueens);
  }

  static Future<void> unlockQueenBadge() async {
    if (_queenBadgeUnlocked) return;
    _queenBadgeUnlocked = true;
    await SecureStorageService.writeBool(_keyHasPlacedAllQueens, true);
  }
}
