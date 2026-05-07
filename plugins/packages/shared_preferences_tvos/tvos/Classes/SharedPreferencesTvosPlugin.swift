// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Flutter
import Foundation

/// tvOS implementation of `shared_preferences`, backed by
/// `UserDefaults.standard`. Keys are namespaced by the Dart side with a
/// `flutter.` prefix; this plugin stores them verbatim.
public class SharedPreferencesTvosPlugin: NSObject, FlutterPlugin {
  private static let channelName = "plugins.fluttertv.dev/shared_preferences_tvos"
  private static let keyPrefix = "flutter."

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    let instance = SharedPreferencesTvosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let defaults = UserDefaults.standard

    switch call.method {
    case "getAll":
      result(allFlutterPrefs(defaults))

    case "setValue":
      guard let args = call.arguments as? [String: Any],
            let key = args["key"] as? String,
            let value = args["value"]
      else {
        result(FlutterError(code: "bad_args",
                            message: "setValue requires key and value",
                            details: nil))
        return
      }
      defaults.set(value, forKey: key)
      result(true)

    case "remove":
      guard let args = call.arguments as? [String: Any],
            let key = args["key"] as? String
      else {
        result(FlutterError(code: "bad_args",
                            message: "remove requires key",
                            details: nil))
        return
      }
      defaults.removeObject(forKey: key)
      result(true)

    case "clear":
      for key in allFlutterPrefs(defaults).keys {
        defaults.removeObject(forKey: key)
      }
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Returns every entry in `NSUserDefaults` whose key starts with the
  /// `flutter.` namespace prefix used by `shared_preferences`.
  private func allFlutterPrefs(_ defaults: UserDefaults) -> [String: Any] {
    var out: [String: Any] = [:]
    for (key, value) in defaults.dictionaryRepresentation()
    where key.hasPrefix(Self.keyPrefix) {
      out[key] = value
    }
    return out
  }
}
