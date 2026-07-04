import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme_constants.dart';

/// Central user-facing feedback + error logging.
///
/// Policy: background work the user didn't initiate logs via [logError]
/// only; user-initiated flows that fail get a [showAppSnack] with
/// `isError: true`. Never both silent and unlogged.

/// Shows the app-styled floating snackbar. Replaces any snack currently
/// showing so rapid events can't queue a backlog.
void showAppSnack(BuildContext context, String message,
    {bool isError = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(
          color: isError ? Colors.white : kGoldLight,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: isError ? kDanger : kBurgundyLight,
      behavior: SnackBarBehavior.floating,
      duration: kDurSnack,
      shape: RoundedRectangleBorder(
        borderRadius: kBrMd,
        side: BorderSide(
          color: isError ? Colors.white24 : kGold,
          width: 1,
        ),
      ),
    ),
  );
}

/// Debug-visible error trace for swallowed/background failures.
/// [scope] is a short dotted tag like 'duel.syncScore'.
void logError(String scope, Object error, [StackTrace? stack]) {
  if (!kDebugMode) return;
  debugPrint('[RF:$scope] $error');
  if (stack != null) debugPrint(stack.toString());
}
