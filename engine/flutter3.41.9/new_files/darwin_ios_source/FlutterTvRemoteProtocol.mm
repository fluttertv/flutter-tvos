// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <TargetConditionals.h>
#if TARGET_OS_TV

#import "flutter/shell/platform/darwin/ios/framework/Source/FlutterTvRemoteProtocol.h"

NSString* const kFlutterTvRemoteButtonChannel = @"flutter/tv_remote";
NSString* const kFlutterTvRemoteTouchesChannel = @"flutter/tv_remote_touches";

NSString* const kFlutterTvRemoteTouchPhaseStarted = @"started";
NSString* const kFlutterTvRemoteTouchPhaseMove = @"move";
NSString* const kFlutterTvRemoteTouchPhaseEnded = @"ended";
NSString* const kFlutterTvRemoteTouchPhaseCancelled = @"cancelled";
NSString* const kFlutterTvRemoteTouchPhaseLoc = @"loc";
NSString* const kFlutterTvRemoteTouchPhaseClickStart = @"click_s";
NSString* const kFlutterTvRemoteTouchPhaseClickEnd = @"click_e";

NSString* const kFlutterTvRemoteConfigShortSwipeThreshold = @"shortSwipeThreshold";
NSString* const kFlutterTvRemoteConfigFastSwipeThreshold = @"fastSwipeThreshold";
NSString* const kFlutterTvRemoteConfigDpadDeadZone = @"dpadDeadZone";
NSString* const kFlutterTvRemoteConfigContinuousSwipeMoveThreshold =
    @"continuousSwipeMoveThreshold";
NSString* const kFlutterTvRemoteConfigKeyRepeatInitialDelayMs = @"keyRepeatInitialDelayMs";
NSString* const kFlutterTvRemoteConfigKeyRepeatIntervalMs = @"keyRepeatIntervalMs";

NSString* const kFlutterTvRemoteMethodConfigure = @"configure";

#endif  // TARGET_OS_TV
