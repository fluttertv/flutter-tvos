#!/bin/bash
# Build Flutter tvOS engine artifacts from upstream flutter/flutter.
#
# Usage:
#   ./engine/build.sh [variant...] [options]
#
# Variants:
#   debug_sim     — Debug simulator arm64
#   debug         — Debug device arm64
#   profile       — Profile device arm64
#   release       — Release device arm64
#   host_debug    — Host debug tools (gen_snapshot, frontend_server)
#   host_release  — Host release tools
#   all           — All six variants (default)
#
# Options:
#   --version <x.y.z>          Flutter version (default: from bin/internal/engine.version)
#   --engine-workspace <path>  Root dir for gclient checkout (default: ~/tvos_engine_builds)
#   --publish                  After build, create GitHub Release in fluttertv/engine-artifacts
#   --with-tests               Build XCTest bundle for debug variants
#
# Examples:
#   ./engine/build.sh debug_sim
#   ./engine/build.sh all --version 3.44.0
#   ./engine/build.sh all --version 3.44.0 --publish

set -e

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
ENGINE_DIR="$REPO_ROOT/engine"

# --- Parse arguments ---
VARIANTS=()
FLUTTER_VERSION=""
ENGINE_WORKSPACE_BASE="${TVOS_ENGINE_WORKSPACE:-$HOME/tvos_engine_builds}"
PUBLISH=0
WITH_TESTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)       FLUTTER_VERSION="$2"; shift 2 ;;
    --engine-workspace) ENGINE_WORKSPACE_BASE="$2"; shift 2 ;;
    --publish)       PUBLISH=1; shift ;;
    --with-tests)    WITH_TESTS=1; shift ;;
    -*)              echo "Unknown option: $1"; exit 1 ;;
    *)               VARIANTS+=("$1"); shift ;;
  esac
done

