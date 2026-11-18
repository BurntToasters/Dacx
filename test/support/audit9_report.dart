import 'dart:convert';
import 'dart:io';

class Audit9Report {
  Audit9Report(this.area, {required List<String> expectedIds, this.reportDir})
    : expectedIds = List<String>.unmodifiable(expectedIds);

  static const schema = 'dacx.e2e.audit9.v1';

  final String area;
  final List<String> expectedIds;
  final String? reportDir;
  final Set<String> _passed = <String>{};

  void pass(String id) {
    _passed.add(id);
  }

  String get path {
    final dir =
        reportDir ??
        Platform.environment['DACX_E2E_REPORT_DIR'] ??
        'test-results/e2e/${Platform.operatingSystem}';
    return '$dir/audit9-$area-report.json';
  }

  Map<String, Object?> toJson() {
    final expected = expectedIds.toSet().toList()..sort();
    final passed = _passed.toList()..sort();
    final missing = expected.where((id) => !_passed.contains(id)).toList();
    return <String, Object?>{
      'area': area,
      'expected': expected,
      'missing': missing,
      'passed': passed,
      'platform': Platform.operatingSystem,
      'schema': schema,
      'status': missing.isEmpty ? 'passed' : 'failed',
    };
  }

  void write() {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final text = const JsonEncoder.withIndent('  ').convert(toJson());
    file.writeAsStringSync('$text\n');
  }
}
