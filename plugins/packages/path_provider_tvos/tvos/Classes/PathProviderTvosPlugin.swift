// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Flutter
import Foundation

/// tvOS implementation of `path_provider`, backed by `FileManager`.
///
/// Apple TV storage is constrained: Documents, Caches and Application
/// Support all exist but are not suitable for large or long-lived data.
/// External storage and user-visible Downloads are not supported.
public class PathProviderTvosPlugin: NSObject, FlutterPlugin {
  private static let channelName = "plugins.fluttertv.dev/path_provider_tvos"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    let instance = PathProviderTvosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getTemporaryDirectory":
      result(NSTemporaryDirectory())

    case "getApplicationDocumentsDirectory":
      result(path(for: .documentDirectory))

    case "getApplicationSupportDirectory":
      result(path(for: .applicationSupportDirectory, createIfMissing: true))

    case "getApplicationCacheDirectory":
      result(path(for: .cachesDirectory))

    case "getLibraryDirectory":
      result(path(for: .libraryDirectory))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Returns the first matching user-domain path for the given directory,
  /// optionally creating it if it does not exist.
  private func path(
    for directory: FileManager.SearchPathDirectory,
    createIfMissing: Bool = false
  ) -> String? {
    let urls = FileManager.default.urls(for: directory, in: .userDomainMask)
    guard let url = urls.first else { return nil }

    if createIfMissing && !FileManager.default.fileExists(atPath: url.path) {
      try? FileManager.default.createDirectory(
        at: url, withIntermediateDirectories: true, attributes: nil)
    }
    return url.path
  }
}
