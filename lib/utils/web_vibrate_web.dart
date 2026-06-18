import 'dart:js_interop';

@JS('navigator.vibrate')
external JSBoolean? _vibrate(JSAny pattern);

void webVibrate(int ms) {
  try {
    _vibrate(ms.toJS);
  } catch (_) {}
}
