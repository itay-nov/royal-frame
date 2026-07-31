import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window.open')
external JSObject? _openWindow(JSString url, JSString target);

Object? openRatingInvitationBrowserWindow(String url, String target) {
  final opened = _openWindow('about:blank'.toJS, target.toJS);
  if (opened == null) return null;

  try {
    opened.setProperty('opener'.toJS, null);
    final location = opened.getProperty<JSObject>('location'.toJS);
    location.setProperty('href'.toJS, url.toJS);
    return opened;
  } catch (_) {
    try {
      opened.callMethod<JSAny?>('close'.toJS);
    } catch (_) {
      // The original browser failure is the meaningful result.
    }
    rethrow;
  }
}
