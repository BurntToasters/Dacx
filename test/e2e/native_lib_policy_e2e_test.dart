import 'package:flutter_test/flutter_test.dart';
import 'package:dacx/playback/native_lib_policy.dart';

void main() {
  group('bundled FFmpeg policy', () {
    test('rejects the 2023 builds and accepts the refreshed ones', () {
      expect(NativeLibPolicy.acceptsFfmpeg('n6.0', os: 'windows'), isFalse);
      expect(NativeLibPolicy.acceptsFfmpeg('6.0', os: 'macos'), isFalse);
      expect(
        NativeLibPolicy.acceptsFfmpeg('N-117622-g8d940a07d', os: 'windows'),
        isTrue,
      );
      expect(
        NativeLibPolicy.acceptsFfmpeg('N-111000-gabcdef1', os: 'windows'),
        isFalse,
      );
      expect(NativeLibPolicy.acceptsFfmpeg('n7.1', os: 'macos'), isTrue);
      expect(NativeLibPolicy.acceptsFfmpeg('8.0.1', os: 'macos'), isTrue);
      expect(NativeLibPolicy.acceptsFfmpeg('n7.0.2', os: 'macos'), isFalse);
    });

    test('unknown or missing versions fail on bundled platforms', () {
      expect(NativeLibPolicy.acceptsFfmpeg(null, os: 'windows'), isFalse);
      expect(NativeLibPolicy.acceptsFfmpeg('', os: 'macos'), isFalse);
      expect(
        NativeLibPolicy.acceptsFfmpeg('custom-build', os: 'windows'),
        isFalse,
      );
    });

    test('Linux system libmpv is maintained by the distro', () {
      expect(
        NativeLibPolicy.acceptsFfmpeg('6.1.1-3ubuntu5', os: 'linux'),
        isTrue,
      );
    });
  });
}
