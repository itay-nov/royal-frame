import 'package:flutter/widgets.dart';

/// One shared rule for player names across authentication and persistence.
abstract final class PlayerNamePolicy {
  static const int maxCharacters = 30;
  static const String fallbackName = 'Player';

  static String normalize(String? value) => (value ?? '').trim();

  static int characterCount(String? value) => normalize(value).characters.length;

  static bool isValid(String? value) {
    final normalized = normalize(value);
    return normalized.isNotEmpty &&
        normalized.characters.length <= maxCharacters;
  }

  static String sanitize(String? value, {String fallback = fallbackName}) {
    final normalized = normalize(value);
    final candidate = normalized.isEmpty ? normalize(fallback) : normalized;
    final safeCandidate = candidate.isEmpty ? fallbackName : candidate;
    return safeCandidate.characters.take(maxCharacters).toString();
  }
}
