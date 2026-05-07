// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

const String _channelName = 'plugins.fluttertv.dev/url_launcher_tvos';

/// The tvOS implementation of [UrlLauncherPlatform].
///
/// Backed by `UIApplication.open(_:options:completionHandler:)`. tvOS has
/// no in-app browser (no WebKit), no universal links UI, and no
/// `SFSafariViewController`, so only [PreferredLaunchMode.externalApplication]
/// is meaningful. All other launch modes degrade to the external path.
///
/// URLs that no installed app can handle return `false`. App-scheme URLs
/// (e.g. `youtube://`) work if the target app is installed on the Apple TV.
class UrlLauncherTvos extends UrlLauncherPlatform {
  /// The method channel used to talk to the tvOS host plugin.
  static const MethodChannel _channel = MethodChannel(_channelName);

  /// Registers this class as the default instance of [UrlLauncherPlatform].
  static void registerWith() {
    UrlLauncherPlatform.instance = UrlLauncherTvos();
  }

  @override
  final LinkDelegate? linkDelegate = null;

  @override
  Future<bool> canLaunch(String url) async {
    final bool? result = await _channel.invokeMethod<bool>(
      'canLaunch',
      <String, Object>{'url': url},
    );
    return result ?? false;
  }

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    // tvOS has no in-app browser; all flags except the URL itself are ignored.
    final bool? result = await _channel.invokeMethod<bool>(
      'launch',
      <String, Object>{
        'url': url,
        'universalLinksOnly': universalLinksOnly,
      },
    );
    return result ?? false;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    // Mode is ignored on tvOS; we always hand off to UIApplication.open.
    final bool? result = await _channel.invokeMethod<bool>(
      'launch',
      <String, Object>{
        'url': url,
        'universalLinksOnly':
            options.mode == PreferredLaunchMode.externalNonBrowserApplication,
      },
    );
    return result ?? false;
  }

  @override
  Future<void> closeWebView() async {
    // No-op: tvOS has no in-app web view to close.
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async {
    // Only external-app launching is supported on tvOS.
    return mode == PreferredLaunchMode.platformDefault ||
        mode == PreferredLaunchMode.externalApplication ||
        mode == PreferredLaunchMode.externalNonBrowserApplication;
  }

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async {
    // Nothing to close on tvOS.
    return false;
  }
}
