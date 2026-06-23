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
    await expectLater(
      hydrateWindowsCertificateStoreForTesting(
        context,
        timeout: const Duration(milliseconds: 1),
        runProcess: (_, _) => Future<ProcessResult>.delayed(
          const Duration(seconds: 1),
          () => ProcessResult(1, 0, '', ''),
        ),
      ),
      completes,
    );
  });
}
