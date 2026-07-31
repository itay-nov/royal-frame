import 'rating_invitation_platform.dart';

RatingInvitationPlatformAdapter createPlatformAdapter() =>
    const _UnsupportedRatingInvitationAdapter();

class _UnsupportedRatingInvitationAdapter
    implements RatingInvitationPlatformAdapter {
  const _UnsupportedRatingInvitationAdapter();

  @override
  RatingInvitationPlatform get platform => RatingInvitationPlatform.unsupported;

  @override
  Future<bool> launchWebListing() async => false;

  @override
  Future<bool> requestAndroidReview() async => false;
}
