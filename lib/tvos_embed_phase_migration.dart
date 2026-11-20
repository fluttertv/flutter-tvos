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
# Every path below is under DEST_FRAMEWORKS, which the engine's lines set; an
# empty one would point the removal at the file system root.
: "${DEST_FRAMEWORKS:?}"
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
        rm -rf "${EMBEDDED}" || exit 1
      fi
      ;;
  esac
done
for NATIVE_ASSET in "${NATIVE_ASSETS_SRC}"/*.framework; do
  [ -d "${NATIVE_ASSET}" ] || continue
  NATIVE_ASSET_NAME="$(basename "${NATIVE_ASSET}")"
  echo "Embedding ${NATIVE_ASSET_NAME}..."
  rsync -a --delete "${NATIVE_ASSET}" "${DEST_FRAMEWORKS}/" || exit 1
  if [ -d "${NATIVE_ASSET}.dSYM" ]; then
    rsync -a --delete "${NATIVE_ASSET}.dSYM" "${BUILT_PRODUCTS_DIR}/" || exit 1
  fi
  if [ "${CODE_SIGNING_REQUIRED}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY}" ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${DEST_FRAMEWORKS}/${NATIVE_ASSET_NAME}" || exit 1
  fi
done
''';

/// Escapes [script] the way a `project.pbxproj` stores a `shellScript`.
String pbxprojEscapeScript(String script) =>
    script.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');

/// Every earlier "Embed Flutter.framework" phase script flutter-tvos has
/// generated, as it appears in `project.pbxproj`.
///
/// Only an exact match is migrated: a phase someone edited is theirs.
@visibleForTesting
const Map<String, String> earlierEmbedFlutterFrameworkScripts = <String, String>{
  // Created by dev builds between the phase's introduction (56eed7c) and
  // 2452a03, which reworded one comment; never in a release.
  'pre-1.9.0': r'''#!/bin/sh\n# Embed + code-sign the Flutter engine into the app bundle.\n#\n# flutter-tvos stages the engine at tvos/Flutter/Flutter.framework on every\n# build/run, and the Runner scheme's \"Prepare Flutter framework\" pre-action\n# copies it into BUILT_PRODUCTS_DIR so the Swift package targets can compile\n# against it. Neither of those puts it in the bundle -- this phase does,\n# mirroring what upstream Flutter's xcode_backend does for iOS. Runs for build,\n# run, AND archive, so TestFlight/App Store builds get it too.\n#\n# Headers and Modules are compile-time only. Xcode's own framework embed strips\n# them, so strip them here too rather than shipping them inside every app.\n#\n# The engine must never reach Apple unsigned: an unsigned Flutter.framework\n# uploads fine and passes internal TestFlight, then is rejected at external Beta\n# App Review with ITMS-91065 (\"Missing signature\"), because Flutter is on\n# Apple's commonly-used-SDK list. Sign it with the app's own identity, the same\n# thing upstream Flutter does to the engine it copies.\n#\n# Use CODESIGNING_FOLDER_PATH (the bundle being signed), not ${PRODUCT_NAME}.app,\n# which is wrong whenever the product name is overridden.\nFRAMEWORK_SRC=\"${PROJECT_DIR}/Flutter/Flutter.framework\"\nDEST_FRAMEWORKS=\"${CODESIGNING_FOLDER_PATH}/Frameworks\"\nif [ ! -d \"${FRAMEWORK_SRC}\" ]; then\n  echo \"error: ${FRAMEWORK_SRC} does not exist, so this build would ship without a Flutter engine. Run 'flutter-tvos build tvos' (or 'flutter-tvos run') for this configuration first, then build again.\"\n  exit 1\nfi\necho \"Embedding Flutter.framework...\"\nmkdir -p \"${DEST_FRAMEWORKS}\"\nrsync -a --delete --filter \"- Headers\" --filter \"- Modules\" \"${FRAMEWORK_SRC}\" \"${DEST_FRAMEWORKS}/\"\nif [ \"${CODE_SIGNING_REQUIRED}\" = \"NO\" ] || [ -z \"${EXPANDED_CODE_SIGN_IDENTITY}\" ]; then\n  echo \"Skipping Flutter.framework signing (code signing not required for this build).\"\nelse\n  echo \"Codesigning Flutter.framework with ${EXPANDED_CODE_SIGN_IDENTITY}...\"\n  codesign --force --sign \"${EXPANDED_CODE_SIGN_IDENTITY}\" --timestamp=none --generate-entitlement-der \"${DEST_FRAMEWORKS}/Flutter.framework\"\nfi\n''',
  // Created by 1.9.0 through 1.12.0.
  '1.9.0-1.12.0': r'''#!/bin/sh\n# Embed + code-sign the Flutter engine into the app bundle.\n#\n# flutter-tvos stages the engine at tvos/Flutter/Flutter.framework on every\n# build/run, and the Runner scheme's \"Prepare Flutter framework\" pre-action\n# copies it into BUILT_PRODUCTS_DIR so the Swift package targets can compile\n# against it. Neither of those puts it in the bundle -- this phase does,\n# mirroring what upstream Flutter's xcode_backend does for iOS. Runs for build,\n# run, AND archive, so TestFlight/App Store builds get it too.\n#\n# Headers and Modules are compile-time only. Xcode's own framework embed strips\n# them, so strip them here too rather than shipping them inside every app.\n#\n# Sign the embedded engine with the app's own identity, the same thing upstream\n# Flutter does to the engine it copies -- a framework that reaches the bundle\n# unsigned fails to load. This is NOT what satisfies Apple's ITMS-91065 check:\n# that needs a Developer ID signature on the engine BEFORE this phase embeds\n# it, which flutter-tvos applies to its artifact cache on every device build.\n#\n# Use CODESIGNING_FOLDER_PATH (the bundle being signed), not ${PRODUCT_NAME}.app,\n# which is wrong whenever the product name is overridden.\nFRAMEWORK_SRC=\"${PROJECT_DIR}/Flutter/Flutter.framework\"\nDEST_FRAMEWORKS=\"${CODESIGNING_FOLDER_PATH}/Frameworks\"\nif [ ! -d \"${FRAMEWORK_SRC}\" ]; then\n  echo \"error: ${FRAMEWORK_SRC} does not exist, so this build would ship without a Flutter engine. Run 'flutter-tvos build tvos' (or 'flutter-tvos run') for this configuration first, then build again.\"\n  exit 1\nfi\necho \"Embedding Flutter.framework...\"\nmkdir -p \"${DEST_FRAMEWORKS}\"\nrsync -a --delete --filter \"- Headers\" --filter \"- Modules\" \"${FRAMEWORK_SRC}\" \"${DEST_FRAMEWORKS}/\"\nif [ \"${CODE_SIGNING_REQUIRED}\" = \"NO\" ] || [ -z \"${EXPANDED_CODE_SIGN_IDENTITY}\" ]; then\n  echo \"Skipping Flutter.framework signing (code signing not required for this build).\"\nelse\n  echo \"Codesigning Flutter.framework with ${EXPANDED_CODE_SIGN_IDENTITY}...\"\n  codesign --force --sign \"${EXPANDED_CODE_SIGN_IDENTITY}\" --timestamp=none --generate-entitlement-der \"${DEST_FRAMEWORKS}/Flutter.framework\"\nfi\n''',
  // The first two revisions of the code-asset phase, on the unreleased branch
  // of fluttertv/flutter-tvos#98 (e59a782, d221e14).
  'code-assets-r1': r'''#!/bin/sh\n# Embed + code-sign the Flutter engine into the app bundle.\n#\n# flutter-tvos stages the engine at tvos/Flutter/Flutter.framework on every\n# build/run, and the Runner scheme's \"Prepare Flutter framework\" pre-action\n# copies it into BUILT_PRODUCTS_DIR so the Swift package targets can compile\n# against it. Neither of those puts it in the bundle -- this phase does,\n# mirroring what upstream Flutter's xcode_backend does for iOS. Runs for build,\n# run, AND archive, so TestFlight/App Store builds get it too.\n#\n# Headers and Modules are compile-time only. Xcode's own framework embed strips\n# them, so strip them here too rather than shipping them inside every app.\n#\n# Sign the embedded engine with the app's own identity, the same thing upstream\n# Flutter does to the engine it copies -- a framework that reaches the bundle\n# unsigned fails to load. This is NOT what satisfies Apple's ITMS-91065 check:\n# that needs a Developer ID signature on the engine BEFORE this phase embeds\n# it, which flutter-tvos applies to its artifact cache on every device build.\n#\n# Use CODESIGNING_FOLDER_PATH (the bundle being signed), not ${PRODUCT_NAME}.app,\n# which is wrong whenever the product name is overridden.\nFRAMEWORK_SRC=\"${PROJECT_DIR}/Flutter/Flutter.framework\"\nDEST_FRAMEWORKS=\"${CODESIGNING_FOLDER_PATH}/Frameworks\"\nif [ ! -d \"${FRAMEWORK_SRC}\" ]; then\n  echo \"error: ${FRAMEWORK_SRC} does not exist, so this build would ship without a Flutter engine. Run 'flutter-tvos build tvos' (or 'flutter-tvos run') for this configuration first, then build again.\"\n  exit 1\nfi\necho \"Embedding Flutter.framework...\"\nmkdir -p \"${DEST_FRAMEWORKS}\"\nrsync -a --delete --filter \"- Headers\" --filter \"- Modules\" \"${FRAMEWORK_SRC}\" \"${DEST_FRAMEWORKS}/\"\nif [ \"${CODE_SIGNING_REQUIRED}\" = \"NO\" ] || [ -z \"${EXPANDED_CODE_SIGN_IDENTITY}\" ]; then\n  echo \"Skipping Flutter.framework signing (code signing not required for this build).\"\nelse\n  echo \"Codesigning Flutter.framework with ${EXPANDED_CODE_SIGN_IDENTITY}...\"\n  codesign --force --sign \"${EXPANDED_CODE_SIGN_IDENTITY}\" --timestamp=none --generate-entitlement-der \"${DEST_FRAMEWORKS}/Flutter.framework\"\nfi\n# Code assets: the native libraries packages ship for dart:ffi through Dart\n# build hooks. flutter-tvos installs each as a framework under\n# tvos/Flutter/native_assets -- the layout upstream Flutter embeds for iOS --\n# signed ad hoc. Embed them next to the engine, put their dSYMs with the app's,\n# and sign them the same way as the engine.\nNATIVE_ASSETS_SRC=\"${PROJECT_DIR}/Flutter/native_assets\"\nfor NATIVE_ASSET in \"${NATIVE_ASSETS_SRC}\"/*.framework; do\n  [ -d \"${NATIVE_ASSET}\" ] || continue\n  NATIVE_ASSET_NAME=\"$(basename \"${NATIVE_ASSET}\")\"\n  echo \"Embedding ${NATIVE_ASSET_NAME}...\"\n  rsync -a --delete \"${NATIVE_ASSET}\" \"${DEST_FRAMEWORKS}/\"\n  if [ -d \"${NATIVE_ASSET}.dSYM\" ]; then\n    rsync -a --delete \"${NATIVE_ASSET}.dSYM\" \"${BUILT_PRODUCTS_DIR}/\"\n  fi\n  if [ \"${CODE_SIGNING_REQUIRED}\" != \"NO\" ] && [ -n \"${EXPANDED_CODE_SIGN_IDENTITY}\" ]; then\n    codesign --force --sign \"${EXPANDED_CODE_SIGN_IDENTITY}\" --timestamp=none \"${DEST_FRAMEWORKS}/${NATIVE_ASSET_NAME}\"\n  fi\ndone\n''',
  'code-assets-r2': r'''#!/bin/sh\n# Embed + code-sign the Flutter engine into the app bundle.\n#\n# flutter-tvos stages the engine at tvos/Flutter/Flutter.framework on every\n# build/run, and the Runner scheme's \"Prepare Flutter framework\" pre-action\n# copies it into BUILT_PRODUCTS_DIR so the Swift package targets can compile\n# against it. Neither of those puts it in the bundle -- this phase does,\n# mirroring what upstream Flutter's xcode_backend does for iOS. Runs for build,\n# run, AND archive, so TestFlight/App Store builds get it too.\n#\n# Headers and Modules are compile-time only. Xcode's own framework embed strips\n# them, so strip them here too rather than shipping them inside every app.\n#\n# Sign the embedded engine with the app's own identity, the same thing upstream\n# Flutter does to the engine it copies -- a framework that reaches the bundle\n# unsigned fails to load. This is NOT what satisfies Apple's ITMS-91065 check:\n# that needs a Developer ID signature on the engine BEFORE this phase embeds\n# it, which flutter-tvos applies to its artifact cache on every device build.\n#\n# Use CODESIGNING_FOLDER_PATH (the bundle being signed), not ${PRODUCT_NAME}.app,\n# which is wrong whenever the product name is overridden.\nFRAMEWORK_SRC=\"${PROJECT_DIR}/Flutter/Flutter.framework\"\nDEST_FRAMEWORKS=\"${CODESIGNING_FOLDER_PATH}/Frameworks\"\nif [ ! -d \"${FRAMEWORK_SRC}\" ]; then\n  echo \"error: ${FRAMEWORK_SRC} does not exist, so this build would ship without a Flutter engine. Run 'flutter-tvos build tvos' (or 'flutter-tvos run') for this configuration first, then build again.\"\n  exit 1\nfi\necho \"Embedding Flutter.framework...\"\nmkdir -p \"${DEST_FRAMEWORKS}\"\nrsync -a --delete --filter \"- Headers\" --filter \"- Modules\" \"${FRAMEWORK_SRC}\" \"${DEST_FRAMEWORKS}/\"\nif [ \"${CODE_SIGNING_REQUIRED}\" = \"NO\" ] || [ -z \"${EXPANDED_CODE_SIGN_IDENTITY}\" ]; then\n  echo \"Skipping Flutter.framework signing (code signing not required for this build).\"\nelse\n  echo \"Codesigning Flutter.framework with ${EXPANDED_CODE_SIGN_IDENTITY}...\"\n  codesign --force --sign \"${EXPANDED_CODE_SIGN_IDENTITY}\" --timestamp=none --generate-entitlement-der \"${DEST_FRAMEWORKS}/Flutter.framework\"\nfi\n# Code assets: the native libraries packages ship for dart:ffi through Dart\n# build hooks. flutter-tvos installs each as a framework under\n# tvos/Flutter/native_assets -- the layout upstream Flutter embeds for iOS --\n# signed ad hoc. Embed them next to the engine, put their dSYMs with the app's,\n# and sign them the same way as the engine.\nNATIVE_ASSETS_SRC=\"${PROJECT_DIR}/Flutter/native_assets\"\n# First drop the code-asset frameworks an earlier build embedded that this one\n# no longer stages (a package that stopped shipping a library, or code assets\n# turned off). They are recognized by their bundle identifier.\nfor EMBEDDED in \"${DEST_FRAMEWORKS}\"/*.framework; do\n  [ -d \"${EMBEDDED}\" ] || continue\n  EMBEDDED_ID=\"$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \"${EMBEDDED}/Info.plist\" 2>/dev/null)\"\n  case \"${EMBEDDED_ID}\" in\n    io.flutter.flutter.native-assets.*)\n      if [ ! -d \"${NATIVE_ASSETS_SRC}/${EMBEDDED##*/}\" ]; then\n        echo \"Removing ${EMBEDDED##*/}, which this build no longer has...\"\n        rm -rf \"${EMBEDDED}\"\n      fi\n      ;;\n  esac\ndone\nfor NATIVE_ASSET in \"${NATIVE_ASSETS_SRC}\"/*.framework; do\n  [ -d \"${NATIVE_ASSET}\" ] || continue\n  NATIVE_ASSET_NAME=\"$(basename \"${NATIVE_ASSET}\")\"\n  echo \"Embedding ${NATIVE_ASSET_NAME}...\"\n  rsync -a --delete \"${NATIVE_ASSET}\" \"${DEST_FRAMEWORKS}/\"\n  if [ -d \"${NATIVE_ASSET}.dSYM\" ]; then\n    rsync -a --delete \"${NATIVE_ASSET}.dSYM\" \"${BUILT_PRODUCTS_DIR}/\"\n  fi\n  if [ \"${CODE_SIGNING_REQUIRED}\" != \"NO\" ] && [ -n \"${EXPANDED_CODE_SIGN_IDENTITY}\" ]; then\n    codesign --force --sign \"${EXPANDED_CODE_SIGN_IDENTITY}\" --timestamp=none \"${DEST_FRAMEWORKS}/${NATIVE_ASSET_NAME}\"\n  fi\ndone\n''',
};