if [ ${#VARIANTS[@]} -eq 0 ] || [[ " ${VARIANTS[*]} " == *" all "* ]]; then
  VARIANTS=("host_debug" "host_release" "debug_sim" "debug" "profile" "release")
fi

# --- Resolve Flutter version ---
if [ -z "$FLUTTER_VERSION" ]; then
  ENGINE_VERSION_FILE="$REPO_ROOT/bin/internal/engine.version"
  if [ -f "$ENGINE_VERSION_FILE" ]; then
    RAW=$(cat "$ENGINE_VERSION_FILE" | tr -d '[:space:]')
    # Extract version number from tags like "v1.0.0-flutter3.44.0"
    FLUTTER_VERSION=$(echo "$RAW" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+$' || true)
  fi
fi
if [ -z "$FLUTTER_VERSION" ]; then
  echo "ERROR: Flutter version not specified. Use --version or set bin/internal/engine.version."
  exit 1
fi

VERSION_DIR="$ENGINE_DIR/flutter${FLUTTER_VERSION}"
if [ ! -d "$VERSION_DIR" ]; then
  echo "ERROR: No patch set found for Flutter $FLUTTER_VERSION at $VERSION_DIR"
  echo "Create $VERSION_DIR/patches/ with numbered patch files first."
  exit 1
fi

FLUTTER_COMMIT=$(cat "$VERSION_DIR/flutter_commit.txt" 2>/dev/null | tr -d '[:space:]')
if [ -z "$FLUTTER_COMMIT" ]; then
  echo "ERROR: $VERSION_DIR/flutter_commit.txt is missing or empty."
  exit 1
fi

# --- Workspace setup ---
WORKSPACE="$ENGINE_WORKSPACE_BASE/$FLUTTER_VERSION"
ENGINE_SRC="$WORKSPACE/engine/src"
DEPS_MARKER="$WORKSPACE/.deps_patched"

mkdir -p "$WORKSPACE"

echo "========================================"
echo "  Flutter:   $FLUTTER_VERSION ($FLUTTER_COMMIT)"
echo "  Workspace: $WORKSPACE"
echo "========================================"

# --- gclient sync if needed ---
if [ ! -f "$ENGINE_SRC/flutter/tools/gn" ]; then
  echo ""
  echo "--- gclient sync ---"
  python3 "$ENGINE_DIR/gclient_config.py" "$FLUTTER_COMMIT" > "$WORKSPACE/.gclient"

  DEPOT_TOOLS_PATH="${DEPOT_TOOLS:-$HOME/depot_tools}"
  if [ ! -d "$DEPOT_TOOLS_PATH" ]; then
    echo "ERROR: depot_tools not found at $DEPOT_TOOLS_PATH"
    echo "Set DEPOT_TOOLS env var or install to ~/depot_tools"
    exit 1
  fi
  export PATH="$DEPOT_TOOLS_PATH:$PATH"

  cd "$WORKSPACE"
  gclient sync --no-history --shallow
fi

# --- Set up PATH for build tools ---
DEPOT_TOOLS_PATH="${DEPOT_TOOLS:-$ENGINE_SRC/flutter/third_party/depot_tools}"
export PATH="$DEPOT_TOOLS_PATH:$PATH"

if command -v python3.12 >/dev/null 2>&1; then
  PYTHON312="$(command -v python3.12)"
  SHIM_DIR="$(mktemp -d)"
  ln -sf "$PYTHON312" "$SHIM_DIR/python3"
  ln -sf "$PYTHON312" "$SHIM_DIR/python"
  export PATH="$SHIM_DIR:$PATH"
  trap 'rm -rf "$SHIM_DIR"' EXIT INT TERM HUP
fi

NINJA="$DEPOT_TOOLS_PATH/ninja"
[ ! -f "$NINJA" ] && NINJA="$ENGINE_SRC/flutter/third_party/ninja/ninja"
[ ! -f "$NINJA" ] && NINJA=$(which ninja 2>/dev/null || true)
if [ -z "$NINJA" ] || [ ! -f "$NINJA" ]; then
  echo "ERROR: ninja not found."
  exit 1
fi

GN="$ENGINE_SRC/flutter/tools/gn"
if [ ! -f "$GN" ]; then
  echo "ERROR: GN not found at $GN — run gclient sync first."
  exit 1
fi

if ! xcode-select -p &>/dev/null; then
  echo "ERROR: Xcode not found."
  exit 1
fi

CONCURRENT_JOBS=${TVOS_BUILD_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}

# --- Apply patches ---
if [ ! -f "$DEPS_MARKER" ]; then
  echo ""
  echo "--- Applying tvOS patches ---"

  PATCHES_DIR="$VERSION_DIR/patches"
  DART_DIR="$ENGINE_SRC/flutter/third_party/dart"
  SKIA_DIR="$ENGINE_SRC/flutter/third_party/skia"
  PERFETTO_DIR="$ENGINE_SRC/flutter/third_party/dart/third_party/perfetto/src"
  # Monorepo git root: the flutter/flutter checkout that gclient put in $WORKSPACE
  MONOREPO_ROOT="$WORKSPACE"

  # 01-02: Dart submodule
  if [ -d "$DART_DIR" ]; then
    for patch in "$PATCHES_DIR"/0[12]-*.patch; do
      [ -f "$patch" ] || continue
      echo "  Applying $(basename $patch) → dart"
      (cd "$DART_DIR" && git apply -p0 "$patch" 2>/dev/null) || \
      (cd "$DART_DIR" && git apply "$patch" 2>/dev/null) || \
      echo "  WARNING: $(basename $patch) did not apply cleanly (may already be applied)"
    done
  fi

  # 03: Perfetto submodule
  if [ -d "$PERFETTO_DIR" ] && [ -f "$PATCHES_DIR/03-perfetto.patch" ]; then
    echo "  Applying 03-perfetto.patch → perfetto"
    (cd "$PERFETTO_DIR" && git apply -p0 "$PATCHES_DIR/03-perfetto.patch" 2>/dev/null) || \
    echo "  WARNING: 03-perfetto.patch did not apply cleanly"
  fi

  # 04: Skia submodule
  if [ -d "$SKIA_DIR" ] && [ -f "$PATCHES_DIR/04-skia.patch" ]; then
    echo "  Applying 04-skia.patch → skia"
    (cd "$SKIA_DIR" && git apply -p0 "$PATCHES_DIR/04-skia.patch" 2>/dev/null) || \
    echo "  WARNING: 04-skia.patch did not apply cleanly"
  fi

  # 05-15: Monorepo patches (build config + engine source)
  for patch in "$PATCHES_DIR"/[01][0-9]-*.patch; do
    [ -f "$patch" ] || continue
    basename_patch=$(basename "$patch")
    num="${basename_patch%%-*}"
    [[ "$num" -lt 5 ]] && continue   # skip subrepo patches already applied
    echo "  Applying $basename_patch → monorepo"
    (cd "$MONOREPO_ROOT" && git apply --ignore-whitespace "$patch" 2>/dev/null) || \
    echo "  WARNING: $basename_patch did not apply cleanly"
  done

  # Copy verbatim tvOS source files
  NEW_FILES="$VERSION_DIR/new_files/darwin_ios_source"
  IOS_SOURCE="$ENGINE_SRC/flutter/shell/platform/darwin/ios/framework/Source"
  if [ -d "$NEW_FILES" ] && [ -d "$IOS_SOURCE" ]; then
    echo "  Copying tvOS new files → ios/framework/Source/"
    cp "$NEW_FILES/"* "$IOS_SOURCE/" 2>/dev/null || true
  fi

  # Regenerate tvOS SDK symlinks in prebuilts/
  SDK_SCRIPT="$ENGINE_SRC/build/mac/darwin_sdk.py"
  PREBUILTS_DIR="$ENGINE_SRC/flutter/prebuilts"
  if [ -f "$SDK_SCRIPT" ] && [ -d "$PREBUILTS_DIR" ]; then
    echo "  Regenerating SDK symlinks via darwin_sdk.py"
    rm -rf "$PREBUILTS_DIR/Platforms" "$PREBUILTS_DIR/SDKs"
    python3 "$SDK_SCRIPT" 2>/dev/null || true
  fi

  # Copy clang_rt tvOS libs from Xcode
  BUILDTOOLS_CLANG_RT=$(ls -d "$ENGINE_SRC/flutter/buildtools/mac-arm64/clang/lib/clang/"*/lib/darwin 2>/dev/null | tail -1)
  if [ -n "$BUILDTOOLS_CLANG_RT" ]; then
    XCODE_DEV=$(xcode-select -p 2>/dev/null)
    XCODE_CLANG_RT=$(ls -d "$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/"*/lib/darwin 2>/dev/null | tail -1)
    if [ -n "$XCODE_CLANG_RT" ]; then
      for lib in libclang_rt.tvos.a libclang_rt.tvossim.a; do
        if [ ! -f "$BUILDTOOLS_CLANG_RT/$lib" ] && [ -f "$XCODE_CLANG_RT/$lib" ]; then
          echo "  Copying $lib from Xcode → buildtools"
          cp "$XCODE_CLANG_RT/$lib" "$BUILDTOOLS_CLANG_RT/$lib"
        fi
      done
    fi
  fi

  touch "$DEPS_MARKER"
  echo "--- Patches applied ---"
fi

# --- Build function ---
build_variant() {
  local variant="$1"
  local gn_flags out_dir ninja_target
  local test_target="flutter/shell/platform/darwin/ios:ios_test_flutter"

  case "$variant" in
    debug_sim)
      gn_flags="--tvos --simulator --simulator-cpu=arm64 --unoptimized --runtime-mode=debug"
      out_dir="out/tvos_debug_sim_unopt_arm64"
      ninja_target="flutter/shell/platform/darwin/ios:flutter_framework"
      ;;
    debug)
      gn_flags="--tvos --unoptimized --runtime-mode=debug"
      out_dir="out/tvos_debug_unopt"
      ninja_target="flutter/shell/platform/darwin/ios:flutter_framework"
      ;;
    profile)
      gn_flags="--tvos --runtime-mode=profile"
      out_dir="out/tvos_profile"
      ninja_target="flutter/shell/platform/darwin/ios:flutter_framework clang_arm64/gen_snapshot"
      ;;
    release)
      gn_flags="--tvos --runtime-mode=release"
      out_dir="out/tvos_release"
      ninja_target="flutter/shell/platform/darwin/ios:flutter_framework clang_arm64/gen_snapshot"
      ;;
    host_debug)
      gn_flags="--unoptimized --runtime-mode=debug"
      out_dir="out/host_debug_unopt"
      ninja_target="gen_snapshot flutter/flutter_frontend_server:frontend_server flutter/lib/snapshot:strong_platform"
      ;;
    host_release)
      gn_flags="--runtime-mode=release"
      out_dir="out/host_release"
      ninja_target="gen_snapshot flutter/flutter_frontend_server:frontend_server flutter/lib/snapshot:strong_platform"
      ;;
    *)
      echo "ERROR: Unknown variant '$variant'"; exit 1 ;;
  esac

  if [ "$WITH_TESTS" = "1" ]; then
    case "$variant" in
      debug_sim|debug) ninja_target="$ninja_target $test_target" ;;
    esac
  fi

  echo ""
  echo "========================================"
  echo "  Building: $variant"
  echo "========================================"
  cd "$ENGINE_SRC"
  echo "--- gn gen ($variant) ---"
  vpython3 "$GN" $gn_flags
  echo "--- ninja ($variant) ---"
  "$NINJA" -C "$ENGINE_SRC/$out_dir" -j "$CONCURRENT_JOBS" $ninja_target
  echo "--- $variant build complete ---"
}

