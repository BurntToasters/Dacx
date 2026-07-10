import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dacx/services/trusted_http.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProcess implements Process {
  _FakeProcess({
    required this.exitCodeValue,
    required this.stdoutContent,
    required this.stderrContent,
  });

  final int exitCodeValue;
  final String stdoutContent;
  final String stderrContent;

  @override
  Stream<List<int>> get stdout => Stream.value(utf8.encode(stdoutContent));

  @override
  Stream<List<int>> get stderr => Stream.value(utf8.encode(stderrContent));

  @override
  Future<int> get exitCode => Future.value(exitCodeValue);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('applyTrustedCertificatesFromBase64Lines', () {
    test('skips empty lines', () {
      final context = SecurityContext(withTrustedRoots: false);
      expect(
        () => applyTrustedCertificatesFromBase64Lines(context, ['', '  ', '']),
        returnsNormally,
      );
    });

    test('skips malformed base64', () {
      final context = SecurityContext(withTrustedRoots: false);
      expect(
        () => applyTrustedCertificatesFromBase64Lines(context, [
          base64Encode([0, 1, 2, 3]),
          'not-base64!!!',
        ]),
        returnsNormally,
      );
    });

    test('processes valid DER certificate without throwing', () {
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

  group('hydrateWindowsCertificateStoreForTesting', () {
    test('hydrates certificates on success', () async {
      final context = SecurityContext(withTrustedRoots: false);
      final certBase64 = base64Encode(List<int>.filled(50, 0x30));

      await hydrateWindowsCertificateStoreForTesting(
        context,
        startProcess: (executable, arguments) async {
          return _FakeProcess(
            exitCodeValue: 0,
            stdoutContent: '$certBase64\n',
            stderrContent: '',
          );
        },
      );
    });

    test('skips hydration on process failure', () async {
      final context = SecurityContext(withTrustedRoots: false);
      await hydrateWindowsCertificateStoreForTesting(
        context,
        startProcess: (executable, arguments) async {
          return _FakeProcess(
            exitCodeValue: 1,
            stdoutContent: 'error logs',
            stderrContent: 'error',
          );
        },
      );
    });

    test('aborts hydration on timeout', () async {
      final context = SecurityContext(withTrustedRoots: false);
      final completer = Completer<Process>();

      final future = hydrateWindowsCertificateStoreForTesting(
        context,
        startProcess: (executable, arguments) => completer.future,
        timeout: const Duration(milliseconds: 10),
      );

      // Complete process start after the timeout duration to simulate delay
      await Future<void>.delayed(const Duration(milliseconds: 20));
      completer.complete(
        _FakeProcess(
          exitCodeValue: 0,
          stdoutContent: 'data',
          stderrContent: '',
        ),
      );

      await future;
    });
  });
}
