import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/main.dart';
import 'package:royal_frame/models/game_model.dart';
import 'package:royal_frame/screens/board_screen.dart';
import 'package:royal_frame/services/rating_invitation_platform.dart';
import 'package:royal_frame/services/rating_invitation_platform_io.dart';
import 'package:royal_frame/services/rating_invitation_platform_web.dart';
import 'package:royal_frame/services/rating_invitation_service.dart';
import 'package:royal_frame/utils/localization.dart';
import 'package:royal_frame/widgets/rating_invitation_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shared rating invitation eligibility', () {
    test('the first gameplay session never queues an invitation', () async {
      final store = _MemoryStore();
      final adapter = _FakePlatformAdapter(RatingInvitationPlatform.android);
      final coordinator = _coordinator(store: store, adapter: adapter);

      await coordinator.beginGameplaySession();
      expect(await coordinator.recordCompletedFrameVictory(), isFalse);
      expect(await coordinator.recordCompletedFrameVictory(), isFalse);
      expect(
        await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
        RatingInvitationDispatch.none,
      );
      expect(adapter.androidRequestCount, 0);
      expect(store.state.sessionCount, 1);
      expect(store.state.victoryCount, 2);
    });

    test(
      'first victory is ineligible and a second-session second victory queues',
      () async {
        final store = _MemoryStore();
        final adapter = _FakePlatformAdapter(RatingInvitationPlatform.android);

        final firstSession = _coordinator(store: store, adapter: adapter);
        await firstSession.beginGameplaySession();
        expect(await firstSession.recordCompletedFrameVictory(), isFalse);

        final secondSession = _coordinator(store: store, adapter: adapter);
        await secondSession.beginGameplaySession();
        expect(await secondSession.recordCompletedFrameVictory(), isTrue);
        expect(store.state.sessionCount, 2);
        expect(store.state.victoryCount, 2);
      },
    );

    test(
      'one stable session identifier is shared by start and victory',
      () async {
        final store = _MemoryStore();
        final adapter = _FakePlatformAdapter(RatingInvitationPlatform.android);
        final coordinator = _coordinator(store: store, adapter: adapter);
        final gameplaySession = RatingGameplaySession();
        expect(gameplaySession.identifier, isNull);

        final firstIdentifier = gameplaySession.startNew();
        expect(gameplaySession.startIfNeeded(), same(firstIdentifier));
        await coordinator.beginGameplaySession(sessionToken: firstIdentifier);
        await coordinator.beginGameplaySession(sessionToken: firstIdentifier);
        expect(store.state.sessionCount, 1);
        expect(
          await coordinator.recordCompletedFrameVictory(
            sessionToken: firstIdentifier,
          ),
          isFalse,
        );

        final secondIdentifier = gameplaySession.startNew();
        expect(secondIdentifier, isNot(same(firstIdentifier)));
        await coordinator.beginGameplaySession(sessionToken: secondIdentifier);
        expect(store.state.sessionCount, 2);
        expect(
          await coordinator.recordCompletedFrameVictory(
            sessionToken: secondIdentifier,
          ),
          isTrue,
        );
        expect(store.state.victoryCount, 2);
      },
    );

    test('losses cannot change victory eligibility', () async {
      final store = _MemoryStore(const RatingInvitationState(sessionCount: 1));
      final coordinator = _coordinator(
        store: store,
        adapter: _FakePlatformAdapter(RatingInvitationPlatform.web),
      );

      await coordinator.beginGameplaySession();
      // A loss has no coordinator mutation API.
      expect(store.state.victoryCount, 0);
      expect(
        await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
        RatingInvitationDispatch.none,
      );
    });

    test('exact 30-day cooldown boundary and lifetime limit work', () {
      final now = DateTime.utc(2026, 7, 30, 12);
      final policy = RatingInvitationPolicy(
        clock: () => now,
        isDebugBuild: false,
        debugDefineEnabled: false,
      );
      const platform = RatingInvitationPlatform.android;
      final base = RatingInvitationState(
        sessionCount: 2,
        victoryCount: 2,
        attemptCount: 1,
      );

      expect(
        policy
            .evaluate(
              base.copyWith(
                lastAttemptAt: now
                    .subtract(ratingInvitationCooldown)
                    .add(const Duration(microseconds: 1)),
              ),
              platform,
            )
            .isEligible,
        isFalse,
      );
      expect(
        policy
            .evaluate(
              base.copyWith(
                lastAttemptAt: now.subtract(ratingInvitationCooldown),
              ),
              platform,
            )
            .isEligible,
        isTrue,
      );
      expect(
        policy
            .evaluate(
              base.copyWith(attemptCount: ratingInvitationMaximumAttempts),
              platform,
            )
            .isEligible,
        isFalse,
      );
    });

    test(
      'cooldown and three attempts persist across coordinator reloads',
      () async {
        var now = DateTime.utc(2026, 1, 1);
        final store = _eligibleStore();
        final adapter = _FakePlatformAdapter(RatingInvitationPlatform.android);

        Future<RatingInvitationDispatch> reloadAndCompleteVictory() async {
          final coordinator = _coordinator(
            store: store,
            adapter: adapter,
            clock: () => now,
          );
          await coordinator.beginGameplaySession();
          await coordinator.recordCompletedFrameVictory();
          return coordinator.dispatchPendingInvitation(gameplayUnblocked: true);
        }

        expect(
          await reloadAndCompleteVictory(),
          RatingInvitationDispatch.androidRequested,
        );
        expect(store.state.attemptCount, 1);

        now = now
            .add(ratingInvitationCooldown)
            .subtract(const Duration(microseconds: 1));
        expect(await reloadAndCompleteVictory(), RatingInvitationDispatch.none);
        expect(store.state.attemptCount, 1);

        now = now.add(const Duration(microseconds: 1));
        expect(
          await reloadAndCompleteVictory(),
          RatingInvitationDispatch.androidRequested,
        );
        expect(store.state.attemptCount, 2);

        now = now.add(ratingInvitationCooldown);
        expect(
          await reloadAndCompleteVictory(),
          RatingInvitationDispatch.androidRequested,
        );
        expect(store.state.attemptCount, ratingInvitationMaximumAttempts);

        now = now.add(ratingInvitationCooldown);
        expect(await reloadAndCompleteVictory(), RatingInvitationDispatch.none);
        expect(store.state.attemptCount, ratingInvitationMaximumAttempts);
      },
    );

    test(
      'a blocked overlay keeps the event queued until gameplay unblocks',
      () async {
        final store = _MemoryStore(
          const RatingInvitationState(sessionCount: 1, victoryCount: 1),
        );
        final adapter = _FakePlatformAdapter(RatingInvitationPlatform.android);
        final coordinator = _coordinator(store: store, adapter: adapter);
        await coordinator.beginGameplaySession();
        expect(await coordinator.recordCompletedFrameVictory(), isTrue);

        expect(
          await coordinator.dispatchPendingInvitation(gameplayUnblocked: false),
          RatingInvitationDispatch.none,
        );
        expect(adapter.androidRequestCount, 0);

        expect(
          await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
          RatingInvitationDispatch.androidRequested,
        );
        expect(adapter.androidRequestCount, 1);
      },
    );
  });

  group('platform dispatch and persistence', () {
    test(
      'Android completion counts once without recording review submission',
      () async {
        final store = _eligibleStore();
        final adapter = _FakePlatformAdapter(
          RatingInvitationPlatform.android,
          androidRequestResult: true,
        );
        final coordinator = _coordinator(store: store, adapter: adapter);
        await coordinator.beginGameplaySession();
        await coordinator.recordCompletedFrameVictory();

        expect(
          await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
          RatingInvitationDispatch.androidRequested,
        );
        expect(adapter.androidRequestCount, 1);
        expect(adapter.webLaunchCount, 0);
        expect(store.state.attemptCount, 1);
        expect(store.state.lastAttemptAt, isNotNull);
        // The persisted state intentionally has no "reviewed", dialog-shown,
        // rating, or submission field.
        expect(store.state.webPlayStoreLaunchSucceeded, isFalse);
      },
    );

    test(
      'Android request failure is silent and does not count an attempt',
      () async {
        final store = _eligibleStore();
        final adapter = _FakePlatformAdapter(
          RatingInvitationPlatform.android,
          androidRequestResult: false,
        );
        final coordinator = _coordinator(store: store, adapter: adapter);
        await coordinator.beginGameplaySession();
        await coordinator.recordCompletedFrameVictory();

        expect(
          await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
          RatingInvitationDispatch.none,
        );
        expect(store.state.attemptCount, 0);
        expect(adapter.webLaunchCount, 0);
      },
    );

    test(
      'Android adapter exception is contained without gameplay state',
      () async {
        final store = _eligibleStore();
        final adapter = _FakePlatformAdapter(
          RatingInvitationPlatform.android,
          throwAndroidRequest: true,
        );
        final coordinator = _coordinator(store: store, adapter: adapter);
        await coordinator.beginGameplaySession();
        await coordinator.recordCompletedFrameVictory();

        expect(
          await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
          RatingInvitationDispatch.none,
        );
        expect(store.state.attemptCount, 0);
      },
    );

    test(
      'Web counts an attempt only after presentation is confirmed',
      () async {
        final store = _eligibleStore();
        final adapter = _FakePlatformAdapter(RatingInvitationPlatform.web);
        final coordinator = _coordinator(store: store, adapter: adapter);
        await coordinator.beginGameplaySession();
        await coordinator.recordCompletedFrameVictory();

        expect(
          await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
          RatingInvitationDispatch.webReadyToPresent,
        );
        expect(store.state.attemptCount, 0);
        expect(await coordinator.confirmWebInvitationPresented(), isTrue);
        expect(store.state.attemptCount, 1);
        expect(adapter.androidRequestCount, 0);
        expect(adapter.webLaunchCount, 0);
      },
    );

    test(
      'cancelled Web presentation is retried without counting an attempt',
      () async {
        final store = _eligibleStore();
        final adapter = _FakePlatformAdapter(RatingInvitationPlatform.web);
        final coordinator = _coordinator(store: store, adapter: adapter);
        await coordinator.beginGameplaySession();
        await coordinator.recordCompletedFrameVictory();

        expect(
          await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
          RatingInvitationDispatch.webReadyToPresent,
        );
        coordinator.cancelWebInvitationPresentation();
        expect(store.state.attemptCount, 0);

        expect(
          await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
          RatingInvitationDispatch.webReadyToPresent,
        );
        expect(await coordinator.confirmWebInvitationPresented(), isTrue);
        expect(store.state.attemptCount, 1);
      },
    );

    test('successful Web launch permanently suppresses after reload', () async {
      var now = DateTime.utc(2026, 1, 1);
      final store = _eligibleStore();
      final adapter = _FakePlatformAdapter(
        RatingInvitationPlatform.web,
        webLaunchResult: true,
      );
      var coordinator = _coordinator(
        store: store,
        adapter: adapter,
        clock: () => now,
      );
      await coordinator.beginGameplaySession();
      await coordinator.recordCompletedFrameVictory();
      await coordinator.dispatchPendingInvitation(gameplayUnblocked: true);
      await coordinator.confirmWebInvitationPresented();

      expect(await coordinator.launchWebPlayStore(), isTrue);
      expect(adapter.webLaunchCount, 1);
      expect(store.state.webPlayStoreLaunchSucceeded, isTrue);

      now = now.add(ratingInvitationCooldown);
      coordinator = _coordinator(
        store: store,
        adapter: adapter,
        clock: () => now,
      );
      await coordinator.beginGameplaySession();
      expect(await coordinator.recordCompletedFrameVictory(), isFalse);
      expect(
        await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
        RatingInvitationDispatch.none,
      );
    });

    test(
      'failed Web launch remains eligible after the normal cooldown',
      () async {
        var now = DateTime.utc(2026, 1, 1);
        final store = _eligibleStore();
        final adapter = _FakePlatformAdapter(
          RatingInvitationPlatform.web,
          webLaunchResult: false,
        );
        var coordinator = _coordinator(
          store: store,
          adapter: adapter,
          clock: () => now,
        );
        await coordinator.beginGameplaySession();
        await coordinator.recordCompletedFrameVictory();
        await coordinator.dispatchPendingInvitation(gameplayUnblocked: true);
        await coordinator.confirmWebInvitationPresented();

        expect(await coordinator.launchWebPlayStore(), isFalse);
        expect(store.state.webPlayStoreLaunchSucceeded, isFalse);
        expect(store.state.attemptCount, 1);

        now = now.add(ratingInvitationCooldown);
        coordinator = _coordinator(
          store: store,
          adapter: adapter,
          clock: () => now,
        );
        await coordinator.beginGameplaySession();
        expect(await coordinator.recordCompletedFrameVictory(), isTrue);
        expect(
          await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
          RatingInvitationDispatch.webReadyToPresent,
        );
        expect(await coordinator.confirmWebInvitationPresented(), isTrue);
        expect(store.state.attemptCount, 2);
      },
    );

    test('listing URL is exact', () {
      expect(
        ratingInvitationGooglePlayUrl,
        'https://play.google.com/store/apps/details?id=com.itay.royalframegame',
      );
    });
  });

  group('SharedPreferences persistence', () {
    test('state survives store reconstruction', () async {
      SharedPreferences.setMockInitialValues({});
      final savedAt = DateTime.utc(2026, 4, 5, 6, 7, 8);
      final store = SharedPreferencesRatingInvitationStore();
      await store.save(
        RatingInvitationState(
          sessionCount: 4,
          victoryCount: 3,
          lastAttemptAt: savedAt,
          attemptCount: 2,
          webPlayStoreLaunchSucceeded: true,
        ),
      );

      final reconstructedStore = SharedPreferencesRatingInvitationStore();
      final loaded = await reconstructedStore.load();
      expect(loaded.sessionCount, 4);
      expect(loaded.victoryCount, 3);
      expect(loaded.lastAttemptAt, savedAt);
      expect(loaded.attemptCount, 2);
      expect(loaded.webPlayStoreLaunchSucceeded, isTrue);
    });

    test('legacy and malformed values fail safe', () async {
      final legacyDate = DateTime.utc(2026, 1, 2);
      SharedPreferences.setMockInitialValues({
        'ratingInvitationSessionCount': '4',
        'ratingInvitationVictoryCount': -2,
        'ratingInvitationLastAttemptUtc': legacyDate.millisecondsSinceEpoch,
        'ratingInvitationAttemptCount': 'not-a-number',
        'ratingInvitationWebPlayStoreLaunchSucceeded': 'yes',
      });

      final store = SharedPreferencesRatingInvitationStore();
      final loaded = await store.load();
      expect(loaded.sessionCount, 4);
      expect(loaded.victoryCount, 0);
      expect(loaded.lastAttemptAt, legacyDate);
      expect(loaded.attemptCount, 0);
      expect(loaded.webPlayStoreLaunchSucceeded, isFalse);
    });

    test('malformed date does not break state loading', () async {
      SharedPreferences.setMockInitialValues({
        'ratingInvitationLastAttemptUtc': 'not-a-date',
      });

      final store = SharedPreferencesRatingInvitationStore();
      final loaded = await store.load();
      expect(loaded.lastAttemptAt, isNull);
    });
  });

  group('concrete Web browser launch', () {
    test('opened window is reported synchronously', () async {
      var called = false;
      final adapter = WebRatingInvitationPlatformAdapter(
        browserOpen: (url, target) {
          called = true;
          expect(url, ratingInvitationGooglePlayUrl);
          expect(target, '_blank');
          return Object();
        },
      );

      final result = adapter.launchWebListing();
      expect(called, isTrue);
      expect(await result, isTrue);
    });

    test('blocked popup and browser exception report failure', () async {
      final blocked = WebRatingInvitationPlatformAdapter(
        browserOpen: (url, target) => null,
      );
      final throwing = WebRatingInvitationPlatformAdapter(
        browserOpen: (url, target) => throw StateError('browser failure'),
      );

      expect(await blocked.launchWebListing(), isFalse);
      expect(await throwing.launchWebListing(), isFalse);
    });

    test('blocked launch does not suppress a later confirmed launch', () async {
      var now = DateTime.utc(2026, 1, 1);
      var browserAllowsOpen = false;
      final store = _eligibleStore();
      final adapter = WebRatingInvitationPlatformAdapter(
        browserOpen: (url, target) {
          return browserAllowsOpen ? Object() : null;
        },
      );
      var coordinator = _coordinator(
        store: store,
        adapter: adapter,
        clock: () => now,
      );
      final firstGame = Object();

      await coordinator.beginGameplaySession(sessionToken: firstGame);
      await coordinator.recordCompletedFrameVictory(sessionToken: firstGame);
      await coordinator.dispatchPendingInvitation(gameplayUnblocked: true);
      await coordinator.confirmWebInvitationPresented();
      expect(await coordinator.launchWebPlayStore(), isFalse);
      expect(store.state.webPlayStoreLaunchSucceeded, isFalse);

      now = now.add(ratingInvitationCooldown);
      browserAllowsOpen = true;
      coordinator = _coordinator(
        store: store,
        adapter: adapter,
        clock: () => now,
      );
      final secondGame = Object();
      await coordinator.beginGameplaySession(sessionToken: secondGame);
      expect(
        await coordinator.recordCompletedFrameVictory(sessionToken: secondGame),
        isTrue,
      );
      expect(
        await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
        RatingInvitationDispatch.webReadyToPresent,
      );
      expect(await coordinator.confirmWebInvitationPresented(), isTrue);
      expect(await coordinator.launchWebPlayStore(), isTrue);
      expect(store.state.webPlayStoreLaunchSucceeded, isTrue);
    });

    test('thrown browser launch does not persist suppression', () async {
      final store = _eligibleStore();
      final adapter = WebRatingInvitationPlatformAdapter(
        browserOpen: (url, target) => throw StateError('browser failure'),
      );
      final coordinator = _coordinator(store: store, adapter: adapter);
      final game = Object();

      await coordinator.beginGameplaySession(sessionToken: game);
      await coordinator.recordCompletedFrameVictory(sessionToken: game);
      await coordinator.dispatchPendingInvitation(gameplayUnblocked: true);
      await coordinator.confirmWebInvitationPresented();

      expect(await coordinator.launchWebPlayStore(), isFalse);
      expect(store.state.webPlayStoreLaunchSucceeded, isFalse);
    });
  });

  group('Android method channel adapter', () {
    const channel = MethodChannel('com.itay.royalframegame/in_app_review_test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('reports successful native launch-task completion', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'requestReview');
        return true;
      });
      final adapter = AndroidRatingInvitationAdapter(channel: channel);

      expect(await adapter.requestAndroidReview(), isTrue);
    });

    test('contains native false and channel failures', () async {
      var returnFailure = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (returnFailure) return false;
        throw PlatformException(code: 'in_app_review_failed');
      });
      final adapter = AndroidRatingInvitationAdapter(channel: channel);

      expect(await adapter.requestAndroidReview(), isFalse);
      returnFailure = false;
      expect(await adapter.requestAndroidReview(), isFalse);
    });
  });

  group('debug and startup gates', () {
    test(
      'debug define forces without rewriting attempt policy state',
      () async {
        final store = _MemoryStore();
        final coordinator = _coordinator(
          store: store,
          adapter: _FakePlatformAdapter(RatingInvitationPlatform.web),
          isDebugBuild: true,
          debugDefineEnabled: true,
        );

        await coordinator.beginGameplaySession();
        expect(
          await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
          RatingInvitationDispatch.webReadyToPresent,
        );
        expect(await coordinator.confirmWebInvitationPresented(), isTrue);
        expect(store.state.victoryCount, 0);
        expect(store.state.attemptCount, 0);
        expect(store.state.lastAttemptAt, isNull);
      },
    );

    test(
      'debug override remains non-persistent when production eligible',
      () async {
        final store = _MemoryStore(
          const RatingInvitationState(sessionCount: 1, victoryCount: 2),
        );
        final coordinator = _coordinator(
          store: store,
          adapter: _FakePlatformAdapter(RatingInvitationPlatform.web),
          isDebugBuild: true,
          debugDefineEnabled: true,
        );

        await coordinator.beginGameplaySession();
        expect(
          await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
          RatingInvitationDispatch.webReadyToPresent,
        );
        expect(await coordinator.confirmWebInvitationPresented(), isTrue);
        expect(store.state.sessionCount, 2);
        expect(store.state.victoryCount, 2);
        expect(store.state.attemptCount, 0);
        expect(store.state.lastAttemptAt, isNull);
      },
    );

    test('debug forcing is re-armed for each new game token', () async {
      final store = _MemoryStore();
      final coordinator = _coordinator(
        store: store,
        adapter: _FakePlatformAdapter(RatingInvitationPlatform.web),
        isDebugBuild: true,
        debugDefineEnabled: true,
      );
      final firstGame = Object();
      final secondGame = Object();

      await coordinator.beginGameplaySession(sessionToken: firstGame);
      expect(
        await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
        RatingInvitationDispatch.webReadyToPresent,
      );
      expect(await coordinator.confirmWebInvitationPresented(), isTrue);
      coordinator.dismissWebInvitation();

      await coordinator.beginGameplaySession(sessionToken: secondGame);
      expect(store.state.sessionCount, 2);
      expect(
        await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
        RatingInvitationDispatch.webReadyToPresent,
      );
      expect(store.state.attemptCount, 0);
    });

    test('release ignores the debug define', () async {
      final store = _MemoryStore();
      final coordinator = _coordinator(
        store: store,
        adapter: _FakePlatformAdapter(RatingInvitationPlatform.web),
        isDebugBuild: false,
        debugDefineEnabled: true,
      );

      await coordinator.beginGameplaySession();
      expect(
        await coordinator.dispatchPendingInvitation(gameplayUnblocked: true),
        RatingInvitationDispatch.none,
      );
      expect(await coordinator.recordCompletedFrameVictory(), isFalse);
    });

    testWidgets('forced-update screen does not start a gameplay session', (
      tester,
    ) async {
      final store = _MemoryStore();
      final adapter = _FakePlatformAdapter(RatingInvitationPlatform.android);
      final coordinator = _coordinator(
        store: store,
        adapter: adapter,
        isDebugBuild: true,
        debugDefineEnabled: true,
      );

      await tester.pumpWidget(
        RoyalFrameApp(
          updateRequired: true,
          initialName: 'Player',
          ratingInvitationCoordinator: coordinator,
        ),
      );
      await tester.pump();

      expect(find.text('Update the game to continue.'), findsOneWidget);
      expect(store.saveCount, 0);
      expect(store.state.sessionCount, 0);
      expect(find.byType(RatingInvitationOverlay), findsNothing);
      expect(adapter.androidRequestCount, 0);
    });

    testWidgets('welcome/startup recovery does not start a gameplay session', (
      tester,
    ) async {
      final store = _MemoryStore();
      final coordinator = _coordinator(
        store: store,
        adapter: _FakePlatformAdapter(RatingInvitationPlatform.android),
      );

      await tester.pumpWidget(
        RoyalFrameApp(
          initialName: null,
          ratingInvitationCoordinator: coordinator,
          welcomeBuilder: (_) =>
              const Scaffold(body: Text('Welcome test seam')),
        ),
      );
      await tester.pump();

      expect(find.text('Welcome test seam'), findsOneWidget);
      expect(store.saveCount, 0);
      expect(store.state.sessionCount, 0);
    });
  });

  group('BoardScreen terminal-event isolation', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'royalFrameTutorialV3Done': true,
      });
    });

    testWidgets('a restored loss does not create rating eligibility', (
      tester,
    ) async {
      final game = GameState.newGame()
        ..phase = Phase.gameOver
        ..endTime = DateTime.utc(2026, 7, 30);
      final store = _MemoryStore(
        const RatingInvitationState(sessionCount: 1, victoryCount: 1),
      );
      final adapter = _FakePlatformAdapter(RatingInvitationPlatform.android);
      final coordinator = _coordinator(store: store, adapter: adapter);

      await tester.pumpWidget(
        MaterialApp(
          home: BoardScreen(
            existingGame: game,
            initialLang: AppLang.en,
            ratingInvitationCoordinator: coordinator,
          ),
        ),
      );
      await tester.pump();

      expect(store.state.sessionCount, 2);
      expect(store.state.victoryCount, 1);
      expect(store.state.attemptCount, 0);
      expect(adapter.androidRequestCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('placeholder waits and real new games rotate once', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _MemoryStore();
      final adapter = _FakePlatformAdapter(RatingInvitationPlatform.android);
      final coordinator = _coordinator(
        store: store,
        adapter: adapter,
        isDebugBuild: true,
        debugDefineEnabled: true,
      );
      final gameplaySession = RatingGameplaySession();

      Widget board() {
        return MaterialApp(
          home: BoardScreen(
            key: const ValueKey<String>('active-board'),
            existingGame: GameState.newGame(seed: 0),
            showNewGamePicker: true,
            initialLang: AppLang.en,
            ratingInvitationCoordinator: coordinator,
            ratingGameplaySession: gameplaySession,
          ),
        );
      }

      await tester.pumpWidget(board());
      await tester.pump();
      expect(find.text('START GAME'), findsOneWidget);
      expect(gameplaySession.identifier, isNull);
      expect(store.state.sessionCount, 0);

      await tester.tap(find.text('START GAME'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      final firstIdentifier = gameplaySession.identifier;
      expect(firstIdentifier, isNotNull);
      expect(store.state.sessionCount, 1);
      expect(adapter.androidRequestCount, 1);

      await tester.pumpWidget(board());
      await tester.pump();
      expect(store.state.sessionCount, 1);

      await tester.tap(find.byTooltip('New Game'));
      await tester.pump();
      expect(find.text('START GAME'), findsOneWidget);
      await tester.tap(find.text('START GAME'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(store.state.sessionCount, 2);
      expect(gameplaySession.identifier, isNot(same(firstIdentifier)));
      expect(adapter.androidRequestCount, 2);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('clone resume keeps one session and a separate game adds one', (
      tester,
    ) async {
      final firstGame = GameState.newGame(seed: 1);
      final store = _MemoryStore();
      final coordinator = _coordinator(
        store: store,
        adapter: _FakePlatformAdapter(RatingInvitationPlatform.android),
      );
      final firstSession = RatingGameplaySession();

      Widget board(String key, GameState game, RatingGameplaySession session) {
        return MaterialApp(
          home: BoardScreen(
            key: ValueKey<String>(key),
            existingGame: game,
            initialLang: AppLang.en,
            ratingInvitationCoordinator: coordinator,
            ratingGameplaySession: session,
          ),
        );
      }

      await tester.pumpWidget(board('first', firstGame, firstSession));
      await tester.pump();
      final firstIdentifier = firstSession.identifier;
      expect(firstIdentifier, isNotNull);
      expect(store.state.sessionCount, 1);

      await tester.pumpWidget(board('first', firstGame, firstSession));
      await tester.pump();
      expect(firstSession.identifier, same(firstIdentifier));
      expect(store.state.sessionCount, 1);

      // Undo replaces BoardScreen's GameState with a clone. Reconstructing the
      // route with that clone and the stable owner must keep the same session.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        board('resumed-clone', firstGame.clone(), firstSession),
      );
      await tester.pump();
      expect(firstSession.identifier, same(firstIdentifier));
      expect(store.state.sessionCount, 1);

      final secondSession = RatingGameplaySession();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        board('separate-game', GameState.newGame(seed: 2), secondSession),
      );
      await tester.pump();
      expect(secondSession.identifier, isNot(same(firstIdentifier)));
      expect(store.state.sessionCount, 2);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Web invitation presentation', () {
    testWidgets('English copy explicitly labels Android and Google Play', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                RatingInvitationOverlay(
                  lang: AppLang.en,
                  onRateAndroidGame: () {},
                  onDismiss: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Rate the Android game on Google Play'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('Hebrew copy uses RTL and usable actions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                RatingInvitationOverlay(
                  lang: AppLang.he,
                  onRateAndroidGame: () {},
                  onDismiss: () {},
                ),
              ],
            ),
          ),
        ),
      );

      final action = find.text('דירוג משחק ה-Android ב-Google Play');
      expect(action, findsOneWidget);
      expect(
        tester.getSize(find.byType(OutlinedButton)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(48),
      );
      expect(Directionality.of(tester.element(action)), TextDirection.rtl);
    });

    testWidgets('actions remain reachable in small landscape with large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(667, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var rated = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(667, 320),
              padding: EdgeInsets.only(left: 20, right: 20),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: Stack(
                children: [
                  RatingInvitationOverlay(
                    lang: AppLang.en,
                    onRateAndroidGame: () => rated = true,
                    onDismiss: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final action = find.text('Rate the Android game on Google Play');
      await tester.ensureVisible(action);
      await tester.tap(action);
      expect(rated, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}

RatingInvitationCoordinator _coordinator({
  required RatingInvitationStore store,
  required RatingInvitationPlatformAdapter adapter,
  DateTime Function()? clock,
  bool isDebugBuild = false,
  bool debugDefineEnabled = false,
}) {
  return RatingInvitationCoordinator(
    store: store,
    platformAdapter: adapter,
    policy: RatingInvitationPolicy(
      clock: clock ?? () => DateTime.utc(2026, 7, 30),
      isDebugBuild: isDebugBuild,
      debugDefineEnabled: debugDefineEnabled,
    ),
  );
}

_MemoryStore _eligibleStore() {
  return _MemoryStore(
    const RatingInvitationState(sessionCount: 1, victoryCount: 1),
  );
}

class _MemoryStore implements RatingInvitationStore {
  RatingInvitationState state;
  int saveCount = 0;

  _MemoryStore([this.state = const RatingInvitationState()]);

  @override
  Future<RatingInvitationState> load() async => state;

  @override
  Future<void> save(RatingInvitationState state) async {
    saveCount++;
    this.state = state;
  }
}

class _FakePlatformAdapter implements RatingInvitationPlatformAdapter {
  @override
  final RatingInvitationPlatform platform;
  final bool androidRequestResult;
  final bool webLaunchResult;
  final bool throwAndroidRequest;

  int androidRequestCount = 0;
  int webLaunchCount = 0;

  _FakePlatformAdapter(
    this.platform, {
    this.androidRequestResult = true,
    this.webLaunchResult = true,
    this.throwAndroidRequest = false,
  });

  @override
  Future<bool> launchWebListing() async {
    webLaunchCount++;
    return webLaunchResult;
  }

  @override
  Future<bool> requestAndroidReview() async {
    androidRequestCount++;
    if (throwAndroidRequest) throw StateError('injected adapter failure');
    return androidRequestResult;
  }
}
