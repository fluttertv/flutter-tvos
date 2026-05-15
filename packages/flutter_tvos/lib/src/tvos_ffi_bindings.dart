// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// On Web, dart:ffi is unavailable — redirect to the stub implementation.
// On all other platforms, use the real FFI bindings.
export 'tvos_ffi_bindings_web.dart'
    if (dart.library.ffi) 'tvos_ffi_bindings_native.dart';
