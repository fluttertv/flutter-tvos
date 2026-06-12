// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_TVOS_FFI_H
#define FLUTTER_TVOS_FFI_H

#include <stdbool.h>
#include <stdint.h>

// FFI symbols are looked up at runtime via `DynamicLibrary.process()`
// (dlsym), so nothing in native code references them. Under CocoaPods the
// plugin is a dynamic framework and its exported symbols survive. Under
// Swift Package Manager the plugin is linked *statically* into Runner, where
// the linker would dead-strip these otherwise-unreferenced functions. `used`
// keeps them through dead-stripping and `visibility("default")` keeps them in
// the dynamic symbol table so dlsym can find them. Harmless under CocoaPods.
#define FLUTTER_TVOS_FFI_EXPORT \
  __attribute__((used)) __attribute__((visibility("default")))

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
