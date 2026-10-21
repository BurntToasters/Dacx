import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'flatpak_pictures_dir.dart';

typedef _SHGetKnownFolderPathNative = Int32 Function(
  Pointer<Uint8> rfid,
  Uint32 dwFlags,
  IntPtr hToken,
  Pointer<Pointer<Utf16>> ppszPath,
);
typedef _SHGetKnownFolderPathDart = int Function(
  Pointer<Uint8> rfid,
  int dwFlags,
  int hToken,
  Pointer<Pointer<Utf16>> ppszPath,
);
typedef _CoTaskMemFreeNative = Void Function(Pointer<Void> pv);
typedef _CoTaskMemFreeDart = void Function(Pointer<Void> pv);

abstract final class PicturesDir {
  static const List<int> _folderIdPictures = [
    0x30,
    0x81,
    0xE2,
    0x33,
    0x1E,
    0x4E,
    0x76,
    0x46,
    0x83,
    0x5A,
    0x98,
    0x39,
    0x5C,
    0x3B,
    0xC3,
    0xBB,
  ];

  static String resolve({
    required String os,
    required Map<String, String> environment,
    required String? Function() windowsKnownFolder,
    required String? Function() readUserDirs,
    required bool Function(String path) directoryExists,
  }) {
    if (os == 'windows') {
      final known = windowsKnownFolder()?.trim();
      if (known != null && known.isNotEmpty) return known;
      final profile = environment['USERPROFILE'] ?? environment['HOME'] ?? '.';
      return p.windows.join(profile, 'Pictures');
    }
    final home = environment['HOME'] ?? environment['USERPROFILE'] ?? '.';
    if (os == 'linux') {
      final xdg = FlatpakPicturesDir.resolve(
        environment: environment,
        userDirsContents: readUserDirs(),
        directoryExists: directoryExists,
      );
      if (xdg != null) return xdg;
    }
    return p.posix.join(home, 'Pictures');
  }

  static String current() {
    final environment = Platform.environment;
    return resolve(
      os: Platform.operatingSystem,
      environment: environment,
      windowsKnownFolder: windowsKnownPicturesFolder,
      readUserDirs: () => _readUserDirs(environment),
      directoryExists: (path) => Directory(path).existsSync(),
    );
  }

  static String? _readUserDirs(Map<String, String> environment) {
    try {
      final configHome =
          environment['XDG_CONFIG_HOME'] ??
          p.join(environment['HOME'] ?? '.', '.config');
      final file = File(p.join(configHome, 'user-dirs.dirs'));
      return file.existsSync() ? file.readAsStringSync() : null;
    } catch (_) {
      return null;
    }
  }

  static String? windowsKnownPicturesFolder() {
    if (!Platform.isWindows) return null;
    final rfid = calloc<Uint8>(_folderIdPictures.length);
    final out = calloc<Pointer<Utf16>>();
    try {
      for (var i = 0; i < _folderIdPictures.length; i++) {
        rfid[i] = _folderIdPictures[i];
      }
      final shell32 = DynamicLibrary.open('shell32.dll');
      final ole32 = DynamicLibrary.open('ole32.dll');
      final getPath = shell32
          .lookupFunction<
            _SHGetKnownFolderPathNative,
            _SHGetKnownFolderPathDart
          >('SHGetKnownFolderPath');
      final free = ole32
          .lookupFunction<_CoTaskMemFreeNative, _CoTaskMemFreeDart>(
            'CoTaskMemFree',
          );
      final hr = getPath(rfid, 0, 0, out);
      final pathPointer = out.value;
      if (pathPointer == nullptr) return null;
      try {
        if (hr != 0) return null;
        final path = pathPointer.toDartString().trim();
        return path.isEmpty ? null : path;
      } finally {
        free(pathPointer.cast());
      }
    } catch (_) {
      return null;
    } finally {
      calloc.free(rfid);
      calloc.free(out);
    }
  }
}
