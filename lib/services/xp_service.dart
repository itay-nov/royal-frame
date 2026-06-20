import 'dart:math';
import 'package:flutter/material.dart';
import 'secure_storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COSMETIC ITEM MODEL
// ─────────────────────────────────────────────────────────────────────────────
class CosmeticItem {
  final String id;
  final String name;
  final int levelRequired;
  final bool isDefault;

  // Card back: asset path to the back-of-card image.
  final String? assetPath;
  // Fallback color rendered when the asset is missing.
  final Color? fallbackColor;

  // Board color: the scaffold background color.
  final Color? boardColor;
  // Slightly lighter variant used for panels / appbar.
  final Color? boardColorLight;

  const CosmeticItem({
    required this.id,
    required this.name,
    required this.levelRequired,
    this.isDefault = false,
    this.assetPath,
    this.fallbackColor,
    this.boardColor,
    this.boardColorLight,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// XP / COSMETICS SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class XpService {
  // ── SharedPreferences keys ─────────────────────────────────────────────────
  static const _keyXP             = 'xp_total';
  static const _keyUnlockedBacks  = 'xp_unlocked_backs';
  static const _keyUnlockedColors = 'xp_unlocked_colors';
  static const _keyEquippedBack   = 'xp_equipped_back';
  static const _keyEquippedColor  = 'xp_equipped_color';

  // ── In-memory state ────────────────────────────────────────────────────────
  static int _currentXP = 0;
  static List<String> _unlockedBackIds   = ['classic_red'];
  static List<String> _unlockedColorIds  = ['burgundy'];
  static String _equippedBackId   = 'classic_red';
  static String _equippedColorId  = 'burgundy';

  // ── XP per level (flat 1 000 XP per level) ────────────────────────────────
  static const int xpPerLevel = 1000;

  static int get currentXP       => _currentXP;
  static int get playerLevel     => (_currentXP ~/ xpPerLevel) + 1;
  static int get xpInCurrentLevel => _currentXP % xpPerLevel;
  static double get levelProgress => xpInCurrentLevel / xpPerLevel;

  static String get equippedBackId  => _equippedBackId;
  static String get equippedColorId => _equippedColorId;

  // ── Cosmetic item catalogues ───────────────────────────────────────────────

  static final List<CosmeticItem> cardBacks = [
    const CosmeticItem(
      id: 'classic_red',
      name: 'Classic Red',
      levelRequired: 1,
      isDefault: true,
      assetPath: 'assets/images/card_back_red.png',
      fallbackColor: Color(0xFFB71C1C),
    ),
    const CosmeticItem(
      id: 'midnight_blue',
      name: 'Midnight Blue',
      levelRequired: 2,
      assetPath: 'assets/images/card_back_blue.png',
      fallbackColor: Color(0xFF0D2D6B),
    ),
    const CosmeticItem(
      id: 'forest_green',
      name: 'Forest Green',
      levelRequired: 3,
      assetPath: 'assets/images/card_back_green.png',
      fallbackColor: Color(0xFF1B5E20),
    ),
    const CosmeticItem(
      id: 'royal_purple',
      name: 'Royal Purple',
      levelRequired: 5,
      assetPath: 'assets/images/card_back_purple.png',
      fallbackColor: Color(0xFF4A148C),
    ),
    const CosmeticItem(
      id: 'golden_crown',
      name: 'Golden Crown',
      levelRequired: 8,
      assetPath: 'assets/images/card_back_gold.png',
      fallbackColor: Color(0xFF5D4E00),
    ),
  ];

  static final List<CosmeticItem> boardColors = [
    const CosmeticItem(
      id: 'burgundy',
      name: 'Burgundy',
      levelRequired: 1,
      isDefault: true,
      boardColor: Color(0xFF4A0E1A),
      boardColorLight: Color(0xFF6B1A2A),
    ),
    const CosmeticItem(
      id: 'navy',
      name: 'Midnight Navy',
      levelRequired: 2,
      boardColor: Color(0xFF0A1628),
      boardColorLight: Color(0xFF142240),
    ),
    const CosmeticItem(
      id: 'forest',
      name: 'Deep Forest',
      levelRequired: 3,
      boardColor: Color(0xFF0D2818),
      boardColorLight: Color(0xFF163D26),
    ),
    const CosmeticItem(
      id: 'obsidian',
      name: 'Obsidian',
      levelRequired: 5,
      boardColor: Color(0xFF111118),
      boardColorLight: Color(0xFF1E1E2E),
    ),
    const CosmeticItem(
      id: 'amethyst',
      name: 'Amethyst',
      levelRequired: 8,
      boardColor: Color(0xFF2D1B4E),
      boardColorLight: Color(0xFF3D2660),
    ),
  ];

  // ── Convenience getters ────────────────────────────────────────────────────

  static String get equippedCardBackAsset {
    final item = cardBacks.firstWhere(
      (b) => b.id == _equippedBackId,
      orElse: () => cardBacks.first,
    );
    return item.assetPath ?? 'assets/images/card_back_red.png';
  }

  static Color get equippedCardBackFallback {
    final item = cardBacks.firstWhere(
      (b) => b.id == _equippedBackId,
      orElse: () => cardBacks.first,
    );
    return item.fallbackColor ?? const Color(0xFFB71C1C);
  }

  static Color get equippedBoardColor {
    final item = boardColors.firstWhere(
      (c) => c.id == _equippedColorId,
      orElse: () => boardColors.first,
    );
    return item.boardColor ?? const Color(0xFF4A0E1A);
  }

  static Color get equippedBoardColorLight {
    final item = boardColors.firstWhere(
      (c) => c.id == _equippedColorId,
      orElse: () => boardColors.first,
    );
    return item.boardColorLight ?? const Color(0xFF6B1A2A);
  }

  static bool isBackUnlocked(String id)  => _unlockedBackIds.contains(id);
  static bool isColorUnlocked(String id) => _unlockedColorIds.contains(id);

  // ── Persistence ────────────────────────────────────────────────────────────

  static Future<void> load() async {
    _currentXP        = await SecureStorageService.readInt(_keyXP) ?? 0;
    _unlockedBackIds  = await SecureStorageService.readStringList(_keyUnlockedBacks)  ?? ['classic_red'];
    _unlockedColorIds = await SecureStorageService.readStringList(_keyUnlockedColors) ?? ['burgundy'];
    _equippedBackId   = await SecureStorageService.read(_keyEquippedBack)  ?? 'classic_red';
    _equippedColorId  = await SecureStorageService.read(_keyEquippedColor) ?? 'burgundy';

    // Ensure defaults are always in the unlocked lists (migration safety).
    if (!_unlockedBackIds.contains('classic_red'))  _unlockedBackIds.add('classic_red');
    if (!_unlockedColorIds.contains('burgundy'))    _unlockedColorIds.add('burgundy');

    // Auto-unlock anything the player has already earned.
    _autoUnlock();
  }

  static Future<void> addXP(int amount) async {
    _currentXP += max(0, amount);
    _autoUnlock();
    await SecureStorageService.writeInt(_keyXP, _currentXP);
    await SecureStorageService.writeStringList(_keyUnlockedBacks,  _unlockedBackIds);
    await SecureStorageService.writeStringList(_keyUnlockedColors, _unlockedColorIds);
  }

  static Future<void> equipCardBack(String id) async {
    if (!_unlockedBackIds.contains(id)) return;
    _equippedBackId = id;
    await SecureStorageService.write(_keyEquippedBack, id);
  }

  static Future<void> equipBoardColor(String id) async {
    if (!_unlockedColorIds.contains(id)) return;
    _equippedColorId = id;
    await SecureStorageService.write(_keyEquippedColor, id);
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  static Future<void> reset() async {
    _currentXP        = 0;
    _unlockedBackIds  = ['classic_red'];
    _unlockedColorIds = ['burgundy'];
    _equippedBackId   = 'classic_red';
    _equippedColorId  = 'burgundy';
    await SecureStorageService.delete(_keyXP);
    await SecureStorageService.delete(_keyUnlockedBacks);
    await SecureStorageService.delete(_keyUnlockedColors);
    await SecureStorageService.delete(_keyEquippedBack);
    await SecureStorageService.delete(_keyEquippedColor);
  }

  static void _autoUnlock() {
    final level = playerLevel;
    for (final back in cardBacks) {
      if (back.levelRequired <= level && !_unlockedBackIds.contains(back.id)) {
        _unlockedBackIds.add(back.id);
      }
    }
    for (final color in boardColors) {
      if (color.levelRequired <= level && !_unlockedColorIds.contains(color.id)) {
        _unlockedColorIds.add(color.id);
      }
    }
  }
}