# --- Build all requested variants ---
for v in "${VARIANTS[@]}"; do
  build_variant "$v"
done

# --- Package artifacts ---
ARTIFACTS_DIR="$REPO_ROOT/artifacts"
mkdir -p "$ARTIFACTS_DIR"

GN_DIRS=(tvos_debug_sim_unopt_arm64 tvos_debug_unopt tvos_profile tvos_release host_debug_unopt host_release)
TARGET_NAMES=(tvos_debug_sim_arm64 tvos_debug_arm64 tvos_profile_arm64 tvos_release_arm64 host_debug_unopt host_release)
TVOS_INCLUDES=(Flutter.framework Flutter.xcframework "clang_arm64/gen_snapshot" "clang_arm64/impellerc" "clang_arm64/shader_lib" "clang_arm64/icudtl.dat" flutter_patched_sdk args.gn LICENSE)
HOST_INCLUDES=(gen_snapshot "gen/frontend_server_aot.dart.snapshot" flutter_patched_sdk icudtl.dat args.gn LICENSE)

echo ""
echo "--- Packaging artifacts → $ARTIFACTS_DIR ---"
PACKAGED=0
for i in "${!GN_DIRS[@]}"; do
  gn_dir="${GN_DIRS[$i]}"
  target="${TARGET_NAMES[$i]}"
  src="$ENGINE_SRC/out/$gn_dir"
  [ -d "$src" ] || continue

  staging=$(mktemp -d)
  mkdir -p "$staging/$target"

  if [[ "$target" == host_* ]]; then
    for item in "${HOST_INCLUDES[@]}"; do
      [ -e "$src/$item" ] && cp -a "$src/$item" "$staging/$target/$item" 2>/dev/null || true
    done
    [ -f "$src/clang_arm64/gen_snapshot" ] && { mkdir -p "$staging/$target/clang_arm64"; cp -a "$src/clang_arm64/gen_snapshot" "$staging/$target/clang_arm64/"; }
  else
    for item in "${TVOS_INCLUDES[@]}"; do
      [ -e "$src/$item" ] && cp -a "$src/$item" "$staging/$target/$item" 2>/dev/null || true
    done
    [ -f "$src/libFlutter.dylib" ] && cp -a "$src/libFlutter.dylib" "$staging/$target/"
  fi

  zip_path="$ARTIFACTS_DIR/${target}.zip"
  rm -f "$zip_path"
  (cd "$staging" && zip -r -q "$zip_path" "$target")
  rm -rf "$staging"

  size=$(du -h "$zip_path" | cut -f1)
  echo "  $target.zip ($size)"
  PACKAGED=$((PACKAGED + 1))
