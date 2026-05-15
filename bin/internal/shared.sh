#!/usr/bin/env bash
# Copyright 2025 The Flutter-tvOS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# ---------------------------------- NOTE ---------------------------------- #
#
# Please keep the logic in this file consistent with the logic in
# flutter-tizen's and flutter-elinux's shared.sh to ensure consistency.
#
# -------------------------------------------------------------------------- #

set -e

# Needed because if it is set, cd may print the path it changed to.
unset CDPATH

FLUTTER_REPO="https://github.com/flutter/flutter.git"

if [[ -z "$BIN_DIR" ]]; then
  echo "BIN_DIR is not set."
  exit 1
fi
ROOT_DIR="$(cd "${BIN_DIR}/.." ; pwd -P)"
FLUTTER_DIR="$ROOT_DIR/flutter"
SNAPSHOT_PATH="$ROOT_DIR/bin/cache/flutter-tvos.snapshot"

FLUTTER_EXE="$FLUTTER_DIR/bin/flutter"
DART_EXE="$FLUTTER_DIR/bin/cache/dart-sdk/bin/dart"

function tool_revision() {
  if [[ -d "$ROOT_DIR/.git" ]] && git --git-dir="$ROOT_DIR/.git" rev-parse HEAD >/dev/null 2>&1; then
    git --git-dir="$ROOT_DIR/.git" rev-parse HEAD
    return
  fi

  (
    cd "$ROOT_DIR" || exit 1
    {
      find bin lib -type f -not -path 'bin/cache/*' 2>/dev/null
      printf '%s\n' pubspec.yaml pubspec.lock
    } | while IFS= read -r file; do
      if [[ -f "$file" ]]; then
        shasum "$file"
      fi
    done | shasum | awk '{print $1}'
  )
}

function update_flutter() {
  if [[ -e "$FLUTTER_DIR" && ! -d "$FLUTTER_DIR/.git" ]]; then
    echo "$FLUTTER_DIR is not a git directory. Remove it and try again."
    exit 1
  fi

  local version="$(head -n 1 "$ROOT_DIR/bin/internal/flutter.version")"
  local tag="$(sed -n 2p "$ROOT_DIR/bin/internal/flutter.version")"

  # Clone flutter repo if not installed.
  #
  # `--quiet` suppresses the "Cloning into ..." preamble and the in-place
  # "Updating files: 36% (...)" progress line. Without a tty (e.g. piping
  # through `tee`) those CR-driven progress updates collapse into one
  # extremely long unreadable line, so quieting them is a UX win.
  #
  # Print a single line BEFORE the clone so the user knows the command is
  # working — a fresh clone takes 10–30s depending on connection, and any
  # output before this point would have been the user's first feedback
  # (which used to be "Cloning into ..." plus a CR-mangled progress bar,
  # silenced by `--quiet`). This is now the FIRST line the user sees on
  # any fresh install.
  if [[ ! -d "$FLUTTER_DIR" ]]; then
    echo "Setting up flutter-tvos (first run)..."
    echo "Downloading Flutter SDK source..."
    git clone --depth=1 --quiet "$FLUTTER_REPO" "$FLUTTER_DIR" -b "$tag"
  fi

  # GIT_DIR and GIT_WORK_TREE are used in the git command.
  export GIT_DIR="$FLUTTER_DIR/.git"
  export GIT_WORK_TREE="$FLUTTER_DIR"

  # Update flutter repo if needed.
  if [[ "$version" != "$(git rev-parse HEAD)" ]]; then
    echo "Updating Flutter SDK to pinned revision..."
    git reset --hard --quiet
    git clean -xdf --quiet
    # `--tags` is required so `git describe --tags` can resolve the
    # Flutter version (otherwise `flutter doctor` reports
    # `0.0.0-unknown` and prompts the user to reinstall). Pair it with
    # `--quiet` so we don't print the ~1100-line `* [new tag] X.Y.Z`
    # listing the bare command emits on a fresh install.
    git fetch --depth=1 --quiet --tags "$FLUTTER_REPO" "$version"
    git checkout --quiet FETCH_HEAD

    # Invalidate the cache.
    rm -fr "$ROOT_DIR/bin/cache"
  fi

  if [[ "$version" != "$(git rev-parse HEAD)" ]]; then
    echo "Something went wrong when upgrading the Flutter SDK." \
         "Remove directory $FLUTTER_DIR and try again."
    exit 1
  fi

  unset GIT_DIR
  unset GIT_WORK_TREE

  # NOTE: Flutter SDK is intentionally NOT patched by flutter-tvos. All
  # tvOS-specific behavior lives in (a) the engine artifact (Dart VM +
  # Impeller + iOS embedder patches, shipped as pre-built zips) and
  # (b) this CLI. The Flutter SDK checkout above is bit-for-bit identical
  # to the pinned commit in bin/internal/flutter.version.

  # Invalidate the flutter cache.
  local stamp_path="$FLUTTER_DIR/bin/cache/flutter_tools.stamp"
  if [[ ! -f "$stamp_path" ]]; then
    bootstrap_flutter_tool
  else
    local v="$(cat "$stamp_path")"
    v="${v%%:*}"
    if [[ "$version" != "$v" ]]; then
      bootstrap_flutter_tool
    fi
  fi
}

