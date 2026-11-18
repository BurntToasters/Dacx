import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/audit9_report.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('audit9_report_');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> read(Audit9Report report) =>
      jsonDecode(File(report.path).readAsStringSync()) as Map<String, Object?>;

  test('R.1 all expected ids passed gives status passed', () {
    final report = Audit9Report(
      'sample',
      expectedIds: ['M1.2', 'M1.1'],
      reportDir: tmp.path,
    );
    report.pass('M1.1');
    report.pass('M1.2');
    report.write();
    final json = read(report);
    expect(json['schema'], 'dacx.e2e.audit9.v1');
    expect(json['area'], 'sample');
    expect(json['platform'], Platform.operatingSystem);
    expect(json['status'], 'passed');
    expect(json['missing'], isEmpty);
  });

  test('R.2 a missing id gives status failed', () {
    final report = Audit9Report(
      'sample',
      expectedIds: ['M1.1', 'M1.2'],
      reportDir: tmp.path,
    );
    report.pass('M1.1');
    report.write();
    final json = read(report);
    expect(json['status'], 'failed');
    expect(json['missing'], ['M1.2']);
  });

  test('R.3 writes are byte-identical regardless of pass order', () {
    final first = Audit9Report(
      'sample',
      expectedIds: ['M2.1', 'M1.1'],
      reportDir: tmp.path,
    );
    first.pass('M1.1');
    first.pass('M2.1');
    first.write();
    final firstBytes = File(first.path).readAsBytesSync();
    first.write();
    expect(File(first.path).readAsBytesSync(), firstBytes);

    final second = Audit9Report(
      'sample',
      expectedIds: ['M1.1', 'M2.1'],
      reportDir: tmp.path,
    );
    second.pass('M2.1');
    second.pass('M1.1');
    second.pass('M1.1');
    second.write();
    expect(File(second.path).readAsBytesSync(), firstBytes);
  });

  test('R.4 passed, expected and missing are sorted and deduplicated', () {
    final report = Audit9Report(
      'sample',
      expectedIds: ['M3.1', 'M1.1', 'M2.1', 'M1.1'],
      reportDir: tmp.path,
    );
    report.pass('M2.1');
    report.pass('M2.1');
    report.pass('M1.1');
    report.write();
    final json = read(report);
    expect(json['expected'], ['M1.1', 'M2.1', 'M3.1']);
    expect(json['passed'], ['M1.1', 'M2.1']);
    expect(json['missing'], ['M3.1']);
  });

  test('R.5 an unexpected id does not hide a missing expected id', () {
    final report = Audit9Report(
      'sample',
      expectedIds: ['M1.1', 'M1.2'],
      reportDir: tmp.path,
    );
    report.pass('M1.1');
    report.pass('M9.9');
    report.write();
    final json = read(report);
    expect(json['status'], 'failed');
    expect(json['missing'], ['M1.2']);
  });

  test('R.6 creates the directory and names the file by area', () {
    final nested = '${tmp.path}/a/b';
    final report = Audit9Report(
      'area-x',
      expectedIds: ['M1.1'],
      reportDir: nested,
    );
    report.pass('M1.1');
    report.write();
    expect(File('$nested/audit9-area-x-report.json').existsSync(), isTrue);
  });
}
