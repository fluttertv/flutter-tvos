// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:flutter_tools/src/ios/device_support.dart';
import 'package:flutter_tools/src/ios/lldb.dart';

/// Xcode Device Support symbols for a physical Apple TV.
///
/// Flutter 3.47.4 made [LLDB.attachAndStart] take an [IOSDeviceSupport]. lldb
/// uses it for a `platform select remote-ios --sysroot <symbols>` sent before
/// the attach whenever [existingDeviceSupportSymbols] is non-null, and for the
/// message it prints when the attach passes one minute. The same release also
/// added a `platform status` step to every attach; that one does not depend on
/// this class and runs on tvOS as it does on iOS.
///
/// Upstream's implementation cannot serve tvOS as-is: it hardcodes
/// `~/Library/Developer/Xcode/iOS DeviceSupport`, and Apple TV symbols live in
/// `tvOS DeviceSupport`. This implements the same interface against the tvOS
/// directory, with one deliberate difference:
///
/// [existingDeviceSupportSymbols] is always null, so lldb is never told to
/// select the `remote-ios` platform for an Apple TV and finds the tvOS symbols
/// on its own, as it did on 3.47.3. The command is hardcoded in a private
/// method of [LLDB], selecting the iOS platform for a tvOS process is untested
/// on hardware, and the lldb attach is the only path that sustains a device
/// debug session.
///
/// [missingSymbolsWarning] never returns null for the slow-attach message:
/// upstream turns null into an error asking the user to file a flutter/flutter
/// bug, and on an Apple TV a slow attach with complete symbols is usually the
/// wireless tunnel, not a Flutter bug.
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

  /// Does nothing. Upstream's copy (`xcodebuild -prepareDeviceSupport`) is
  /// called only from `IOSDevice.startApp`, which an Apple TV never goes
  /// through; this exists to satisfy the interface.
  @override
  Future<void> prepareDeviceSupport() async {}

  /// Whether Xcode has finished preparing [device]: `.finalized` is present
  /// and so are the symbols, either directly under the device directory or one
  /// level down. The second layout is how Xcode 27 stores iOS symbols
  /// (`<device>/arm64e/Symbols`, flutter/flutter#189284); whether it does the
  /// same for tvOS is not known yet, and accepting both keeps this from
  /// reporting a complete copy as unfinished if it does.
  ///
  /// `.copying_lock` and `.processing_lock` survive a successful copy, so they
  /// say nothing either way.
  static bool _isPrepared(Directory device) {
    if (!device.childFile('.finalized').existsSync()) {
      return false;
    }
    if (device.childDirectory('Symbols').existsSync()) {
      return true;
    }
    return device.listSync().whereType<Directory>().any(
      (Directory child) => child.childDirectory('Symbols').existsSync(),
    );
  }

  /// Called with `warnWhenSymbolsExist: false` by [LLDB] when an attach passes
  /// one minute, and with `true` when lldb logs, after attaching, that it is
  /// reading system libraries from the device (see `TvosDevice.attachLldb`).
  /// Once the first has printed, [LLDB] drops that log line, so the second
  /// never follows a slow attach.
  @override
  String? missingSymbolsWarning({bool warnWhenSymbolsExist = false}) {
    const slowOverNetwork =
        'Without it lldb reads system libraries over the network and the app may '
        'hang during launch.';
    final Directory? device = deviceDirectory;

    if (device == null) {
      return 'flutter-tvos could not work out where Xcode keeps debugger support '
          'for this Apple TV, so it cannot check whether it is ready. $slowOverNetwork\n'
          'Open Xcode with the Apple TV connected (Window ▸ Devices and Simulators) '
          'and wait for it to finish preparing the device, then retry.';
    }

    if (_isPrepared(device)) {
      if (warnWhenSymbolsExist) {
        return 'Xcode has prepared debugger support for this Apple TV, but lldb is '
            'reading system libraries from the device instead, so the copy is '
            'probably stale or incomplete. $slowOverNetwork\n'
            'Remove it and let Xcode prepare the device again:\n'
            '  1. rm -rf "${device.path}"\n'
            '  2. Open Xcode with the Apple TV connected (Window ▸ Devices and '
            'Simulators) and wait for it to finish preparing the device, then retry.';
      }
      // This message is the only one a slow attach gets: printing it makes LLDB
      // drop the "read from process memory" line that would otherwise produce
      // the stale-copy warning above. So it names both causes.
      return 'Debugger support for this Apple TV is in place, so the delay is most '
          'likely the wireless connection: an Apple TV has no USB data port, and '
          'attaching over the network can take well over a minute.\n'
          'If it does not attach, restart the Apple TV (Settings ▸ System ▸ Restart) '
          'and run again. On a slow network, raise the limit with '
          'FLUTTER_TVOS_LLDB_ATTACH_TIMEOUT_SECONDS.\n'
          'If it is slow every time, the prepared copy may be stale. Remove it and '
          'let Xcode prepare the device again:\n'
          '  1. rm -rf "${device.path}"\n'
          '  2. Open Xcode with the Apple TV connected (Window ▸ Devices and '
          'Simulators) and wait for it to finish preparing the device, then retry.';
    }

    final status = device.existsSync()
        ? 'Xcode has not finished preparing debugger support for this Apple TV.'
        : 'Xcode has not prepared debugger support for this Apple TV.';
    return '$status $slowOverNetwork\n'
        'Open Xcode with the Apple TV connected (Window ▸ Devices and Simulators) '
        'and wait for it to finish preparing the device, then retry. '
        'It is expected at: ${device.path}';
  }
}
