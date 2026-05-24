#!/bin/bash
# Generate tvOS patches from a built engine workspace.
#
# Run this after manually applying and fixing patches in a workspace to
# capture the final diff as numbered patch files for the next release.
#
# Usage:
#   ./engine/generate_patches.sh --version <x.y.z> --engine-src <path>
#
# Arguments:
#   --version <x.y.z>     Flutter version to create patches for (required)
#   --engine-src <path>   Path to engine/src inside a built workspace (required)
#
# Example:
#   ./engine/generate_patches.sh --version 3.45.0 --engine-src ~/tvos_engine_builds/3.45.0/engine/src
#
# After generation:
#   1. Review engine/flutter3.45.0/patches/ — subrepo patches (01-04) are
#      fully automatic. Monorepo patch (05-15) may need manual splitting if
#      generate_patches.sh produced a single flutter-engine.full.patch.tmp.
#   2. Test: ./engine/build.sh debug_sim --version 3.45.0
#   3. Commit the new engine/flutter3.45.0/ directory.

set -e

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

FLUTTER_VERSION=""
ENGINE_SRC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)    FLUTTER_VERSION="$2"; shift 2 ;;
    --engine-src) ENGINE_SRC="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$FLUTTER_VERSION" ] || [ -z "$ENGINE_SRC" ]; then
  echo "Usage: $0 --version <x.y.z> --engine-src <path>"
  exit 1
fi

OUTPUT_DIR="$REPO_ROOT/engine/flutter${FLUTTER_VERSION}"
PATCHES_DIR="$OUTPUT_DIR/patches"
NEW_FILES_DIR="$OUTPUT_DIR/new_files/darwin_ios_source"

mkdir -p "$PATCHES_DIR" "$NEW_FILES_DIR"

DART_DIR="$ENGINE_SRC/flutter/third_party/dart"
SKIA_DIR="$ENGINE_SRC/flutter/third_party/skia"
PERFETTO_DIR="$ENGINE_SRC/flutter/third_party/dart/third_party/perfetto/src"
# Monorepo git root is two levels above engine/src
MONOREPO_ROOT="$(cd "$ENGINE_SRC/../.." && pwd)"
IOS_SOURCE="$ENGINE_SRC/flutter/shell/platform/darwin/ios/framework/Source"

echo "Generating patches for Flutter $FLUTTER_VERSION"
echo "Engine src: $ENGINE_SRC"
echo "Output:     $OUTPUT_DIR"
echo ""

# Record the flutter commit
FLUTTER_COMMIT=$(cd "$ENGINE_SRC/flutter" && git rev-parse HEAD 2>/dev/null || true)
if [ -n "$FLUTTER_COMMIT" ]; then
  echo "$FLUTTER_COMMIT" > "$OUTPUT_DIR/flutter_commit.txt"
  echo "flutter_commit.txt: $FLUTTER_COMMIT"
fi

# --- Subrepo patches (fully automatic) ---
echo ""
echo "--- Subrepo patches ---"

if [ -d "$DART_DIR" ]; then
  cd "$DART_DIR"
  git diff HEAD -- runtime/platform/globals.h runtime/vm/virtual_memory.h sdk/lib/io/platform.dart \
    > "$PATCHES_DIR/01-dart-globals.patch"
  git diff HEAD -- runtime/bin/process_macos.cc \
    > "$PATCHES_DIR/02-dart-process.patch"
  echo "  01-dart-globals.patch ($(wc -l < "$PATCHES_DIR/01-dart-globals.patch") lines)"
  echo "  02-dart-process.patch ($(wc -l < "$PATCHES_DIR/02-dart-process.patch") lines)"
fi

if [ -d "$PERFETTO_DIR" ]; then
  cd "$PERFETTO_DIR"
  git diff HEAD > "$PATCHES_DIR/03-perfetto.patch"
  echo "  03-perfetto.patch ($(wc -l < "$PATCHES_DIR/03-perfetto.patch") lines)"
fi

if [ -d "$SKIA_DIR" ]; then
  cd "$SKIA_DIR"
  git diff HEAD > "$PATCHES_DIR/04-skia.patch"
  echo "  04-skia.patch ($(wc -l < "$PATCHES_DIR/04-skia.patch") lines)"
fi

