// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Flutter
import UIKit

/// tvOS implementation of `url_launcher`, backed by `UIApplication.open`.
///
/// tvOS has no in-app browser (no WebKit) and no `SFSafariViewController`,
/// so every launch delegates to the system-level `open(_:options:completionHandler:)`.
/// Only URLs with a handler installed on the Apple TV (either the system, or an
/// installed third-party app declaring the scheme) succeed.
public class UrlLauncherTvosPlugin: NSObject, FlutterPlugin {
  private static let channelName = "plugins.fluttertv.dev/url_launcher_tvos"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    let instance = UrlLauncherTvosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "canLaunch":
      result(canLaunch(call: call))

    case "launch":
      launch(call: call, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func canLaunch(call: FlutterMethodCall) -> Bool {
    guard
      let args = call.arguments as? [String: Any],
      let urlString = args["url"] as? String,
      let url = URL(string: urlString)
    else {
      return false
    }
    return UIApplication.shared.canOpenURL(url)
  }

  private func launch(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let urlString = args["url"] as? String,
      let url = URL(string: urlString)
    else {
      result(
        FlutterError(
          code: "argument_error",
          message: "Missing or invalid 'url' argument",
          details: nil))
      return
    }

    let universalLinksOnly = args["universalLinksOnly"] as? Bool ?? false
    let options: [UIApplication.OpenExternalURLOptionsKey: Any] = [
      .universalLinksOnly: universalLinksOnly
    ]

    UIApplication.shared.open(url, options: options) { success in
      result(success)
    }
  }
}
