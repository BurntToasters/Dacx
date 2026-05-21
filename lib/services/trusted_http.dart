import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// AppUserModelID for Windows shell integration (Start search, taskbar).
const String dacxAppUserModelId = 'run.rosie.dacx';

typedef HttpGet =
    Future<http.Response> Function(Uri uri, {Map<String, String>? headers});

typedef HttpStreamFn =
    Future<http.StreamedResponse> Function(http.BaseRequest request);

/// Hydrates [SecurityContext] with base64-encoded DER certificates (one per line).
void applyTrustedCertificatesFromBase64Lines(
  SecurityContext context,
  Iterable<String> base64Lines,
) {
  for (final line in base64Lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    try {
      context.setTrustedCertificatesBytes(base64Decode(trimmed));
    } catch (_) {
      // Skip malformed or duplicate entries.
    }
  }
}

Future<void> _hydrateWindowsCertificateStore(SecurityContext context) async {
  const stores = <String>[
    r'Cert:\LocalMachine\Root',
    r'Cert:\CurrentUser\Root',
    r'Cert:\LocalMachine\CA',
    r'Cert:\CurrentUser\CA',
  ];
  final command = stores
      .map(
        (store) =>
            "Get-ChildItem -Path '$store' -ErrorAction SilentlyContinue | "
            "ForEach-Object { [Convert]::ToBase64String(\$_.RawData) }",
      )
      .join('; ');

  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    command,
  ]);

  if (result.exitCode != 0) return;

  applyTrustedCertificatesFromBase64Lines(
    context,
    (result.stdout as String).split(RegExp(r'\r?\n')),
  );
}

IOClient? _windowsIoClient;
var _windowsTrustPrimed = false;

Future<void> primeWindowsTlsTrust() async {
  if (!Platform.isWindows || _windowsTrustPrimed) return;
  _windowsTrustPrimed = true;
  final context = SecurityContext(withTrustedRoots: true);
  await _hydrateWindowsCertificateStore(context);
  _windowsIoClient = IOClient(HttpClient(context: context));
}

Future<http.Client> _windowsHttpClient() async {
  await primeWindowsTlsTrust();
  return _windowsIoClient ?? IOClient();
}

/// Default GET for update/download code. Uses Schannel-backed roots on Windows.
Future<http.Response> platformHttpGet(Uri uri, {Map<String, String>? headers}) {
  if (!Platform.isWindows) {
    return http.get(uri, headers: headers);
  }
  return _windowsHttpClient().then(
    (client) => client.get(uri, headers: headers),
  );
}

Future<http.StreamedResponse> platformHttpSend(http.BaseRequest request) {
  if (!Platform.isWindows) {
    return request.send();
  }
  return _windowsHttpClient().then((client) => client.send(request));
}

HttpGet get platformHttpGetFn => platformHttpGet;

HttpStreamFn get platformHttpStreamFn => platformHttpSend;