/// The current "Embed Flutter.framework" phase script, as the template has it.
String get currentEmbedFlutterFrameworkScript =>
    earlierEmbedFlutterFrameworkScripts['1.9.0-1.12.0']! +
    pbxprojEscapeScript(kCodeAssetEmbedScript);

const String _engineInputPath = '\t\t\t\t"\$(PROJECT_DIR)/Flutter/Flutter.framework",\n';
const String _codeAssetsInputPath = '\t\t\t\t"\$(PROJECT_DIR)/Flutter/native_assets",\n';

/// The definitions of every "Embed Flutter.framework" phase in [pbxproj]: the
/// object id, and the range from the definition's start to its closing brace.
List<({String id, int start, int end})> _embedPhaseDefinitions(String pbxproj) => <({String id, int start, int end})>[
  for (final RegExpMatch match in RegExp(
    r'([0-9A-Fa-f]{24}) /\* Embed Flutter\.framework \*/ = \{',
  ).allMatches(pbxproj))
    if (pbxproj.indexOf('\n\t\t};', match.start) case final int end when end >= 0)
      (id: match.group(1)!, start: match.start, end: end),
];

/// The escaped `shellScript` value in [phase], or null if it has none.
String? _shellScriptOf(String phase) {
  const key = 'shellScript = "';
  final int keyStart = phase.indexOf(key);
  if (keyStart < 0) {
    return null;
  }
  final int valueStart = keyStart + key.length;
  for (var i = valueStart; i < phase.length; i++) {
    if (phase[i] == r'\') {
      i++;
    } else if (phase[i] == '"') {
      return phase.substring(valueStart, i);
    }
  }
  return null;
}

