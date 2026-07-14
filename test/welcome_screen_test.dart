import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/main.dart';
import 'package:royal_frame/screens/welcome_screen.dart';
import 'package:royal_frame/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('player name input is capped at the backend limit', (
    tester,
  ) async {
    await tester.pumpWidget(const RoyalFrameApp());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    final nameField = find.byType(TextField).first;
    await tester.enterText(nameField, List.filled(40, 'a').join());

    final field = tester.widget<TextField>(nameField);
    expect(field.controller!.text, hasLength(30));
  });

  testWidgets('empty guest name is rejected before authentication', (
    tester,
  ) async {
    await tester.pumpWidget(const RoyalFrameApp());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play as Guest'));
    await tester.pump();

    expect(find.text('Please enter a name'), findsOneWidget);
  });

  testWidgets('native phone code callback opens verification dialog later', (
    tester,
  ) async {
    final auth = _DelayedPhoneAuthService();
    await tester.pumpWidget(
      MaterialApp(home: WelcomeScreen(authService: auth)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Continue with Phone'));
    await tester.tap(find.text('Continue with Phone'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '+972501234567');
    await tester.tap(find.text('Send Code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Verification Code'), findsNothing);
    expect(auth.hasCodeSentCallback, isTrue);

    auth.emitCodeSent('verification-id');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Verification Code'), findsOneWidget);
  });
}

class _DelayedPhoneAuthService extends AuthService {
  PhoneCodeSent? _onCodeSent;

  bool get hasCodeSentCallback => _onCodeSent != null;

  void emitCodeSent(String verificationId) {
    _onCodeSent!(verificationId, null);
  }

  @override
  Future<void> sendSmsCodeNative({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(UserCredential credential) onAutoVerified,
    required void Function(String error) onError,
  }) async {
    _onCodeSent = onCodeSent;
  }
}
