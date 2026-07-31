import 'rating_invitation_browser_open.dart';
import 'rating_invitation_platform.dart';

RatingInvitationPlatformAdapter createPlatformAdapter() =>
    WebRatingInvitationPlatformAdapter();

class WebRatingInvitationPlatformAdapter
    implements RatingInvitationPlatformAdapter {
  final RatingInvitationBrowserOpen _browserOpen;

  WebRatingInvitationPlatformAdapter({RatingInvitationBrowserOpen? browserOpen})
    : _browserOpen = browserOpen ?? openRatingInvitationBrowserWindow;

  @override
  RatingInvitationPlatform get platform => RatingInvitationPlatform.web;

  @override
  Future<bool> launchWebListing() {
    try {
      final opened = _browserOpen(ratingInvitationGooglePlayUrl, '_blank');
      return Future<bool>.value(opened != null);
    } catch (_) {
      return Future<bool>.value(false);
    }
  }

  @override
  Future<bool> requestAndroidReview() async => false;
}
