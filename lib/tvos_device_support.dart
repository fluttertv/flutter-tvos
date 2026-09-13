// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:flutter_tools/src/ios/device_support.dart';
import 'package:flutter_tools/src/ios/lldb.dart';

/// Xcode Device Support symbols for a physical Apple TV.
///
/// Flutter 3.47.4 made [LLDB.attachAndStart] take an [IOSDeviceSupport], which
/// it uses for two things: a warning when the attach is slow, and a
/// `platform select remote-ios --sysroot <symbols>` sent to lldb before the
/// attach whenever [existingDeviceSupportSymbols] is non-null.
///
/// Upstream's implementation cannot serve tvOS as-is: it hardcodes
/// `~/Library/Developer/Xcode/iOS DeviceSupport`, and Apple TV symbols live in
/// `tvOS DeviceSupport`. This implements the same interface against the tvOS
/// directory, with one deliberate difference:
///
/// [existingDeviceSupportSymbols] is always null, so lldb is never told to
/// select the `remote-ios` platform for an Apple TV. The attach sequence stays
/// exactly what it was on 3.47.3, where lldb found the tvOS symbols on its own.
/// Selecting the iOS platform for a tvOS process is untested on hardware, and
/// the lldb attach is the only path that sustains a device debug session.
///
/// [missingSymbolsWarning] does look at the tvOS directory, because a missing
/// or unfinished copy there is the known cause of a device debug run that
/// hangs with no error.
class TvosDeviceSupport implements IOSDeviceSupport {
  TvosDeviceSupport({
    required Directory? homeDirectory,
    required String? modelCode,
    required String? operatingSystemVersion,
  }) : _homeDirectory = homeDirectory,
       _modelCode = modelCode,
       _operatingSystemVersion = operatingSystemVersion;

  final Directory? _homeDirectory;
  final String? _modelCode;
  final String? _operatingSystemVersion;

  /// `~/Library/Developer/Xcode/tvOS DeviceSupport/<model> <version> (<build>)`,
  /// the name Xcode gives it, e.g. `AppleTV14,1 26.6 (23L773)`. Null when the
  /// home directory or the device's model or OS version is unknown.
  Directory? get deviceDirectory {
    if (_homeDirectory == null || _modelCode == null || _operatingSystemVersion == null) {
      return null;
    }
    return _homeDirectory
        .childDirectory('Library')
        .childDirectory('Developer')
        .childDirectory('Xcode')
        .childDirectory('tvOS DeviceSupport')
        .childDirectory('$_modelCode $_operatingSystemVersion');
  }

  /// Always null. See the class documentation.
  @override
  Directory? get existingDeviceSupportSymbols => null;

  /// Does nothing. Upstream copies symbols with `xcodebuild -prepareDeviceSupport`
  /// only when [existingDeviceSupportSymbols] is null, which here is always.
  @override
  Future<void> prepareDeviceSupport() async {}

  @override
  String? missingSymbolsWarning({bool warnWhenSymbolsExist = false}) {
    final Directory? device = deviceDirectory;
    if (device == null) {
      return null;
    }
    // `.finalized` is written when Xcode finishes. `.copying_lock` and
    // `.processing_lock` survive a successful copy, so they say nothing.
    final bool finished =
        device.childDirectory('Symbols').existsSync() &&
        device.childFile('.finalized').existsSync();
    if (finished) {
      return null;
    }
    final status = device.existsSync()
        ? 'Xcode has not finished preparing debugger support for this Apple TV.'
        : 'Xcode has not prepared debugger support for this Apple TV.';
    return '$status Without it lldb reads system libraries over the network and '
        'the app may hang during launch.\n'
        'Open Xcode with the Apple TV connected (Window ▸ Devices and Simulators) '
        'and wait for it to finish preparing the device, then retry. '
        'It is expected at: ${device.path}';
  }
}
