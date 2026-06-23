import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/widgets/open_url_dialog.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  group('OpenUrlDialog', () {
    testWidgets('shows validation error for unsupported URLs', (tester) async {
      String? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await OpenUrlDialog.show(context);
              },
              child: const Text('Launch'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('open-url-text-field')),
        'ftp://example.com/stream.m3u8',
      );
      await tester.tap(find.text('Open'));
      await tester.pump();

      expect(
        find.text('Enter a valid http:// or https:// URL.'),
        findsOneWidget,
      );
      expect(result, isNull);
    });

    testWidgets('returns trimmed URL after a valid submission', (tester) async {
      String? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await OpenUrlDialog.show(context);
              },
              child: const Text('Launch'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('open-url-text-field')),
        '  https://example.com/live.m3u8  ',
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(result, 'https://example.com/live.m3u8');
      expect(find.text('Open URL'), findsNothing);
    });
  });
}
