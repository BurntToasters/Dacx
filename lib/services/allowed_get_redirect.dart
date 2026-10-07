import 'dart:async';

import 'package:http/http.dart' as http;

import 'trusted_http.dart';

/// Whether [statusCode] is an HTTP redirect that requires manual follow-up.
bool isHttpRedirectStatus(int statusCode) =>
    statusCode == 301 ||
    statusCode == 302 ||
    statusCode == 303 ||
    statusCode == 307 ||
    statusCode == 308;

/// Default gap allowed between body chunks before a stalled body fails.
const Duration defaultBodyIdleTimeout = Duration(seconds: 60);

/// GET with redirects disabled; only follows [Location] when [isAllowedUrl] passes.
///
/// [timeout] bounds the wait for response headers. [bodyIdleTimeout] bounds
/// the gap between body chunks, so a stalled body fails instead of hanging
/// while a slow but steady download still completes.
Future<http.StreamedResponse> fetchAllowedGetFollowingRedirects({
  required String url,
  required Duration timeout,
  required HttpStreamFn httpStream,
  required bool Function(String url) isAllowedUrl,
  int maxRedirects = 5,
  Duration bodyIdleTimeout = defaultBodyIdleTimeout,
}) async {
  var uri = Uri.parse(url);
  for (var redirectCount = 0; redirectCount <= maxRedirects; redirectCount++) {
    if (!isAllowedUrl(uri.toString())) {
      throw StateError('Refusing to fetch from non-allowlisted host: $uri');
    }
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await httpStream(request).timeout(timeout);
    if (!isHttpRedirectStatus(response.statusCode)) {
      return _withBodyIdleTimeout(response, uri, bodyIdleTimeout);
    }

    final location = response.headers['location'];
    await response.stream.drain<void>();
    if (location == null || location.trim().isEmpty) {
      throw StateError('HTTP ${response.statusCode} redirect missing Location');
    }
    final next = uri.resolve(location);
    if (!isAllowedUrl(next.toString())) {
      throw StateError('Refusing redirect to non-allowlisted host: $next');
    }
    uri = next;
  }
  throw StateError('Too many redirects from $url');
}

http.StreamedResponse _withBodyIdleTimeout(
  http.StreamedResponse response,
  Uri uri,
  Duration idleTimeout,
) {
  final body = response.stream.timeout(
    idleTimeout,
    onTimeout: (sink) {
      sink.addError(
        TimeoutException(
          'No data from $uri for ${idleTimeout.inSeconds}s',
          idleTimeout,
        ),
      );
      sink.close();
    },
  );
  return http.StreamedResponse(
    body,
    response.statusCode,
    contentLength: response.contentLength,
    request: response.request,
    headers: response.headers,
    isRedirect: response.isRedirect,
    persistentConnection: response.persistentConnection,
    reasonPhrase: response.reasonPhrase,
  );
}
