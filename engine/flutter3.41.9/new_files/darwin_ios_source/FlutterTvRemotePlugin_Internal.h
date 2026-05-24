// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_FLUTTERTVREMOTEPLUGIN_INTERNAL_H_
#define FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_FLUTTERTVREMOTEPLUGIN_INTERNAL_H_

#include <TargetConditionals.h>
#if TARGET_OS_TV

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "flutter/shell/platform/darwin/ios/framework/Source/FlutterTvRemotePlugin.h"

NS_ASSUME_NONNULL_BEGIN

@class FlutterTvKeyRepeater;

/// Test-only surface for `FlutterTvRemotePlugin`. Everything declared
/// here is **for XCTests only** — production code must not import this
/// header. The selectors and properties expose internal decision points
/// (D-pad bias, continuous-swipe direction, configure parsing, media
/// command dispatch) so unit tests can drive them directly without
/// constructing real `UIPress`, `GCMicroGamepad`, or
/// `MPRemoteCommandCenter` objects.
@interface FlutterTvRemotePlugin (Testing)

#pragma mark - Press handling
- (void)handlePress:(UILongPressGestureRecognizer*)recognizer;

#pragma mark - Configure protocol
/// Apply a configure-args dictionary directly. Used by tests to bypass
/// the method-channel hop. Production code reaches this via the channel
/// handler installed in `initWithEngine:`.
- (void)applyConfigure:(id)arguments;

#pragma mark - D-pad click bias decision
/// Given the latest D-pad x position and the configured dead-zone,
/// return the logical key name that a touchpad click should produce
/// (`@"select"` when centered, `@"arrowLeft"` / `@"arrowRight"` when
/// off-center). Pure function — no side effects, no `sendKey:`. Tests
/// exercise the decision in isolation; `handleClickDown` calls it.
- (NSString*)debugClickKeyNameForDpadX:(double)x deadZone:(double)deadZone;

#pragma mark - Continuous swipe direction
/// Map a touch-move delta to its dominant cardinal direction
/// (`@"arrowUp/Down/Left/Right"`), or `nil` when the delta is below the
/// micro-jitter threshold. Pure function. Public for tests.
+ (nullable NSString*)debugDirectionFromDeltaX:(double)dx y:(double)dy;

#pragma mark - GameController D-pad
/// Process one D-pad value-changed event from `GCMicroGamepad` —
/// caches `lastDpadX` and forwards a `loc` event on the touches
/// channel. Tests call this directly instead of synthesising a real
/// gamepad value-changed callback.
- (void)debugHandleDpadX:(float)x y:(float)y;

#pragma mark - Media command dispatch
/// Seek-style media command — emits a single keydown/keyup based on
/// the seek phase (`isDown=YES` on Begin, `NO` on End).
- (void)debugDispatchMediaSeekKey:(NSString*)keyName isDown:(BOOL)isDown;
/// Discrete media command (Play / Pause / Stop / TogglePlayPause) —
/// emits both keydown and keyup back-to-back so HardwareKeyboard state
/// does not get stuck.
- (void)debugDispatchMediaDiscreteKey:(NSString*)keyName;
/// Playback-rate command — positive rate ⇒ fast-forward, negative ⇒
/// rewind, zero ⇒ no-op.
- (void)debugDispatchMediaPlaybackRate:(float)rate;

#pragma mark - Touches forwarding
/// Forward a synthesized touch event onto the touches channel. Tests
/// stub `touchesChannel` (via OCMock partial mock) and assert what
/// flows through.
- (void)debugSendTouchEventOfType:(NSString*)type x:(double)x y:(double)y;

/// Live touches channel — exposed so tests can install OCMock partial
/// mocks and assert the wire format of outgoing messages.
@property(nonatomic, strong, readonly) FlutterBasicMessageChannel* touchesChannel;

