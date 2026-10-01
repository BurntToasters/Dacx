abstract final class FlatpakPicturesDir {
  static String? resolve({
    required Map<String, String> environment,
    String? userDirsContents,
    required bool Function(String path) directoryExists,
  }) {
    final fromEnv = environment['XDG_PICTURES_DIR']?.trim();
    if (fromEnv != null &&
        fromEnv.startsWith('/') &&
        directoryExists(fromEnv)) {
      return fromEnv;
    }
    final parsed = parseUserDirsPictures(
      userDirsContents,
      home: environment['HOME'],
    );
    if (parsed != null && parsed.startsWith('/') && directoryExists(parsed)) {
      return parsed;
    }
    return null;
  }

  static String? parseUserDirsPictures(String? contents, {String? home}) {
    if (contents == null || contents.isEmpty) return null;
    for (final raw in contents.split('\n')) {
      final line = raw.trim();
      if (!line.startsWith('XDG_PICTURES_DIR')) continue;
      final eq = line.indexOf('=');
      if (eq < 0) return null;
      var value = line.substring(eq + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      if (home != null && home.isNotEmpty) {
        value = value.replaceAll(r'$HOME', home);
      }
      return value;
    }
    return null;
  }
}
