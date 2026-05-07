// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const String _channelName = 'plugins.fluttertv.dev/path_provider_tvos';

/// The tvOS implementation of [PathProviderPlatform].
///
/// Apple TV apps have a constrained storage model. For reference:
///
/// * **Temporary** — safe for short-lived scratch files. May be purged.
/// * **Caches** — may be purged by the OS between launches.
/// * **Application Support** — persistent, but apps should keep the
///   footprint small (non-ephemeral storage is not designed for large
///   user data on tvOS).
/// * **Documents** — backed by `NSDocumentDirectory`. On tvOS the
///   Documents directory is not exposed to users; treat it as internal
///   app-private storage with a small size budget.
/// * **External / Downloads** — not supported on tvOS.
class PathProviderTvos extends PathProviderPlatform {
  /// The method channel used to talk to the tvOS host plugin.
  static const MethodChannel _channel = MethodChannel(_channelName);

  /// Registers this class as the default instance of [PathProviderPlatform].
  static void registerWith() {
    PathProviderPlatform.instance = PathProviderTvos();
  }

  @override
  Future<String?> getTemporaryPath() {
    return _channel.invokeMethod<String>('getTemporaryDirectory');
  }

  @override
  Future<String?> getApplicationSupportPath() {
    return _channel.invokeMethod<String>('getApplicationSupportDirectory');
  }

  @override
  Future<String?> getApplicationDocumentsPath() {
    return _channel.invokeMethod<String>('getApplicationDocumentsDirectory');
  }

  @override
  Future<String?> getApplicationCachePath() {
    return _channel.invokeMethod<String>('getApplicationCacheDirectory');
  }

  @override
  Future<String?> getLibraryPath() {
    return _channel.invokeMethod<String>('getLibraryDirectory');
  }

  @override
  Future<String?> getDownloadsPath() async {
    // tvOS sandbox has no user-facing Downloads directory.
    throw UnsupportedError(
      'getDownloadsPath is not supported on tvOS',
    );
  }

  @override
  Future<String?> getExternalStoragePath() async {
    throw UnsupportedError(
      'getExternalStoragePath is not supported on tvOS',
    );
  }

  @override
  Future<List<String>?> getExternalCachePaths() async {
    throw UnsupportedError(
      'getExternalCachePaths is not supported on tvOS',
    );
  }

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async {
    throw UnsupportedError(
      'getExternalStoragePaths is not supported on tvOS',
    );
  }
}
