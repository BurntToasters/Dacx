import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/widgets/media_info_dialog.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  group('MediaInfoDialog', () {
    testWidgets('renders media fields and closes cleanly', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => const MediaInfoDialog(
                    fields: [
                      MediaInfoField(
                        label: 'Source',
                        value: 'https://example.com/live.m3u8',
                      ),
                      MediaInfoField(label: 'Type', value: 'URL stream'),
                      MediaInfoField(label: 'Duration', value: 'Unknown'),
                    ],
                  ),
                );
              },
              child: const Text('Launch'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();

      expect(find.text('Media info'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
      expect(find.text('https://example.com/live.m3u8'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('URL stream'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('Unknown'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Media info'), findsNothing);
    });
  });
}
