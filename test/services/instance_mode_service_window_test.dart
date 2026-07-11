import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/instance_mode_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InstanceModeService window channel', () {
    late List<MethodCall> windowCalls;

    setUp(() {
      windowCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(InstanceModeService.windowMethodChannelName),
            (call) async {
              windowCalls.add(call);
              return true;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(InstanceModeService.windowMethodChannelName),
            null,
          );
      windowCalls.clear();
    });

    test('windowMethodChannelName matches MethodChannel registration', () {
      const channel = MethodChannel(
        InstanceModeService.windowMethodChannelName,
      );
      expect(channel.name, InstanceModeService.windowMethodChannelName);
    });

    test('checkForUpdatesMethod name is frozen', () {
      expect(InstanceModeService.checkForUpdatesMethod, 'checkForUpdates');
    });

    test('macOS menu method names are frozen', () {
      expect(InstanceModeService.openPreferencesMethod, 'openPreferences');
      expect(InstanceModeService.openFileMethod, 'openFile');
      expect(InstanceModeService.openUrlMethod, 'openUrl');
      expect(InstanceModeService.openRecentMethod, 'openRecent');
      expect(InstanceModeService.getRecentFilesMethod, 'getRecentFiles');
    });
  });
}
