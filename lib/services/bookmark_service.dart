import 'dart:io';

import 'package:flutter/services.dart';

class ResolvedBookmark {
  final String path;
  final String token;
  final bool stale;
  final String? refreshed;
  const ResolvedBookmark({
    required this.path,
    required this.token,
    required this.stale,
    this.refreshed,
  });
}

class BookmarkService {
  static const methodChannelName = 'run.rosie.dacx/bookmarks';
  static const MethodChannel _channel = MethodChannel(methodChannelName);

  static bool get isSupported => Platform.isMacOS;

  static Future<String?> createBookmark(String path) async {
    if (!isSupported) return null;
    try {
      final result = await _channel.invokeMethod<String>('create', {
        'path': path,
      });
      return result;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<ResolvedBookmark?> resolveAndStart(String bookmark) async {
    if (!isSupported) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'resolveAndStart',
        {'bookmark': bookmark},
      );
      if (result == null) return null;
      final path = result['path'];
      final token = result['token'];
      if (path is! String || path.isEmpty) return null;
      final stale = result['stale'] == true;
      final refreshed = result['refreshed'] is String
          ? result['refreshed'] as String
          : null;
      return ResolvedBookmark(
        path: path,
        token: token is String ? token : '',
        stale: stale,
        refreshed: refreshed,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> stop(String token) async {
    if (!isSupported || token.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('stop', {'token': token});
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }
}
