// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/project_migrator.dart';
import 'package:meta/meta.dart';

/// The bundle identifier prefix of every code-asset framework flutter-tvos
/// installs. The embed phase recognizes the frameworks it put in the app by
/// it, to remove the ones a later build no longer has.
const String kCodeAssetBundleIdentifierPrefix = 'io.flutter.flutter.native-assets.';

/// The shell lines of the "Embed Flutter.framework" build phase that embed the
/// code assets staged in `tvos/Flutter/native_assets`, in the form a person
/// adds them to the phase by hand: after the engine's own lines, which define
/// `DEST_FRAMEWORKS`.
///
/// The template's phase is the 1.12.0 phase followed by these lines; a test
/// holds the two together.
const String kCodeAssetEmbedScript = r'''
# Code assets: the native libraries packages ship for dart:ffi through Dart
# build hooks. flutter-tvos installs each as a framework under
# tvos/Flutter/native_assets -- the layout upstream Flutter embeds for iOS --
# signed ad hoc. Embed them next to the engine, put their dSYMs with the app's,
# and sign them the same way as the engine.
NATIVE_ASSETS_SRC="${PROJECT_DIR}/Flutter/native_assets"
# First drop the code-asset frameworks an earlier build embedded that this one
# no longer stages (a package that stopped shipping a library, or code assets
# turned off). They are recognized by their bundle identifier.
for EMBEDDED in "${DEST_FRAMEWORKS}"/*.framework; do
  [ -d "${EMBEDDED}" ] || continue
  EMBEDDED_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${EMBEDDED}/Info.plist" 2>/dev/null)"
  case "${EMBEDDED_ID}" in
    io.flutter.flutter.native-assets.*)
      if [ ! -d "${NATIVE_ASSETS_SRC}/${EMBEDDED##*/}" ]; then
        echo "Removing ${EMBEDDED##*/}, which this build no longer has..."
        rm -rf "${EMBEDDED}"
      fi
      ;;
  esac
done
for NATIVE_ASSET in "${NATIVE_ASSETS_SRC}"/*.framework; do
  [ -d "${NATIVE_ASSET}" ] || continue
  NATIVE_ASSET_NAME="$(basename "${NATIVE_ASSET}")"
  echo "Embedding ${NATIVE_ASSET_NAME}..."
  rsync -a --delete "${NATIVE_ASSET}" "${DEST_FRAMEWORKS}/"
  if [ -d "${NATIVE_ASSET}.dSYM" ]; then
    rsync -a --delete "${NATIVE_ASSET}.dSYM" "${BUILT_PRODUCTS_DIR}/"
  fi
  if [ "${CODE_SIGNING_REQUIRED}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY}" ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${DEST_FRAMEWORKS}/${NATIVE_ASSET_NAME}"
  fi
done
''';

/// Escapes [script] the way a `project.pbxproj` stores a `shellScript`.
String pbxprojEscapeScript(String script) =>
    script.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');

