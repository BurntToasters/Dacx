import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/trusted_http.dart';

void main() {
  group('applyTrustedCertificatesFromBase64Lines', () {
    test('ignores empty and invalid lines', () {
      final context = SecurityContext();
      expect(
        () => applyTrustedCertificatesFromBase64Lines(context, [
          '',
          'not-base64-cert',
        ]),
        returnsNormally,
      );
    });
  });

  test('dacxAppUserModelId matches package id', () {
    expect(dacxAppUserModelId, 'run.rosie.dacx');
  });

  test('Windows certificate store hydration returns on timeout', () async {
    final context = SecurityContext();
    Future<Process> startSleepyProcess(String _, List<String> __) {
      if (Platform.isWindows) {
        return Process.start('cmd', [
          '/c',
          'ping',
          '-n',
          '2',
          '127.0.0.1',
          '>nul',
        ]);
      }
      return Process.start('sh', ['-c', 'sleep 1']);
    }

    await expectLater(
      hydrateWindowsCertificateStoreForTesting(
        context,
        timeout: const Duration(milliseconds: 1),
        startProcess: startSleepyProcess,
      ),
      completes,
    );
  });
}
