import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/seek_preview_service.dart';
import 'package:dacx/widgets/seek_slider.dart';

// 1x1 transparent PNG used as a stand-in thumbnail.
final Uint8List _stubPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
  0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
  0x42, 0x60, 0x82,
]);

class _FakeSeekPreviewService extends SeekPreviewService {
  int requestCount = 0;
  Duration? lastTarget;
  Uint8List? response;

  @override
  Future<Uint8List?> requestPreview(Duration target) async {
    requestCount++;
    lastTarget = target;
    return response;
  }
}

Widget _harness({
  required SeekPreviewService service,
  required bool previewEnabled,
  Duration position = const Duration(seconds: 5),
  Duration duration = const Duration(seconds: 60),
}) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(40),
        child: SizedBox(
          width: 400,
          child: SeekSliderWithHover(
            position: position,
            duration: duration,
            previewService: service,
            previewEnabled: previewEnabled,
            onSeekStart: () {},
            onSeekChange: (_) {},
            onSeekEnd: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('exposes Semantics slider with position/duration label',
      (tester) async {
    final svc = _FakeSeekPreviewService();
    await tester.pumpWidget(_harness(service: svc, previewEnabled: false));
    final semantics = tester.getSemantics(find.byType(SeekSliderWithHover));
    expect(semantics.label, 'Seek bar');
    expect(semantics.value, contains('00:05'));
    expect(semantics.value, contains('01:00'));
  });

  testWidgets('does not call preview service when feature disabled',
      (tester) async {
    final svc = _FakeSeekPreviewService()..response = _stubPng;
    await tester.pumpWidget(_harness(service: svc, previewEnabled: false));

    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(
      location: tester.getCenter(find.byType(SeekSliderWithHover)),
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    expect(svc.requestCount, 0);
  });

  testWidgets('hover triggers preview request when enabled', (tester) async {
    final svc = _FakeSeekPreviewService()..response = _stubPng;
    await tester.pumpWidget(_harness(service: svc, previewEnabled: true));

    final center = tester.getCenter(find.byType(SeekSliderWithHover));
    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(center.translate(20, 0));
    await tester.pump();

    expect(svc.requestCount, greaterThanOrEqualTo(1));
    expect(svc.lastTarget, isNotNull);
    expect(svc.lastTarget!.inMilliseconds, greaterThan(0));
  });

  testWidgets('mouse exit clears preview state and ignores stale responses',
      (tester) async {
    final svc = _FakeSeekPreviewService();
    final completer = Completer<Uint8List?>();
    final delayed = _DelayedFakeService(completer.future);
    await tester.pumpWidget(_harness(service: delayed, previewEnabled: true));

    final center = tester.getCenter(find.byType(SeekSliderWithHover));
    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(center.translate(20, 0));
    await tester.pump();

    // Move pointer off the slider before the preview future completes.
    await gesture.moveTo(const Offset(0, 0));
    await tester.pump();

    completer.complete(_stubPng);
    await tester.pump();

    // No Image.memory should have been mounted because the request was stale.
    expect(find.byType(Image), findsNothing);
    expect(svc.requestCount, 0);
  });
}

class _DelayedFakeService extends SeekPreviewService {
  _DelayedFakeService(this._future);
  final Future<Uint8List?> _future;
  @override
  Future<Uint8List?> requestPreview(Duration target) => _future;
}
