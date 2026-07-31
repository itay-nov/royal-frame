import 'rating_invitation_browser_open_stub.dart'
    if (dart.library.html) 'rating_invitation_browser_open_web.dart'
    as implementation;

typedef RatingInvitationBrowserOpen =
    Object? Function(String url, String target);

Object? openRatingInvitationBrowserWindow(String url, String target) {
  return implementation.openRatingInvitationBrowserWindow(url, target);
}
