import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Session-scoped NDJSON lines for DEBUG MODE (do not log secrets/PII).
const _kSessionId = '1a3b4a';
const _kLogFileName = 'debug-1a3b4a.log';

/// Writes one NDJSON line to project cwd and %LOCALAPPDATA%\Dacx\ so logs are
/// found when running `flutter run` from the repo or an installed build.
void agentDebugNdjson({
  required String location,
  required String message,
  required String hypothesisId,
  Map<String, Object?> data = const {},
  String runId = 'pre-fix',
}) {
  // #region agent log
  final payload = <String, Object?>{
    'sessionId': _kSessionId,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'location': location,
    'message': message,
    'hypothesisId': hypothesisId,
    'runId': runId,
    'data': data,
  };
  final line = '${jsonEncode(payload)}\n';
  for (final base in _ndjsonLogBases()) {
    try {
      final dir = Directory(base);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      File(
        p.join(base, _kLogFileName),
      ).writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {}
  }
  // #endregion
}

Iterable<String> _ndjsonLogBases() sync* {
  yield Directory.current.path;
  final la = Platform.environment['LOCALAPPDATA'];
  if (la != null && la.isNotEmpty) {
    yield p.join(la, 'Dacx');
  }
}
