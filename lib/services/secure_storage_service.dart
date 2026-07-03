import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper around [FlutterSecureStorage] that adds typed helpers for
/// int, bool, and `List<String>` — since the underlying store is String-only.
///
/// On Android: AES-256 via EncryptedSharedPreferences (hardware-backed key).
/// On iOS: Keychain Services.
/// On Web: localStorage namespaced + obfuscated (best-effort).
///
/// Only use this for sensitive game data (scores, progress, unlocks).
/// Non-sensitive settings (mute, language, UI prefs) stay in SharedPreferences.
class SecureStorageService {
  SecureStorageService._();

  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    webOptions: WebOptions(dbName: 'royal_frame_secure', publicKey: 'rf_pub'),
  );

  // ── Raw string ──────────────────────────────────────────────────────────────

  static Future<String?> read(String key) => _store.read(key: key);

  static Future<void> write(String key, String value) =>
      _store.write(key: key, value: value);

  static Future<void> delete(String key) => _store.delete(key: key);

  // ── Typed helpers ───────────────────────────────────────────────────────────

  static Future<int?> readInt(String key) async {
    final v = await _store.read(key: key);
    return v == null ? null : int.tryParse(v);
  }

  static Future<void> writeInt(String key, int value) =>
      _store.write(key: key, value: value.toString());

  static Future<bool?> readBool(String key) async {
    final v = await _store.read(key: key);
    return v == null ? null : v == 'true';
  }

  static Future<void> writeBool(String key, bool value) =>
      _store.write(key: key, value: value.toString());

  /// Encodes a string list as NUL-delimited bytes — safe because our IDs
  /// (e.g. 'classic_red', 'burgundy') never contain the NUL character.
  static Future<List<String>?> readStringList(String key) async {
    final v = await _store.read(key: key);
    if (v == null || v.isEmpty) return null;
    return v.split('\x00');
  }

  static Future<void> writeStringList(String key, List<String> values) =>
      _store.write(key: key, value: values.join('\x00'));
}