done

echo ""
echo "========================================"
echo "  $PACKAGED artifact(s) → $ARTIFACTS_DIR"
echo "========================================"

# --- Publish ---
if [ "$PUBLISH" = "1" ]; then
  echo ""
  echo "--- Publishing to fluttertv/engine-artifacts ---"
  TAG="v1.0.0-flutter${FLUTTER_VERSION}"
  gh release delete "$TAG" --repo fluttertv/engine-artifacts --yes 2>/dev/null || true
  gh release create "$TAG" \
    --repo fluttertv/engine-artifacts \
    --title "Flutter ${FLUTTER_VERSION} tvOS Engine Artifacts" \
    --notes "tvOS engine artifacts for Flutter ${FLUTTER_VERSION}. Built from flutter/flutter@${FLUTTER_COMMIT}." \
    "$ARTIFACTS_DIR"/tvos_debug_sim_arm64.zip \
    "$ARTIFACTS_DIR"/tvos_debug_arm64.zip \
    "$ARTIFACTS_DIR"/tvos_profile_arm64.zip \
    "$ARTIFACTS_DIR"/tvos_release_arm64.zip \
    "$ARTIFACTS_DIR"/host_debug_unopt.zip \
    "$ARTIFACTS_DIR"/host_release.zip
  echo "  Published: $TAG"
fi