#pragma mark - GameController notification entry-point
/// `GCControllerDidConnectNotification` handler — exposed for tests
/// that simulate hot-plug events without a real physical controller.
- (void)controllerDidConnect:(NSNotification*)notification;

#pragma mark - Media-command registration
/// Install all `MPRemoteCommandCenter` handlers. Idempotent (the second
/// call is a no-op so we don't accumulate duplicate target-token
/// pairs across attach cycles). Production code calls this from
/// `attachToViewController:`; tests call it directly to exercise the
/// idempotency guarantee.
- (void)registerMediaCommandsOnce;
/// Remove every handler installed by `registerMediaCommandsOnce`.
/// Production code calls this from `detach`; tests call it for symmetry
/// after exercising `registerMediaCommandsOnce` in isolation.
- (void)unregisterMediaCommands;

#pragma mark - Internal state mirrors (read-only)
//
// Properties below mirror private ivars. They allow tests to
// black-box-verify state transitions without poking at private API.
@property(nonatomic, copy, readonly, nullable) NSString* debugContinuousSwipeDirection;
@property(nonatomic, assign, readonly) NSInteger debugContinuousSwipeMoveCount;
@property(nonatomic, assign, readonly) double debugLastDpadX;
@property(nonatomic, assign, readonly) double debugLastTouchX;
@property(nonatomic, assign, readonly) double debugLastTouchY;
@property(nonatomic, copy, readonly, nullable) NSString* debugCurrentClickKey;
@property(nonatomic, assign, readonly) double debugDpadDeadZone;
@property(nonatomic, assign, readonly) double debugShortSwipeThreshold;
@property(nonatomic, assign, readonly) double debugFastSwipeThreshold;
@property(nonatomic, assign, readonly) NSInteger debugContinuousSwipeMoveThreshold;
@property(nonatomic, assign, readonly) BOOL debugSelectConsumedByKeyboard;
@property(nonatomic, assign, readonly) BOOL debugMediaCommandsRegistered;
@property(nonatomic, strong, readonly)
    NSArray<NSDictionary<NSString*, id>*>* debugMediaCommandBindings;
@property(nonatomic, strong, readonly) NSArray<UIGestureRecognizer*>* debugPressRecognizers;
@property(nonatomic, strong, readonly) FlutterTvKeyRepeater* debugKeyRepeater;

@end

/// Auto-repeat timer bookkeeping extracted from `FlutterTvRemotePlugin` so
/// it can be unit-tested in isolation. Lives in the plugin translation
/// unit; exposed here only for tests.
@interface FlutterTvKeyRepeater : NSObject

/// `sendBlock` is called on the main thread whenever a synthetic keydown
/// or keyup should be emitted. Tests may provide their own block to
/// record events; the plugin passes a block that calls `sendKey:isDown:`.
- (instancetype)initWithSendBlock:(void (^)(NSString* keyName, BOOL isDown))sendBlock
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// The key currently being repeated, or `nil` when idle.
@property(nonatomic, copy, readonly, nullable) NSString* activeKey;

/// Delay from the initial keydown to the first auto-repeated keydown.
/// Defaults to 0.4 s; apps can override via `configure` method channel.
@property(nonatomic, assign) NSTimeInterval initialDelay;

/// Interval between auto-repeated keydown events while the key is held.
/// Defaults to 0.08 s.
@property(nonatomic, assign) NSTimeInterval repeatInterval;

/// Emit keydown for [key] and arm the repeat timer. If another key is
/// already active, its keyup is emitted first. Starting with the same
/// active key is a no-op. An empty key name is ignored.
- (void)startRepeat:(NSString*)key;

/// Emit keyup for the active key (if any) and cancel all timers. Safe to
/// call when idle.
- (void)stopRepeat;

@end

NS_ASSUME_NONNULL_END

#endif  // TARGET_OS_TV
#endif  // FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_FLUTTERTVREMOTEPLUGIN_INTERNAL_H_
