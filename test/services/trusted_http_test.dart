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
}
