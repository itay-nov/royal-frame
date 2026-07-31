import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:royal_frame/screens/welcome_screen.dart';
import 'package:royal_frame/services/auth_service.dart';
import 'package:royal_frame/services/app_initializer.dart';
import 'package:royal_frame/utils/phone_verification_attempt.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthService extends AuthService {
  int anonymousCalls = 0;
  Duration codeSentDelay = Duration.zero;
  Object? googleError;

  @override
  Future<UserCredential?> signInAnonymously(String displayName) async {
    anonymousCalls++;
    return null;
  }

  @override
  Future<UserCredential?> signInWithGoogle() async {
    final error = googleError;
    if (error != null) throw error;
    return null;
  }

  @override
  Future<void> sendSmsCodeNative({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(UserCredential credential) onAutoVerified,
    required void Function(String error) onError,
  }) async {
    unawaited(
      Future<void>.delayed(
        codeSentDelay,
        () => onCodeSent('test-verification', null),
      ),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('empty guest name is rejected before authentication', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(home: WelcomeScreen(authService: auth)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play as Guest'));
    await tester.pump();

    expect(auth.anonymousCalls, 0);
    expect(find.text('Please enter a name'), findsOneWidget);
  });

  testWidgets('player-name input enforces the 30-character maximum', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(home: WelcomeScreen(authService: auth)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'A' * 31);
    expect(find.text('A' * 30), findsOneWidget);
  });

  testWidgets('native phone flow waits for a delayed code callback', (
    tester,
  ) async {
    final auth = _FakeAuthService()
      ..codeSentDelay = const Duration(milliseconds: 250);
    await tester.pumpWidget(
      MaterialApp(home: WelcomeScreen(authService: auth)),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Continue with Phone'));
    await tester.tap(find.text('Continue with Phone'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '+15555550100');
    await tester.tap(find.text('Send Code'));
    await tester.pump();

    expect(find.text('Verification Code'), findsNothing);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('Verification Code'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  test('automatic and manual phone completion cannot claim one attempt', () {
    final attempt = PhoneVerificationAttempt();

    expect(attempt.claimAuthentication(), isTrue);
    expect(attempt.claimAuthentication(), isFalse);
  });

  test('Google cancellation, interruption, and failure are distinct', () {
    expect(
      AuthService.classifyGoogleSignInFailure(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      ),
      GoogleSignInFailureKind.canceled,
    );
    expect(
      AuthService.classifyGoogleSignInFailure(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.interrupted,
        ),
      ),
      GoogleSignInFailureKind.interrupted,
    );
    expect(
      AuthService.classifyGoogleSignInFailure(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
        ),
      ),
      GoogleSignInFailureKind.failure,
    );
  });

  test('Web Google cancellation and operational failure remain distinct', () async {
    final canceled = await AuthService.runWebGoogleSignInForTesting<Object>(
      () => Future<Object>.error(
        FirebaseAuthException(code: 'popup-closed-by-user'),
      ),
    );
    expect(canceled, isNull);

    await expectLater(
      AuthService.runWebGoogleSignInForTesting<Object>(
        () => Future<Object>.error(
          FirebaseAuthException(code: 'network-request-failed'),
        ),
      ),
      throwsA(isA<FirebaseAuthException>()),
    );

    await expectLater(
      AuthService.runWebGoogleSignInForTesting<Object>(
        () => Future<Object>.error(
          FirebaseAuthException(code: 'cancelled-popup-request'),
        ),
      ),
      throwsA(isA<GoogleSignInInterruptedException>()),
    );
  });

  testWidgets('Welcome localizes Google cancellation and failure separately', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(home: WelcomeScreen(authService: auth)),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Continue with Google'));
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    expect(find.text('Google sign-in was cancelled.'), findsOneWidget);

    auth.googleError = FirebaseAuthException(code: 'network-request-failed');
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    expect(
      find.text('Google sign-in failed. Please try again.'),
      findsOneWidget,
    );
  });

  test('phone-name cancellation rolls back a new session and blocks restart', () async {
    String? currentUid = 'new-phone-user';
    var signOutCalls = 0;

    final rolledBack = await AuthService.rollbackNewPhoneSessionForTesting(
      previousUid: null,
      authenticatedUid: 'new-phone-user',
      currentUid: currentUid,
      signOut: () async {
        signOutCalls++;
        currentUid = null;
      },
    );

    expect(rolledBack, isTrue);
    expect(signOutCalls, 1);
    final restartName = await AppInitializer.validateSessionStateForTesting(
      savedName: null,
      authenticatedUid: currentUid,
      authenticatedDisplayName: null,
      playerDocExists: (_) async => fail('signed-out restart skips lookup'),
      ensurePlayerDoc: (_, __) async => fail('profile must not be created'),
      persistPlayerName: (_) async => fail('name must not be persisted'),
      recoverSession: (_) async => fail('there is no cached session'),
    );
    expect(restartName, isNull);
  });

  test('phone rollback never signs out the pre-existing account', () async {
    var signOutCalls = 0;

    final rolledBack = await AuthService.rollbackNewPhoneSessionForTesting(
      previousUid: 'completed-user',
      authenticatedUid: 'completed-user',
      currentUid: 'completed-user',
      signOut: () async {
        signOutCalls++;
      },
    );

    expect(rolledBack, isFalse);
    expect(signOutCalls, 0);
  });
}
