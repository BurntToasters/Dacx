import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/update_service.dart';
import 'package:dacx/widgets/manual_update_check.dart';

class _FakeUpdateService extends UpdateService {
  var calls = 0;

  @override
  bool get lastCheckSucceeded => true;

  @override
  bool get lastCheckRateLimited => false;

  @override
  bool get lastCheckNetworkError => false;

  @override
  UpdateChannel? get lastEffectiveChannel => UpdateChannel.stable;

  @override
  Future<UpdateInfo?> checkForUpdate({UpdateChannel? channel}) async {
    calls++;
    return null;
  }
}

void main() {
  testWidgets('runManualUpdateCheck shows latest when no update', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    final service = _FakeUpdateService();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => runManualUpdateCheck(
                  context: context,
                  updateService: service,
                  settings: settings,
                ),
                child: const Text('check'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();
    expect(service.calls, 1);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
