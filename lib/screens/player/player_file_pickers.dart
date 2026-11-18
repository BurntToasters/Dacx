import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../playback/file_picker_path.dart';
import '../../playback/m3u_playlist.dart';
import '../../playback/player_path_utils.dart';
import '../../services/path_probe.dart';
import '../../services/settings_service.dart';
import '../../widgets/open_url_dialog.dart';

final List<String> _enqueueAllowedExtensions = List<String>.unmodifiable(
  <String>{
    ...PlayerPathUtils.supportedExtensions,
    ...M3uPlaylist.extensions,
  }.toList()..sort(),
);
const _filePickerWindowsOptions = WindowsOptions(lockParentWindow: true);
const _filePickerLinuxOptions = LinuxOptions(lockParentWindow: true);

class PlayerFilePickers {
  PlayerFilePickers({required this.settings, required this.restoreFocus});

  final SettingsService settings;
  final VoidCallback restoreFocus;

  Future<String?> existingLastOpenDirectory() async {
    final stored = settings.lastOpenDirectory;
    if (stored == null) return null;
    try {
      return await PathProbe.directoryExists(stored) ? stored : null;
    } catch (_) {
      return null;
    }
  }

  void rememberLastOpenDirectory(String filePath) {
    final dir = p.dirname(filePath).trim();
    if (dir.isEmpty || dir == '.') return;
    settings.lastOpenDirectory = dir;
  }

  Future<T> pickWithFocusRestore<T>(Future<T> Function() pick) async {
    try {
      return await pick();
    } finally {
      restoreFocus();
    }
  }

  Future<PlatformFile?> pickMediaFile() async {
    final initialDirectory = await existingLastOpenDirectory();
    return pickWithFocusRestore(
      () => FilePicker.pickFile(
        type: FileType.any,
        windowsOptions: _filePickerWindowsOptions,
        linuxOptions: _filePickerLinuxOptions,
        initialDirectory: initialDirectory,
      ),
    );
  }

  Future<String?> pickFolder() async {
    final initialDirectory = await existingLastOpenDirectory();
    return pickWithFocusRestore(
      () => FilePicker.getDirectoryPath(
        windowsOptions: _filePickerWindowsOptions,
        linuxOptions: _filePickerLinuxOptions,
        initialDirectory: initialDirectory,
      ),
    );
  }

  Future<String?> promptForUrl(BuildContext context) {
    return OpenUrlDialog.show(context);
  }

  Future<String?> pickPlaylistFile() async {
    final initialDirectory = await existingLastOpenDirectory();
    final file = await pickWithFocusRestore(
      () => FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: M3uPlaylist.extensions.toList(),
        windowsOptions: _filePickerWindowsOptions,
        linuxOptions: _filePickerLinuxOptions,
        initialDirectory: initialDirectory,
      ),
    );
    return FilePickerPath.fromPlatformFilePath(file?.path);
  }

  Future<String?> pickPlaylistSavePath({
    required String dialogTitle,
    required String content,
  }) async {
    final initialDirectory = await existingLastOpenDirectory();
    final saved = await pickWithFocusRestore(
      () => FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: 'playlist.m3u',
        type: FileType.custom,
        allowedExtensions: const ['m3u'],
        mimeType: 'audio/x-mpegurl',
        bytes: Uint8List.fromList(utf8.encode(content)),
        windowsOptions: _filePickerWindowsOptions,
        linuxOptions: _filePickerLinuxOptions,
        initialDirectory: initialDirectory,
      ),
    );
    return FilePickerPath.fromSaveUri(saved);
  }

  Future<String?> pickExternalAudioFile() async {
    final initialDirectory = await existingLastOpenDirectory();
    final file = await pickWithFocusRestore(
      () => FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: PlayerPathUtils.audioExtensions.toList()..sort(),
        windowsOptions: _filePickerWindowsOptions,
        linuxOptions: _filePickerLinuxOptions,
        initialDirectory: initialDirectory,
      ),
    );
    return FilePickerPath.fromPlatformFilePath(file?.path);
  }

  Future<String?> pickExternalSubtitleFile() async {
    final initialDirectory = await existingLastOpenDirectory();
    final file = await pickWithFocusRestore(
      () => FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const [
          'srt',
          'ass',
          'ssa',
          'vtt',
          'sub',
          'idx',
          'sup',
        ],
        windowsOptions: _filePickerWindowsOptions,
        linuxOptions: _filePickerLinuxOptions,
        initialDirectory: initialDirectory,
      ),
    );
    return FilePickerPath.fromPlatformFilePath(file?.path);
  }

  Future<List<String>> pickFilesToEnqueue() async {
    final initialDirectory = await existingLastOpenDirectory();
    final files = await pickWithFocusRestore(
      () => FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _enqueueAllowedExtensions,
        windowsOptions: _filePickerWindowsOptions,
        linuxOptions: _filePickerLinuxOptions,
        initialDirectory: initialDirectory,
      ),
    );
    return files
        .map((file) => FilePickerPath.fromPlatformFilePath(file.path))
        .whereType<String>()
        .toList(growable: false);
  }
}