# --- Monorepo patches ---
# Build config patches are split by file group (05-08).
# Engine source patches (09-15) need review — generate individually per file group.
echo ""
echo "--- Monorepo patches ---"
cd "$MONOREPO_ROOT"

git diff HEAD -- engine/src/build/config/darwin/darwin_sdk.gni \
  > "$PATCHES_DIR/05-darwin-sdk-gni.patch"
git diff HEAD -- engine/src/build/mac/darwin_sdk.py \
  > "$PATCHES_DIR/06-darwin-sdk-py.patch"
git diff HEAD -- engine/src/build/config/darwin/BUILD.gn \
  > "$PATCHES_DIR/07-darwin-build.patch"
git diff HEAD -- engine/src/build/toolchain/mac/BUILD.gn \
  > "$PATCHES_DIR/08-toolchain.patch"
git diff HEAD -- \
  engine/src/flutter/shell/platform/darwin/common/framework/Source/Logger.swift \
  > "$PATCHES_DIR/09-logger.patch"
git diff HEAD -- \
  engine/src/flutter/shell/platform/darwin/ios/framework/Headers/FlutterPlugin.h \
  engine/src/flutter/shell/platform/darwin/ios/framework/Headers/FlutterPluginAppLifeCycleDelegate.h \
  engine/src/flutter/shell/platform/darwin/ios/framework/Headers/FlutterSceneLifeCycle.h \
  > "$PATCHES_DIR/10-flutter-headers.patch"
git diff HEAD -- \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/UIPressProxy.swift \
  engine/src/flutter/tools/gn \
  > "$PATCHES_DIR/11-uipress-gn.patch"
git diff HEAD -- \
  engine/src/flutter/impeller/renderer/backend/metal/allocator_mtl.mm \
  engine/src/flutter/impeller/renderer/backend/metal/command_buffer_mtl.mm \
  engine/src/flutter/impeller/renderer/backend/metal/sampler_library_mtl.mm \
  engine/src/flutter/impeller/renderer/backend/metal/swapchain_transients_mtl.h \
  > "$PATCHES_DIR/12-impeller.patch"
git diff HEAD -- \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViews.mm \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformPlugin.h \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformPlugin.mm \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/AccessibilityFeatures.swift \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/profiler_metrics_ios.mm \
  engine/src/flutter/shell/platform/darwin/ios/rendering_api_selection.mm \
  > "$PATCHES_DIR/13-flutter-compat.patch"
git diff HEAD -- \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterAppDelegate.mm \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine_Internal.h \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPluginAppLifeCycleDelegate.mm \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPluginAppLifeCycleDelegate_internal.h \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterSceneDelegate.mm \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterSceneLifeCycle.mm \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterSceneLifeCycle_Internal.h \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterTextInputPlugin.h \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterTextInputPlugin.mm \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterUndoManagerPlugin.mm \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController_Internal.h \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/SemanticsObject.h \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/SemanticsObject.mm \
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/accessibility_bridge.mm \
  > "$PATCHES_DIR/14-flutter-impl.patch"
git diff HEAD -- engine/src/flutter/shell/platform/darwin/ios/BUILD.gn \
  > "$PATCHES_DIR/15-build-gn-ios.patch"

for i in $(seq -w 5 15); do
  f=$(ls "$PATCHES_DIR/${i}-"*.patch 2>/dev/null | head -1)
  [ -f "$f" ] && echo "  $(basename $f) ($(wc -l < "$f") lines)"
done

# --- Copy verbatim new files ---
echo ""
echo "--- New files ---"
if [ -d "$IOS_SOURCE" ]; then
  for f in FlutterTvRemotePlugin.h FlutterTvRemotePlugin.mm \
            FlutterTvRemotePlugin_Internal.h FlutterTvRemoteProtocol.h \
            FlutterTvRemoteProtocol.mm FlutterAccessibilitySelectionView.h \
            FlutterAccessibilitySelectionView.mm; do
    if [ -f "$IOS_SOURCE/$f" ]; then
      cp "$IOS_SOURCE/$f" "$NEW_FILES_DIR/$f"
      echo "  $f"
    fi
  done
fi

echo ""
echo "========================================"
echo "  Patches generated: $PATCHES_DIR"
echo "  Review patches, then test with:"
echo "  ./engine/build.sh debug_sim --version $FLUTTER_VERSION"
echo "========================================"
