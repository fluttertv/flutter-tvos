// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_TVOS_FFI_H
#define FLUTTER_TVOS_FFI_H

#include <stdbool.h>
#include <stdint.h>

// Marks a symbol as exported for dart:ffi lookup. `visibility("default")` keeps
// it in the binary's (dynamic) symbol table so `DynamicLibrary.process()` can
// find it; `used` stops the linker dead-stripping it once the archive member is
// pulled into a static link. The Swift Package Manager integration pulls this
// archive member via a forced reference the generated GeneratedPluginRegistrant.m
// emits (an FFI plugin has no compile-time caller), so without `used` the symbol
// could still be stripped after the member is selected.
#define FLUTTER_TVOS_FFI_EXPORT __attribute__((visibility("default"), used))

/// Returns true if running on tvOS (compiled with TARGET_OS_TV).
FLUTTER_TVOS_FFI_EXPORT bool flutter_tvos_is_tvos(void);

/// Returns the OS version string (e.g., "18.4"). Caller must NOT free.
FLUTTER_TVOS_FFI_EXPORT const char* flutter_tvos_system_version(void);

/// Returns the device model (e.g., "Apple TV"). Caller must NOT free.
FLUTTER_TVOS_FFI_EXPORT const char* flutter_tvos_device_model(void);

/// Returns the machine identifier (e.g., "AppleTV14,1"). Caller must NOT free.
FLUTTER_TVOS_FFI_EXPORT const char* flutter_tvos_machine_id(void);

/// Returns true if running in the simulator.
FLUTTER_TVOS_FFI_EXPORT bool flutter_tvos_is_simulator(void);

/// Returns true if the display supports 4K (3840+ pixels wide).
FLUTTER_TVOS_FFI_EXPORT bool flutter_tvos_supports_4k(void);

/// Returns true if HDR is supported.
FLUTTER_TVOS_FFI_EXPORT bool flutter_tvos_supports_hdr(void);

/// Returns true if multi-user is supported (tvOS 14+).
FLUTTER_TVOS_FFI_EXPORT bool flutter_tvos_supports_multi_user(void);

/// Returns the native display width in pixels.
FLUTTER_TVOS_FFI_EXPORT int32_t flutter_tvos_display_width(void);

/// Returns the native display height in pixels.
FLUTTER_TVOS_FFI_EXPORT int32_t flutter_tvos_display_height(void);

#endif /* FLUTTER_TVOS_FFI_H */
