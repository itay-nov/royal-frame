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
        authenticatedDisplayName: 'Arthur',
        playerDocExists: (_) async => false,
        ensurePlayerDoc: (uid, _) async => ensuredUid = uid,
        persistPlayerName: (_) async {},
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
        authenticatedDisplayName: 'Guinevere',
        playerDocExists: (_) async => null,
        ensurePlayerDoc: (_, _) async => ensured = true,
        persistPlayerName: (_) async {},
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
      authenticatedDisplayName: null,
      playerDocExists: (_) async => fail('must not query without a user'),
      ensurePlayerDoc: (_, _) async => fail('must not heal without a user'),
      persistPlayerName: (_) async => fail('must not persist without a user'),
      recoverSession: (savedName) async => '$savedName recovered',
    );

    expect(name, 'Lancelot recovered');
  });

  test(
    'a live identity without a cached name is restored, not replaced',
    () async {
      var persistedName = '';
      var ensuredName = '';
      var recovered = false;

      final name = await AppInitializer.validateSessionStateForTesting(
        savedName: null,
        authenticatedUid: 'google-user-2',
        authenticatedDisplayName: '  Galahad  ',
        playerDocExists: (_) async => false,
        ensurePlayerDoc: (_, name) async => ensuredName = name,
        persistPlayerName: (name) async => persistedName = name,
        recoverSession: (_) async {
          recovered = true;
          return 'replacement';
        },
      );

      expect(name, 'Galahad');
      expect(persistedName, 'Galahad');
      expect(ensuredName, 'Galahad');
      expect(recovered, isFalse);
    },
  );
}