/// The "Embed Flutter.framework" phase scripts flutter-tvos has generated
/// before it embedded code assets, as they appear in `project.pbxproj`.
///
/// Only an exact match is migrated: a phase someone edited is theirs.
@visibleForTesting
const Map<String, String> embedFlutterFrameworkScriptsBeforeCodeAssets = <String, String>{
  // Created by dev builds between the phase's introduction (56eed7c) and
  // 2452a03, which reworded one comment; never in a release.
  'pre-1.9.0': r'''#!/bin/sh\n# Embed + code-sign the Flutter engine into the app bundle.\n#\n# flutter-tvos stages the engine at tvos/Flutter/Flutter.framework on every\n# build/run, and the Runner scheme's \"Prepare Flutter framework\" pre-action\n# copies it into BUILT_PRODUCTS_DIR so the Swift package targets can compile\n# against it. Neither of those puts it in the bundle -- this phase does,\n# mirroring what upstream Flutter's xcode_backend does for iOS. Runs for build,\n# run, AND archive, so TestFlight/App Store builds get it too.\n#\n# Headers and Modules are compile-time only. Xcode's own framework embed strips\n# them, so strip them here too rather than shipping them inside every app.\n#\n# The engine must never reach Apple unsigned: an unsigned Flutter.framework\n# uploads fine and passes internal TestFlight, then is rejected at external Beta\n# App Review with ITMS-91065 (\"Missing signature\"), because Flutter is on\n# Apple's commonly-used-SDK list. Sign it with the app's own identity, the same\n# thing upstream Flutter does to the engine it copies.\n#\n# Use CODESIGNING_FOLDER_PATH (the bundle being signed), not ${PRODUCT_NAME}.app,\n# which is wrong whenever the product name is overridden.\nFRAMEWORK_SRC=\"${PROJECT_DIR}/Flutter/Flutter.framework\"\nDEST_FRAMEWORKS=\"${CODESIGNING_FOLDER_PATH}/Frameworks\"\nif [ ! -d \"${FRAMEWORK_SRC}\" ]; then\n  echo \"error: ${FRAMEWORK_SRC} does not exist, so this build would ship without a Flutter engine. Run 'flutter-tvos build tvos' (or 'flutter-tvos run') for this configuration first, then build again.\"\n  exit 1\nfi\necho \"Embedding Flutter.framework...\"\nmkdir -p \"${DEST_FRAMEWORKS}\"\nrsync -a --delete --filter \"- Headers\" --filter \"- Modules\" \"${FRAMEWORK_SRC}\" \"${DEST_FRAMEWORKS}/\"\nif [ \"${CODE_SIGNING_REQUIRED}\" = \"NO\" ] || [ -z \"${EXPANDED_CODE_SIGN_IDENTITY}\" ]; then\n  echo \"Skipping Flutter.framework signing (code signing not required for this build).\"\nelse\n  echo \"Codesigning Flutter.framework with ${EXPANDED_CODE_SIGN_IDENTITY}...\"\n  codesign --force --sign \"${EXPANDED_CODE_SIGN_IDENTITY}\" --timestamp=none --generate-entitlement-der \"${DEST_FRAMEWORKS}/Flutter.framework\"\nfi\n''',
  // Created by 1.9.0 through 1.12.0.
  '1.9.0-1.12.0': r'''#!/bin/sh\n# Embed + code-sign the Flutter engine into the app bundle.\n#\n# flutter-tvos stages the engine at tvos/Flutter/Flutter.framework on every\n# build/run, and the Runner scheme's \"Prepare Flutter framework\" pre-action\n# copies it into BUILT_PRODUCTS_DIR so the Swift package targets can compile\n# against it. Neither of those puts it in the bundle -- this phase does,\n# mirroring what upstream Flutter's xcode_backend does for iOS. Runs for build,\n# run, AND archive, so TestFlight/App Store builds get it too.\n#\n# Headers and Modules are compile-time only. Xcode's own framework embed strips\n# them, so strip them here too rather than shipping them inside every app.\n#\n# Sign the embedded engine with the app's own identity, the same thing upstream\n# Flutter does to the engine it copies -- a framework that reaches the bundle\n# unsigned fails to load. This is NOT what satisfies Apple's ITMS-91065 check:\n# that needs a Developer ID signature on the engine BEFORE this phase embeds\n# it, which flutter-tvos applies to its artifact cache on every device build.\n#\n# Use CODESIGNING_FOLDER_PATH (the bundle being signed), not ${PRODUCT_NAME}.app,\n# which is wrong whenever the product name is overridden.\nFRAMEWORK_SRC=\"${PROJECT_DIR}/Flutter/Flutter.framework\"\nDEST_FRAMEWORKS=\"${CODESIGNING_FOLDER_PATH}/Frameworks\"\nif [ ! -d \"${FRAMEWORK_SRC}\" ]; then\n  echo \"error: ${FRAMEWORK_SRC} does not exist, so this build would ship without a Flutter engine. Run 'flutter-tvos build tvos' (or 'flutter-tvos run') for this configuration first, then build again.\"\n  exit 1\nfi\necho \"Embedding Flutter.framework...\"\nmkdir -p \"${DEST_FRAMEWORKS}\"\nrsync -a --delete --filter \"- Headers\" --filter \"- Modules\" \"${FRAMEWORK_SRC}\" \"${DEST_FRAMEWORKS}/\"\nif [ \"${CODE_SIGNING_REQUIRED}\" = \"NO\" ] || [ -z \"${EXPANDED_CODE_SIGN_IDENTITY}\" ]; then\n  echo \"Skipping Flutter.framework signing (code signing not required for this build).\"\nelse\n  echo \"Codesigning Flutter.framework with ${EXPANDED_CODE_SIGN_IDENTITY}...\"\n  codesign --force --sign \"${EXPANDED_CODE_SIGN_IDENTITY}\" --timestamp=none --generate-entitlement-der \"${DEST_FRAMEWORKS}/Flutter.framework\"\nfi\n''',
};

