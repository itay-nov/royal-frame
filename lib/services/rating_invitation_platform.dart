import 'rating_invitation_platform_stub.dart'
    if (dart.library.io) 'rating_invitation_platform_io.dart'
    if (dart.library.html) 'rating_invitation_platform_web.dart';

const String ratingInvitationGooglePlayUrl =
    'https://play.google.com/store/apps/details?id=com.itay.royalframegame';

enum RatingInvitationPlatform { android, web, unsupported }

abstract interface class RatingInvitationPlatformAdapter {
  RatingInvitationPlatform get platform;

  /// Returns true once Google Play's review request completed successfully.
  ///
  /// This does not indicate that a dialog appeared or that a review was
  /// submitted.
  Future<bool> requestAndroidReview();

  /// Starts the exact Google Play listing launch and reports whether the
  /// browser accepted it.
  Future<bool> launchWebListing();
}

RatingInvitationPlatformAdapter createRatingInvitationPlatformAdapter() =>
    createPlatformAdapter();