/// The escaped scripts of the "Embed Flutter.framework" phases of the target
/// the build runs: the native target named `Runner`, the one the scheme builds.
///
/// Every such phase in the file when there is no `Runner` target to read, so
/// a project laid out unexpectedly is judged by all of them rather than by
/// whichever comes first.
@visibleForTesting
List<String> runnerEmbedFlutterFrameworkScripts(String pbxproj) {
  final List<({String id, int start, int end})> definitions = _embedPhaseDefinitions(pbxproj);
  final RegExpMatch? runner = RegExp(
    r'/\* Runner \*/ = \{\s*isa = PBXNativeTarget;(.*?)\n\t\t\};',
    dotAll: true,
  ).firstMatch(pbxproj);
  Set<String>? runnerPhaseIds;
  if (runner != null) {
    final String phases =
        RegExp(r'buildPhases = \((.*?)\);', dotAll: true).firstMatch(runner.group(1)!)?.group(1) ?? '';
    runnerPhaseIds = <String>{
      for (final RegExpMatch m in RegExp(
        r'([0-9A-Fa-f]{24}) /\* Embed Flutter\.framework \*/',
      ).allMatches(phases))
        m.group(1)!,
    };
  }
  return <String>[
    for (final definition in definitions)
      if (runnerPhaseIds == null || runnerPhaseIds.contains(definition.id))
        ?_shellScriptOf(pbxproj.substring(definition.start, definition.end)),
  ];
}

