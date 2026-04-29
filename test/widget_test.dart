import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:dacx/services/update_service.dart';

void main() {
  group('UpdateService', () {
    test('current version does not trigger update when equal', () async {
      final service = UpdateService(
        packageInfoLoader: () async => PackageInfo(
          appName: 'Dacx',
          packageName: 'run.rosie.dacx',
          version: '0.5.0',
          buildNumber: '1',
          buildSignature: '',
          installerStore: null,
        ),
        httpGet: (uri, {headers}) async => http.Response(
          '{"tag_name":"v0.5.0","html_url":"https://github.com/BurntToasters/Dacx/releases/tag/v0.5.0","body":"notes"}',
          200,
        ),
      );

      final update = await service.checkForUpdate();

      expect(update, isNull);
      expect(service.lastCheckSucceeded, isTrue);
    });
  });
}
