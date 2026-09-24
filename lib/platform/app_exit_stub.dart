/// Native close requests are handled by Flutter's lifecycle observer.
void Function() registerAppExit(void Function() onExit) => () {};

bool sendExitRequest({
  required String url,
  required Map<String, String> headers,
  required String body,
}) => false;
