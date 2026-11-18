import 'package:flutter/material.dart';

const Duration kAppSnackBarDefaultDuration = Duration(milliseconds: 4000);

extension AppSnackBarMessenger on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackBar(
    String message, {
    SnackBarAction? action,
    Duration? duration,
  }) {
    clearSnackBars();
    return showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        duration: duration ?? kAppSnackBarDefaultDuration,
      ),
    );
  }
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration? duration,
}) {
  return ScaffoldMessenger.of(context)
      .showAppSnackBar(message, action: action, duration: duration);
}
