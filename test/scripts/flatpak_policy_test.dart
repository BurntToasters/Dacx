import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flatpak manifest avoids host filesystem and ships legal files', () {
    final manifest = File('flatpak/run.rosie.dacx.yaml');
    expect(manifest.existsSync(), isTrue);

    final active = manifest
        .readAsStringSync()
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'#.*$'), '').trim())
        .join('\n');
    expect(active, isNot(contains(RegExp(r'--filesystem=host\b'))));
    expect(active, contains('THIRD_PARTY_NOTICES.txt'));
    expect(active, contains('/app/share/doc/dacx'));
  });
}
