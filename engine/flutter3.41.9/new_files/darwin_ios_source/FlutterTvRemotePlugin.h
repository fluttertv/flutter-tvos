// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_FLUTTERTVREMOTEPLUGIN_H_
#define FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_FLUTTERTVREMOTEPLUGIN_H_

#include <TargetConditionals.h>
#if TARGET_OS_TV

#import <UIKit/UIKit.h>

#import "flutter/shell/platform/darwin/common/framework/Headers/FlutterChannels.h"
#import "flutter/shell/platform/darwin/ios/framework/Headers/FlutterEngine.h"

NS_ASSUME_NONNULL_BEGIN

/// Internal plugin that handles Apple TV remote input (Siri Remote),
/// external game controllers, and lock-screen media commands, then forwards
/// normalized events to Dart through two channels:
///
/// - `flutter/tv_remote` (method channel) — discrete button presses and
///   media commands.
/// - `flutter/tv_remote_touches` (basic message channel) — continuous
///   touchpad gestures with coordinates normalized to [-1.0, 1.0].
///
/// The plugin is owned by `FlutterEngine`, matching how other internal
/// plugins (`FlutterPlatformPlugin`, `FlutterTextInputPlugin`) are wired.
/// Press recognizers and touchpad forwarding are attached to a specific
/// view controller via `attachToViewController:`.
@interface FlutterTvRemotePlugin : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Designated initializer — creates both channels on the engine's binary
/// messenger.
- (instancetype)initWithEngine:(FlutterEngine*)engine NS_DESIGNATED_INITIALIZER;

/// Install press gesture recognizers, subscribe to GameController
/// notifications, and register media-command handlers for the supplied
/// view controller. Idempotent — calling twice with the same VC is a
/// no-op; calling with a new VC cleanly detaches from the previous one.
- (void)attachToViewController:(UIViewController*)viewController;

/// The view controller currently attached to this plugin, or `nil` if
/// detached. Callers such as `FlutterViewController.dealloc` can use
/// this to check ownership before calling `detach` and avoid tearing
/// the plugin off a different VC it has since been migrated to.
@property(nonatomic, weak, readonly, nullable) UIViewController* viewController;

/// Tear down everything set up in `attachToViewController:`.
- (void)detach;

/// Forward a set of touches (from `-touchesBegan:/Moved:/Ended:/Cancelled:`)
/// to the Dart side. Coordinates are taken from `[touch locationInView:view]`
/// and normalized to `[-1.0, 1.0]` using `view.bounds`.
///
/// `phase` is one of `@"started"`, `@"move"`, `@"ended"`, `@"cancelled"`.
- (void)handleTouches:(NSSet<UITouch*>*)touches phase:(NSString*)phase view:(UIView*)view;

/// Send a simulated hardware keyboard event through the engine's standard
/// `flutter/keyevent` channel. `keyName` is a logical name such as
/// `@"arrowUp"`, `@"select"`, `@"menu"`, `@"pageUp"`. Unknown names are
/// silently ignored.
///
/// This is the same path UIKit uses for physical keyboards, so
/// `HardwareKeyboard.instance.logicalKeysPressed` reflects the state and
/// events flow through `Focus` / `Shortcuts` / `Actions` in Dart.
- (void)sendKey:(NSString*)keyName isDown:(BOOL)isDown;

/// Whether Flutter currently wants to intercept the Menu button as a
/// back/pop action. When false, the tvOS system should handle Menu
/// normally (send the app to the home screen/background).
- (void)setFrameworkHandlesBack:(BOOL)frameworkHandlesBack;

@end

NS_ASSUME_NONNULL_END

#endif  // TARGET_OS_TV
#endif  // FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_FLUTTERTVREMOTEPLUGIN_H_
