import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/utils/player_name_policy.dart';

void main() {
  test('empty and whitespace-only names are invalid', () {
    expect(PlayerNamePolicy.isValid(''), isFalse);
    expect(PlayerNamePolicy.isValid('   '), isFalse);
    expect(PlayerNamePolicy.sanitize('   '), 'Player');
  });

  test('English and Hebrew names are normalized', () {
    expect(PlayerNamePolicy.normalize('  Arthur  '), 'Arthur');
    expect(PlayerNamePolicy.normalize('  ארתור  '), 'ארתור');
    expect(PlayerNamePolicy.isValid('Arthur'), isTrue);
    expect(PlayerNamePolicy.isValid('ארתור'), isTrue);
  });

  test('emoji and combining marks count as user-perceived characters', () {
    const family = '👨‍👩‍👧‍👦';
    const combined = 'é';

    expect(PlayerNamePolicy.characterCount(family), 1);
    expect(PlayerNamePolicy.characterCount(combined), 1);
    expect(PlayerNamePolicy.isValid(family * 30), isTrue);
    expect(PlayerNamePolicy.isValid(family * 31), isFalse);
  });

  test('exactly 30 characters pass and 31 are truncated consistently', () {
    expect(PlayerNamePolicy.isValid('A' * 30), isTrue);
    expect(PlayerNamePolicy.isValid('A' * 31), isFalse);
    expect(PlayerNamePolicy.sanitize('A' * 31), 'A' * 30);
    expect(
      PlayerNamePolicy.characterCount(PlayerNamePolicy.sanitize('A' * 31)),
      30,
    );
  });
}
