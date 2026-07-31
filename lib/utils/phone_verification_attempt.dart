import 'dart:async';

/// Coordinates the automatic and manual completion paths for one native
/// phone-verification request.
class PhoneVerificationAttempt {
  final Completer<void> _completion = Completer<void>();

  bool authenticationStarted = false;
  bool codeDialogOpen = false;

  Future<void> get done => _completion.future;

  bool claimAuthentication() {
    if (authenticationStarted) return false;
    authenticationStarted = true;
    return true;
  }

  void complete() {
    if (!_completion.isCompleted) _completion.complete();
  }
}
