// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_FLUTTERTVREMOTEPROTOCOL_H_
#define FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_FLUTTERTVREMOTEPROTOCOL_H_

#include <TargetConditionals.h>
#if TARGET_OS_TV

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Single source of truth for the wire protocol shared with the Dart
// `TvRemoteController`. Every constant here MUST mirror the matching
// field in
// `packages/flutter_tvos/lib/src/rcu/tv_remote_protocol.dart`.
//
// Tests pin both ends:
//   - native: `testProtocolConstants_*` in FlutterTvRemotePluginTest.mm
//   - Dart:   `protocol_drift_test.dart`
// so renaming on one side without updating the other fails in CI.

// ---- Channel names ----

extern NSString* const kFlutterTvRemoteButtonChannel;   // "flutter/tv_remote"
extern NSString* const kFlutterTvRemoteTouchesChannel;  // "flutter/tv_remote_touches"

// ---- Touch phase wire strings ----

extern NSString* const kFlutterTvRemoteTouchPhaseStarted;     // "started"
extern NSString* const kFlutterTvRemoteTouchPhaseMove;        // "move"
extern NSString* const kFlutterTvRemoteTouchPhaseEnded;       // "ended"
extern NSString* const kFlutterTvRemoteTouchPhaseCancelled;   // "cancelled"
extern NSString* const kFlutterTvRemoteTouchPhaseLoc;         // "loc"
extern NSString* const kFlutterTvRemoteTouchPhaseClickStart;  // "click_s"
extern NSString* const kFlutterTvRemoteTouchPhaseClickEnd;    // "click_e"

// ---- Configure dictionary keys ----

extern NSString* const kFlutterTvRemoteConfigShortSwipeThreshold;
extern NSString* const kFlutterTvRemoteConfigFastSwipeThreshold;
extern NSString* const kFlutterTvRemoteConfigDpadDeadZone;
extern NSString* const kFlutterTvRemoteConfigContinuousSwipeMoveThreshold;
extern NSString* const kFlutterTvRemoteConfigKeyRepeatInitialDelayMs;
extern NSString* const kFlutterTvRemoteConfigKeyRepeatIntervalMs;

// ---- Method names ----

extern NSString* const kFlutterTvRemoteMethodConfigure;  // "configure"

NS_ASSUME_NONNULL_END

#endif  // TARGET_OS_TV
#endif  // FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_FLUTTERTVREMOTEPROTOCOL_H_