/// Whether the target the build runs embeds the code assets staged under
/// `Flutter/native_assets`, as far as the text of [pbxproj] shows: it has an
/// "Embed Flutter.framework" phase, and every one it has names the staging
/// directory (the current phase does, and so do the lines a person adds by
/// hand). It is a guess, so the build only traces it: an XML-format project
/// file, a script kept in a file, a renamed phase or another phase embed them
/// without this seeing it, and the built app shows after Xcode whether they
/// were embedded.
bool pbxprojEmbedsCodeAssets(String pbxproj) {
  final List<String> scripts = runnerEmbedFlutterFrameworkScripts(pbxproj);
  return scripts.isNotEmpty &&
      scripts.every((String script) => script.contains('Flutter/native_assets'));
}

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
/// flutter-tvos generated ([earlierEmbedFlutterFrameworkScripts]).
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
    try {
      _pbxproj.writeAsStringSync(migrated);
    } on FileSystemException catch (error) {
      // As upstream's migrators do with a file they cannot write: say so and
      // carry on. Whether this build can still embed its code assets is
      // decided after this, from the project as it is.
      logger.printError(
        'Could not update the "Embed Flutter.framework" build phase in '
        '${_pbxproj.path} to embed code assets: ${error.message}. '
        'Make the file writable, or update the phase by hand.',
      );
      return;
    }
    logger.printStatus(
      'Updated the "Embed Flutter.framework" build phase in ${_pbxproj.path} '
      'to the current one, which also embeds the native libraries Dart build '
      'hooks produce (code assets). The phase was unmodified from the one an '
      'earlier flutter-tvos created; keep the change with your project.',
    );
  }

  /// [pbxproj] with every "Embed Flutter.framework" phase that is an earlier
  /// generated one ([earlierEmbedFlutterFrameworkScripts]) replaced by the
  /// current one, or null when there is none to migrate.
  @visibleForTesting
  static String? migrateEmbedPhase(String pbxproj) {
    var result = pbxproj;
    var changed = false;
    // From the end, so earlier ranges stay valid as later ones change length.
    for (final ({String id, int start, int end}) definition in _embedPhaseDefinitions(pbxproj).reversed) {
      String phase = result.substring(definition.start, definition.end);
      final String? script = _shellScriptOf(phase);
      if (script == null ||
          script == currentEmbedFlutterFrameworkScript ||
          !earlierEmbedFlutterFrameworkScripts.containsValue(script)) {
        continue;
      }
      phase = phase.replaceFirst(
        'shellScript = "$script";',
        'shellScript = "$currentEmbedFlutterFrameworkScript";',
      );
      if (!phase.contains(_codeAssetsInputPath)) {
        phase = phase.replaceFirst(_engineInputPath, _engineInputPath + _codeAssetsInputPath);
      }
      result = result.replaceRange(definition.start, definition.end, phase);
      changed = true;
    }
    return changed ? result : null;
  }
}