/// The current "Embed Flutter.framework" phase script, as the template has it.
String get currentEmbedFlutterFrameworkScript =>
    embedFlutterFrameworkScriptsBeforeCodeAssets['1.9.0-1.12.0']! +
    pbxprojEscapeScript(kCodeAssetEmbedScript);

const String _phaseHeader = '/* Embed Flutter.framework */ = {';
const String _engineInputPath = '\t\t\t\t"\$(PROJECT_DIR)/Flutter/Flutter.framework",\n';
const String _codeAssetsInputPath = '\t\t\t\t"\$(PROJECT_DIR)/Flutter/native_assets",\n';

/// Brings an unmodified "Embed Flutter.framework" phase that predates code
/// assets up to the current one, which also embeds them.
///
/// `project.pbxproj` is written once, at `create`, and never regenerated, so
/// without this a project created with 1.12.0 or earlier would build an app
/// without the libraries its packages' hooks produce — and archiving from
/// Xcode, which never runs flutter-tvos, would keep doing so. Rewriting the
/// phase fixes both, the way upstream's Xcode migrators fix a stock project.
///
/// It touches nothing else, and nothing unless the phase script is exactly one
/// flutter-tvos generated ([embedFlutterFrameworkScriptsBeforeCodeAssets]).
/// Anything else is left to the build, which explains what to add.
class TvosEmbedPhaseMigration extends ProjectMigrator {
  TvosEmbedPhaseMigration(this._pbxproj, super.logger);

  final File _pbxproj;

  @override
  Future<void> migrate() async {
    if (!_pbxproj.existsSync()) {
      return;
    }
    final String original;
    try {
      original = _pbxproj.readAsStringSync();
    } on FileSystemException {
      return; // The build reports a project it cannot read.
    }
    final String? migrated = migrateEmbedPhase(original);
    if (migrated == null) {
      return;
    }
    _pbxproj.writeAsStringSync(migrated);
    logger.printStatus(
      'Updated the "Embed Flutter.framework" build phase in ${_pbxproj.path} '
      'to the current one, which also embeds the native libraries Dart build '
      'hooks produce (code assets). The phase was unmodified from the one an '
      'earlier flutter-tvos created; keep the change with your project.',
    );
  }

  /// [pbxproj] with its "Embed Flutter.framework" phase migrated, or null when
  /// there is nothing to migrate: no such phase, one that already embeds code
  /// assets, or one that is not a known generated phase.
  @visibleForTesting
  static String? migrateEmbedPhase(String pbxproj) {
    final int start = pbxproj.indexOf(_phaseHeader);
    if (start < 0) {
      return null;
    }
    final int end = pbxproj.indexOf('\n\t\t};', start);
    if (end < 0) {
      return null;
    }
    String phase = pbxproj.substring(start, end);
    if (phase.contains('Flutter/native_assets')) {
      return null;
    }
    String? known;
    for (final String script in embedFlutterFrameworkScriptsBeforeCodeAssets.values) {
      if (phase.contains('shellScript = "$script";')) {
        known = script;
        break;
      }
    }
    if (known == null) {
      return null;
    }
    phase = phase.replaceFirst(
      'shellScript = "$known";',
      'shellScript = "$currentEmbedFlutterFrameworkScript";',
    );
    phase = phase.replaceFirst(_engineInputPath, _engineInputPath + _codeAssetsInputPath);
    return pbxproj.replaceRange(start, end, phase);
  }
}