# Triggers Flutter to download the bundled Dart SDK and compile its own
# tool snapshot, capturing the noisy underlying output so the user sees a
# single line of progress instead of:
#   - curl progress bytes mangled into one line by `tee`-style log capture
#     ("Downloading Darwin arm64 Dart SDK from Flutter engine ...")
#   - the "Failed to decode advisories for archive from https://pub.dev"
#     stack-trace pair (a Dart SDK 3.11 / pub.dev quirk that pub recovers
#     from internally — every `pub upgrade` since the bug landed dumps
#     ~40 lines of asynchronous-gap traces and then prints `Got
#     dependencies.` regardless).
# On failure we echo back everything that was captured so genuine errors
# remain debuggable.
function bootstrap_flutter_tool() {
  local log_file
  log_file="$(mktemp -t flutter-tvos-bootstrap.XXXXXX)"
  echo "Bootstrapping Flutter SDK (one-time setup, this may take a few minutes)..."
  if ! "$FLUTTER_EXE" --version >"$log_file" 2>&1; then
    echo "Flutter SDK bootstrap failed. Captured output:" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi
  rm -f "$log_file"
}

function setup_proxy_root() {
  local proxy_root="$ROOT_DIR/proxy_root"
  mkdir -p "$proxy_root/bin"

  # proxy_root/packages → flutter/packages
  local packages_link="$proxy_root/packages"
  rm -f "$packages_link"
  ln -sf "$FLUTTER_DIR/packages" "$packages_link"

  # proxy_root/bin/dart → flutter dart binary
  local dart_link="$proxy_root/bin/dart"
  rm -f "$dart_link"
  ln -sf "$FLUTTER_DIR/bin/cache/dart-sdk/bin/dart" "$dart_link"

  # proxy_root/bin/flutter → shell script calling flutter-tvos
  local flutter_proxy="$proxy_root/bin/flutter"
  cat > "$flutter_proxy" << ENDSCRIPT
#!/bin/bash
exec "$ROOT_DIR/bin/flutter-tvos" "\$@"
ENDSCRIPT
  chmod +x "$flutter_proxy"
}

function update_flutter_tvos() {
  mkdir -p "$ROOT_DIR/bin/cache"

  local revision="$(tool_revision)"
  local stamp_path="$ROOT_DIR/bin/cache/flutter-tvos.stamp"
  local package_config_path="$ROOT_DIR/.dart_tool/package_config.json"
  local needs_pub_get="false"

  # Detect whether `flutter pub get` needs to run. We previously compared
  # pubspec.yaml against pubspec.lock — but `pub get` only updates the
  # lockfile when dependency versions actually change. Editing pubspec.yaml
  # in any other way (description, author, comments) would leave
  # pubspec.yaml newer than pubspec.lock forever, retriggering pub-get and
  # the snapshot recompile on every invocation. Compare against the stamp
  # file instead — it is written each time we finish compiling, so it is a
  # reliable "we have processed this pubspec.yaml" marker.
  if [[ ! -f "$ROOT_DIR/pubspec.lock" || ! -f "$package_config_path"
        || "$ROOT_DIR/pubspec.yaml" -nt "$stamp_path" ]]; then
    needs_pub_get="true"
  fi

  if [[ ! -f "$SNAPSHOT_PATH" || ! -s "$stamp_path" || "$revision" != "$(cat "$stamp_path")"
        || "$needs_pub_get" == "true" ]]; then
    if [[ "$needs_pub_get" == "true" ]]; then
      echo "Running pub get..."
      (cd "$ROOT_DIR" && "$FLUTTER_EXE" pub get --offline) || \
      (cd "$ROOT_DIR" && "$FLUTTER_EXE" pub get) || {
        >&2 echo "Error: Unable to resolve flutter-tvos dependencies."
        exit 1
      }
    fi

    echo "Compiling flutter-tvos..."
    "$DART_EXE" --disable-dart-dev --no-enable-mirrors \
                --snapshot="$SNAPSHOT_PATH" --packages="$ROOT_DIR/.dart_tool/package_config.json" \
                "$ROOT_DIR/bin/flutter_tvos.dart"

    echo "$revision" > "$stamp_path"
  fi
}

function exec_snapshot() {
  "$DART_EXE" --disable-dart-dev --packages="$ROOT_DIR/.dart_tool/package_config.json" "$SNAPSHOT_PATH" "$@"
}
