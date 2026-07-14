import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/services/app_initializer.dart';

void main() {
  test(
    'a live identity with a missing player document is healed in place',
    () async {
      var ensuredUid = '';
      var recovered = false;

      final name = await AppInitializer.validateSessionStateForTesting(
        savedName: 'Arthur',
        authenticatedUid: 'google-user-1',
        playerDocExists: (_) async => false,
        ensurePlayerDoc: (uid, _) async => ensuredUid = uid,
        recoverSession: (_) async {
          recovered = true;
          return 'replacement';
        },
      );

      expect(name, 'Arthur');
      expect(ensuredUid, 'google-user-1');
      expect(recovered, isFalse);
    },
  );

  test(
    'an unknown server result preserves the authenticated identity',
    () async {
      var ensured = false;
      var recovered = false;

      final name = await AppInitializer.validateSessionStateForTesting(
        savedName: 'Guinevere',
        authenticatedUid: 'phone-user-1',
        playerDocExists: (_) async => null,
        ensurePlayerDoc: (_, _) async => ensured = true,
        recoverSession: (_) async {
          recovered = true;
          return null;
        },
      );

      expect(name, 'Guinevere');
      expect(ensured, isFalse);
      expect(recovered, isFalse);
    },
  );

  test('a cached session without an auth user uses recovery', () async {
    final name = await AppInitializer.validateSessionStateForTesting(
      savedName: 'Lancelot',
      authenticatedUid: null,
      playerDocExists: (_) async => fail('must not query without a user'),
      ensurePlayerDoc: (_, _) async => fail('must not heal without a user'),
      recoverSession: (savedName) async => '$savedName recovered',
    );

    expect(name, 'Lancelot recovered');
  });
}
