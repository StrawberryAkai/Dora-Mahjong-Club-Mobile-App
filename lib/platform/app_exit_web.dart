import 'dart:async';
import 'dart:js_interop';

@JS('window.addEventListener')
external void _addEventListener(JSString type, JSFunction listener);

@JS('window.removeEventListener')
external void _removeEventListener(JSString type, JSFunction listener);

@JS('window.fetch')
external JSPromise<JSAny?> _fetch(JSString url, JSObject options);

/// pagehide covers navigation and tab closure without treating an ordinary
/// loss of focus as an exit. Mobile process termination can still skip it;
/// the server lease is the fallback for that case.
void Function() registerAppExit(void Function() onExit) {
  final listener = ((JSAny? event) => onExit()).toJS;
  _addEventListener('pagehide'.toJS, listener);
  return () => _removeEventListener('pagehide'.toJS, listener);
}

/// Start a best-effort release that may outlive this page. Authentication stays
/// in headers, never in the URL. A failed request is covered by lease expiry.
bool sendExitRequest({
  required String url,
  required Map<String, String> headers,
  required String body,
}) {
  try {
    final options =
        {
              'method': 'POST',
              'headers': headers,
              'body': body,
              'keepalive': true,
            }.jsify()
            as JSObject;
    unawaited(
      _fetch(
        url.toJS,
        options,
      ).toDart.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    return true;
  } catch (_) {
    return false;
  }
}
