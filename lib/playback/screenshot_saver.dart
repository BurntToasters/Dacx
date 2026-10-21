import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/playable_source.dart';
import 'pictures_dir.dart';
import 'screenshot_path_policy.dart';

enum ScreenshotSaveOutcome { noFrame, directoryUnavailable, saved, writeFailed }

class ScreenshotSaveResult {
  const ScreenshotSaveResult(
    this.outcome, {
    this.path,
    this.directory,
    this.error,
  });

  final ScreenshotSaveOutcome outcome;
  final String? path;
  final String? directory;
  final Object? error;
}

class ScreenshotSaver {
  ScreenshotSaver({
    required this.capture,
    required this.resolveScope,
    required this.releaseScope,
    String Function()? defaultDirectory,
  }) : _defaultDirectory = defaultDirectory ?? defaultScreenshotDirectory;

  final Future<Uint8List?> Function(String mime) capture;
  final Future<({String path, String? token})> Function(String directory)
  resolveScope;
  final Future<void> Function(String token) releaseScope;
  final String Function() _defaultDirectory;

  static String defaultScreenshotDirectory() => folderIn(PicturesDir.current());

  static String folderIn(String pictures) {
    final legacy = p.join(pictures, 'DACX');
    try {
      if (Directory(legacy).existsSync()) return legacy;
    } catch (_) {}
    return p.join(pictures, 'Dacx');
  }

  Future<ScreenshotSaveResult> save({
    required PlayableSource source,
    required String format,
    required String? customDirectory,
  }) async {
    final bytes = await capture(ScreenshotPathPolicy.mimeForFormat(format));
    if (bytes == null) {
      return const ScreenshotSaveResult(ScreenshotSaveOutcome.noFrame);
    }
    final scoped = customDirectory != null
        ? await resolveScope(customDirectory)
        : (path: _defaultDirectory(), token: null);
    try {
      return _write(bytes, scoped.path, source, format);
    } finally {
      final token = scoped.token;
      if (token != null && token.isNotEmpty) {
        await releaseScope(token);
      }
    }
  }

  ScreenshotSaveResult _write(
    Uint8List bytes,
    String directory,
    PlayableSource source,
    String format,
  ) {
    try {
      Directory(directory).createSync(recursive: true);
    } catch (e) {
      return ScreenshotSaveResult(
        ScreenshotSaveOutcome.directoryUnavailable,
        directory: directory,
        error: e,
      );
    }
    final outPath = ScreenshotPathPolicy.uniqueOutputPath(
      path: ScreenshotPathPolicy.buildOutputPath(
        directory: directory,
        baseName: ScreenshotPathPolicy.baseNameForSource(
          isFile: source.isFile,
          sourceValue: source.value,
          displayName: source.displayName,
        ),
        format: format,
        timestamp: DateTime.now(),
      ),
      exists: (candidate) => File(candidate).existsSync(),
    );
    try {
      File(outPath).writeAsBytesSync(bytes, flush: true);
      return ScreenshotSaveResult(
        ScreenshotSaveOutcome.saved,
        path: outPath,
        directory: directory,
      );
    } catch (e) {
      return ScreenshotSaveResult(
        ScreenshotSaveOutcome.writeFailed,
        path: outPath,
        directory: directory,
        error: e,
      );
    }
  }
}
