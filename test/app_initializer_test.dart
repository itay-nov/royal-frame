import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/services/app_initializer.dart';

void main() {
  setUp(AppInitializer.resetAppCheckActivationForTesting);

  test('successful App Check activation is cached', () async {
    var activations = 0;

    Future<void> activate() async {
      activations++;
    }

    await AppInitializer.activateAppCheckOnceForTesting(activate);
    await AppInitializer.activateAppCheckOnceForTesting(activate);

    expect(activations, 1);
  });

  test('failed App Check activation can be retried', () async {
    var activations = 0;

    Future<void> activate() async {
      activations++;
      if (activations == 1) throw StateError('activation failed');
    }

    await expectLater(
      AppInitializer.activateAppCheckOnceForTesting(activate),
      throwsStateError,
    );
    await AppInitializer.activateAppCheckOnceForTesting(activate);

    expect(activations, 2);
  });

  group('authenticated session validation', () {
    test(
      'heals a missing player document without replacing the identity',
      () async {
        var ensuredUid = '';
        var recovered = false;

        final name = await AppInitializer.validateSessionStateForTesting(
          savedName: 'Arthur',
          authenticatedUid: 'live-user',
          authenticatedDisplayName: null,
          playerDocExists: (_) async => false,
          ensurePlayerDoc: (uid, _) async => ensuredUid = uid,
          persistPlayerName: (_) async {},
          recoverSession: (_) async {
            recovered = true;
            return null;
          },
        );

        expect(name, 'Arthur');
        expect(ensuredUid, 'live-user');
        expect(recovered, isFalse);
      },
    );

    test('unknown server state is non-destructive', () async {
      var ensured = false;
      var persisted = false;

      final name = await AppInitializer.validateSessionStateForTesting(
        savedName: 'Guinevere',
        authenticatedUid: 'live-user',
        authenticatedDisplayName: null,
        playerDocExists: (_) async => null,
        ensurePlayerDoc: (_, __) async => ensured = true,
        persistPlayerName: (_) async => persisted = true,
        recoverSession: (_) async => fail('must not replace a live identity'),
      );

      expect(name, 'Guinevere');
      expect(ensured, isFalse);
      expect(persisted, isFalse);
    });

    test(
      'a cached session without an authenticated user uses recovery',
      () async {
        var recoveredName = '';

        final name = await AppInitializer.validateSessionStateForTesting(
          savedName: 'Lancelot',
          authenticatedUid: null,
          authenticatedDisplayName: null,
          playerDocExists: (_) async => fail('no user should skip lookup'),
          ensurePlayerDoc: (_, __) async {},
          persistPlayerName: (_) async {},
          recoverSession: (savedName) async {
            recoveredName = savedName;
            return savedName;
          },
        );

        expect(name, 'Lancelot');
        expect(recoveredName, 'Lancelot');
      },
    );

    test('recovers and persists a bounded name for a live identity', () async {
      final events = <String>[];
      String? persistedName;

      final name = await AppInitializer.validateSessionStateForTesting(
        savedName: null,
        authenticatedUid: 'live-user',
        authenticatedDisplayName: 'A' * 40,
        playerDocExists: (_) async {
          events.add('server');
          return true;
        },
        ensurePlayerDoc: (_, __) async => events.add('ensure'),
        persistPlayerName: (value) async {
          events.add('persist');
          persistedName = value;
        },
        recoverSession: (_) async => fail('must not replace a live identity'),
      );

      expect(name, 'A' * 30);
      expect(persistedName, 'A' * 30);
      expect(events, ['server', 'persist']);
    });
  });
}
