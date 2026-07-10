/// Pure on-screen display rules extracted from [PlayerScreen].
abstract final class OsdPolicy {
  static bool shouldShow({required bool osdEnabled, required bool mounted}) {
    return osdEnabled && mounted;
  }

  /// Embeds a hidden timestamp so repeated identical messages still refresh OSD.
  static String formatTransientMessage(String message, {int? timestampMs}) {
    final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    return '$message\u2009·\u2009$ts';
  }
}
