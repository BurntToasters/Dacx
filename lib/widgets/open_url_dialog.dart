import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/playable_source.dart';

class OpenUrlDialog extends StatefulWidget {
  const OpenUrlDialog({super.key, this.initialValue = ''});

  final String initialValue;

  static Future<String?> show(
    BuildContext context, {
    String initialValue = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => OpenUrlDialog(initialValue: initialValue),
    );
  }

  @override
  State<OpenUrlDialog> createState() => _OpenUrlDialogState();
}

class _OpenUrlDialogState extends State<OpenUrlDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    if (!PlayableSource.isSupportedUrl(trimmed)) {
      setState(() {
        _errorText = AppLocalizations.of(context).snackInvalidStreamUrl;
      });
      return;
    }
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.dialogOpenUrlTitle),
      content: TextField(
        key: const Key('open-url-text-field'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.dialogOpenUrlHint,
          errorText: _errorText,
        ),
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.done,
        onChanged: (_) {
          if (_errorText == null) return;
          setState(() => _errorText = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.actionOpen)),
      ],
    );
  }
}
