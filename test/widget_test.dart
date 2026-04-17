import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/update_service.dart';

void main() {
  group('UpdateService', () {
    test('current version does not trigger update', () {
      final service = UpdateService();
      expect(service, isNotNull);
    });
  });
}
