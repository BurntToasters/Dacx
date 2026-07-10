import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records [MethodChannel] invocations for assertions in service tests.
class MethodChannelRecorder {
  MethodChannelRecorder(this.channelName);

  final String channelName;
  final List<MethodCall> calls = [];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(channelName), (call) async {
          calls.add(call);
          return null;
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(channelName), null);
    calls.clear();
  }

  MethodCall? firstWhereMethod(String method) {
    for (final call in calls) {
      if (call.method == method) return call;
    }
    return null;
  }
}

/// Returns a handler that echoes [responses] keyed by method name.
Future<dynamic> Function(MethodCall call) methodChannelHandler(
  Map<String, dynamic> responses,
) {
  return (MethodCall call) async => responses[call.method];
}
