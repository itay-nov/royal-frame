import 'package:flutter/widgets.dart';

import '../services/rating_invitation_service.dart';

class RatingInvitationScope extends InheritedWidget {
  final RatingInvitationCoordinator coordinator;

  const RatingInvitationScope({
    super.key,
    required this.coordinator,
    required super.child,
  });

  static RatingInvitationCoordinator? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<RatingInvitationScope>()
        ?.coordinator;
  }

  @override
  bool updateShouldNotify(RatingInvitationScope oldWidget) {
    return coordinator != oldWidget.coordinator;
  }
}
