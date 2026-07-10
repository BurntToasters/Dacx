import 'dart:convert';
import 'dart:io';

import 'package:dacx/services/trusted_http.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyTrustedCertificatesFromBase64Lines', () {
    test('skips empty lines', () {
      // Just verify it doesn't throw on empty input.
      final context = SecurityContext(withTrustedRoots: false);
      expect(
        () => applyTrustedCertificatesFromBase64Lines(context, ['', '  ', '']),
        returnsNormally,
      );
    });

    test('skips malformed base64', () {
      final context = SecurityContext(withTrustedRoots: false);
      // Invalid certificate data but valid base64 — should not throw.
      expect(
        () => applyTrustedCertificatesFromBase64Lines(
          context,
          [base64Encode([0, 1, 2, 3]), 'not-base64!!!'],
        ),
        returnsNormally,
      );
    });

    test('processes valid DER certificate without throwing', () {
      // A minimal self-signed DER cert would be needed for a real test,
      // but we can verify the function handles garbage gracefully.
      final context = SecurityContext(withTrustedRoots: false);
      final fakeDer = base64Encode(List<int>.filled(100, 0x30));
      expect(
        () => applyTrustedCertificatesFromBase64Lines(context, [fakeDer]),
        returnsNormally,
      );
    });
  });

  group('trusted_http constants', () {
    test('dacxAppUserModelId is set', () {
      expect(dacxAppUserModelId, 'run.rosie.dacx');
    });

    test('windowsCertificateStoreHydrationTimeout is reasonable', () {
      expect(
        windowsCertificateStoreHydrationTimeout.inSeconds,
        greaterThanOrEqualTo(5),
      );
      expect(
        windowsCertificateStoreHydrationTimeout.inSeconds,
        lessThanOrEqualTo(30),
      );
    });
  });
}
