// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "flutter/shell/platform/darwin/ios/framework/Source/FlutterTvRemotePlugin.h"

#if TARGET_OS_TV

#import <GameController/GameController.h>
#import <MediaPlayer/MediaPlayer.h>

#import "flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine_Internal.h"
#import "flutter/shell/platform/darwin/ios/framework/Source/FlutterTextInputPlugin.h"
#import "flutter/shell/platform/darwin/ios/framework/Source/FlutterTvRemotePlugin_Internal.h"
#import "flutter/shell/platform/darwin/ios/framework/Source/FlutterTvRemoteProtocol.h"

NS_ASSUME_NONNULL_BEGIN

// Channel names live in `FlutterTvRemoteProtocol.h` (single source of
// truth, shared with the Dart side). Local aliases retained as
// abbreviations — not as a duplicate definition.
#define kButtonChannelName kFlutterTvRemoteButtonChannel
#define kTouchesChannelName kFlutterTvRemoteTouchesChannel

/// Default configuration values used until Dart overrides them via the
/// `configure` method call. Apps that never call `configure` get these.
static const NSTimeInterval kDefaultKeyRepeatInitialDelay = 0.4;
static const NSTimeInterval kDefaultKeyRepeatInterval = 0.08;
static const NSInteger kDefaultContinuousSwipeMoveThreshold = 3;
static const double kDefaultDpadDeadZone = 0.5;
static const double kDefaultShortSwipeThreshold = 0.3;
static const double kDefaultFastSwipeThreshold = 0.5;
static const NSInteger kTouchesChannelStartupBufferSize = 32;

/// Map from `UIPressType` to the logical key name used by both the method
/// channel and the internal key repeater.
static NSString* _LogicalKeyNameForPressType(UIPressType pressType) {
  switch (pressType) {
    case UIPressTypeUpArrow:
      return @"arrowUp";
    case UIPressTypeDownArrow:
      return @"arrowDown";
    case UIPressTypeLeftArrow:
      return @"arrowLeft";
    case UIPressTypeRightArrow:
      return @"arrowRight";
    case UIPressTypeSelect:
      return @"select";
    case UIPressTypePlayPause:
      return @"playPause";
    case UIPressTypeMenu:
      return @"menu";
    default:
      break;
  }
  if (@available(tvOS 14.3, *)) {
    if (pressType == UIPressTypePageUp)
      return @"pageUp";
    if (pressType == UIPressTypePageDown)
      return @"pageDown";
  }
  return @"";
}

/// Encoding returned by `_KeyEncodingForLogicalName`. `keymap` is the
/// value sent in the `flutter/keyevent` channel payload ("macos" or
/// "android") and `keyCode` is looked up from the matching Flutter
/// framework table (see `kMacOsToLogicalKey` / `kAndroidToLogicalKey`
/// in `flutter/packages/flutter/lib/src/services/keyboard_maps.g.dart`).
typedef struct {
  NSString* keymap;
  int keyCode;
} FlutterTvKeyEncoding;

/// Map a logical key name to the right Flutter-framework keymap entry.
///
/// Navigation keys (arrows, enter, escape) use the macOS keymap — Apple's
/// `kVK_*` constants match Flutter's `kMacOsToLogicalKey` table.
///
/// Media keys use the Android keymap: Flutter's macOS map has no entries
/// for `mediaPlay` / `mediaPause` / `mediaPlayPause` / `mediaFastForward`
/// / `mediaRewind` / `mediaStop`, but `kAndroidToLogicalKey` does.
///
/// Select is deliberately mapped to `kVK_Return` → `LogicalKeyboardKey.enter`,
/// not to `LogicalKeyboardKey.select`. Flutter's default `ActivateIntent`
/// shortcut binds `enter` (not `select`), so standard buttons / list items
/// activate on Select press without every tvOS app having to register a
/// custom `SingleActivator(LogicalKeyboardKey.select)`. This is the same
/// choice flutter-tizen makes for its OK button. Directional-click bias
/// still produces `arrowLeft` / `arrowRight` when the touchpad is
/// off-center, also via macOS keymap.
///
/// Returns an encoding with `keymap == nil` for unknown names so
/// `sendKey:` becomes a no-op rather than emitting a wrong key.
static FlutterTvKeyEncoding _KeyEncodingForLogicalName(NSString* name) {
  // --- macOS keymap — navigation ---
  if ([name isEqualToString:@"arrowUp"])
    return (FlutterTvKeyEncoding){@"macos", 0x7E};
  if ([name isEqualToString:@"arrowDown"])
    return (FlutterTvKeyEncoding){@"macos", 0x7D};
  if ([name isEqualToString:@"arrowLeft"])
    return (FlutterTvKeyEncoding){@"macos", 0x7B};
  if ([name isEqualToString:@"arrowRight"])
    return (FlutterTvKeyEncoding){@"macos", 0x7C};
  if ([name isEqualToString:@"enter"])
    return (FlutterTvKeyEncoding){@"macos", 0x24};  // kVK_Return
  // Select resolves to `enter` for cross-platform consistency with
  // flutter-tizen / Flutter Android default shortcut bindings.
  if ([name isEqualToString:@"select"])
    return (FlutterTvKeyEncoding){@"macos", 0x24};
  if ([name isEqualToString:@"escape"] || [name isEqualToString:@"menu"])
    return (FlutterTvKeyEncoding){@"macos", 0x35};  // kVK_Escape
  if ([name isEqualToString:@"pageUp"])
    return (FlutterTvKeyEncoding){@"macos", 0x74};
  if ([name isEqualToString:@"pageDown"])
    return (FlutterTvKeyEncoding){@"macos", 0x79};

  // --- Android keymap — media keys (Flutter's macOS map has no entries) ---
  if ([name isEqualToString:@"mediaPlayPause"])
    return (FlutterTvKeyEncoding){@"android", 85};
  if ([name isEqualToString:@"mediaStop"])
    return (FlutterTvKeyEncoding){@"android", 86};
  if ([name isEqualToString:@"mediaRewind"])
    return (FlutterTvKeyEncoding){@"android", 89};
  if ([name isEqualToString:@"mediaFastForward"])
    return (FlutterTvKeyEncoding){@"android", 90};
  if ([name isEqualToString:@"mediaPlay"])
    return (FlutterTvKeyEncoding){@"android", 126};
  if ([name isEqualToString:@"mediaPause"])
    return (FlutterTvKeyEncoding){@"android", 127};

  return (FlutterTvKeyEncoding){nil, -1};
}

#pragma mark - FlutterTvKeyRepeater

// Public declaration lives in `FlutterTvRemotePlugin_Internal.h` so unit
// tests can instantiate the repeater directly with a custom send block.
@interface FlutterTvKeyRepeater ()
@property(nonatomic, copy) void (^sendBlock)(NSString* keyName, BOOL isDown);
@property(nonatomic, copy, readwrite, nullable) NSString* activeKey;
@property(nonatomic, strong, nullable) NSTimer* initialTimer;
@property(nonatomic, strong, nullable) NSTimer* repeatTimer;
@end

@implementation FlutterTvKeyRepeater

- (instancetype)initWithSendBlock:(void (^)(NSString* _Nonnull, BOOL))sendBlock {
  self = [super init];
  if (self) {
    _sendBlock = [sendBlock copy];
    _initialDelay = kDefaultKeyRepeatInitialDelay;
    _repeatInterval = kDefaultKeyRepeatInterval;
  }
  return self;
}

- (void)dealloc {
  [_initialTimer invalidate];
  [_repeatTimer invalidate];
}

- (void)startRepeat:(NSString*)key {
  if (key.length == 0)
    return;
  if ([self.activeKey isEqualToString:key])
    return;

  if (self.activeKey != nil) {
    [self stopRepeat];
  }

  self.activeKey = key;
  self.sendBlock(key, YES);

  __weak FlutterTvKeyRepeater* weakSelf = self;
  self.initialTimer = [NSTimer scheduledTimerWithTimeInterval:self.initialDelay
                                                      repeats:NO
                                                        block:^(NSTimer* _Nonnull timer) {
                                                          FlutterTvKeyRepeater* strongSelf =
                                                              weakSelf;
                                                          if (strongSelf == nil)
                                                            return;
                                                          strongSelf.initialTimer = nil;
                                                          [strongSelf armPeriodicTimer];
                                                        }];
}

- (void)armPeriodicTimer {
  NSString* keyAtArm = self.activeKey;
  if (keyAtArm == nil)
    return;
  __weak FlutterTvKeyRepeater* weakSelf = self;
  self.repeatTimer = [NSTimer scheduledTimerWithTimeInterval:self.repeatInterval
                                                     repeats:YES
                                                       block:^(NSTimer* _Nonnull timer) {
                                                         FlutterTvKeyRepeater* strongSelf =
                                                             weakSelf;
                                                         if (strongSelf == nil) {
                                                           [timer invalidate];
                                                           return;
                                                         }
                                                         NSString* activeKey = strongSelf.activeKey;
                                                         if (activeKey == nil) {
                                                           [timer invalidate];
                                                           return;
                                                         }
                                                         strongSelf.sendBlock(activeKey, YES);
                                                       }];
}

- (void)stopRepeat {
  [self.initialTimer invalidate];
  self.initialTimer = nil;
  [self.repeatTimer invalidate];
  self.repeatTimer = nil;

  NSString* key = self.activeKey;
  self.activeKey = nil;
  if (key != nil) {
    self.sendBlock(key, NO);
  }
}

@end

#pragma mark - FlutterTvRemotePlugin

@interface FlutterTvRemotePlugin () <UIGestureRecognizerDelegate>

@property(nonatomic, weak) FlutterEngine* engine;
@property(nonatomic, weak, readwrite) UIViewController* viewController;

@property(nonatomic, strong) FlutterMethodChannel* buttonChannel;
@property(nonatomic, strong) FlutterBasicMessageChannel* touchesChannel;

@property(nonatomic, strong) NSMutableArray<UIGestureRecognizer*>* pressRecognizers;
@property(nonatomic, weak, nullable) UILongPressGestureRecognizer* menuPressRecognizer;
@property(nonatomic, strong) NSHashTable<GCController*>* configuredControllers;
@property(nonatomic, assign) BOOL mediaCommandsRegistered;

/// `(MPRemoteCommand, handler-token)` pairs recorded at registration time
/// so `detach` can remove them from the `MPRemoteCommandCenter` shared
/// singleton. Without this, handler blocks accumulate across engine
/// restarts and each media button fires multiple times.
@property(nonatomic, strong) NSMutableArray<NSDictionary<NSString*, id>*>* mediaCommandBindings;

@property(nonatomic, strong) FlutterTvKeyRepeater* keyRepeater;

/// Last touchpad coordinates recorded on a `move` event, used to compute
/// consecutive direction streaks for continuous-swipe repeat detection.
@property(nonatomic, assign) double lastTouchX;
@property(nonatomic, assign) double lastTouchY;

/// Accumulator for continuous-swipe detection. Counts consecutive `move`
/// events whose delta points in the same cardinal direction as the prior
/// move. Reset on direction change, touch-end, or touch-cancel.
@property(nonatomic, copy, nullable) NSString* continuousSwipeDirection;
@property(nonatomic, assign) NSInteger continuousSwipeMoveCount;

/// YES when the most recent Select `Began` was consumed by
/// `tvosActivateKeyboard` (so the matching `Ended` should not emit
/// `click_e`). Cleared on Began that did not consume, and on Ended/Cancelled.
@property(nonatomic, assign) BOOL selectConsumedByKeyboard;

/// Last D-pad x from `GCMicroGamepad` `valueChangedHandler`, normalized
/// to `[-1, 1]`. Used to bias a touchpad click toward an arrow key when
/// the user is holding the touchpad off-center.
@property(nonatomic, assign) double lastDpadX;

/// Config — live-editable by the Dart side via the `configure` method.
/// Applied on the next input event.
@property(nonatomic, assign) double dpadDeadZone;
@property(nonatomic, assign) double shortSwipeThreshold;
@property(nonatomic, assign) double fastSwipeThreshold;
@property(nonatomic, assign) NSInteger continuousSwipeMoveThreshold;

/// Key logical name currently in "click held" state, or nil if no
/// click is in progress. Used to pair `click_s` / `click_e` and to
/// protect against double-`click_s` without a matching `click_e`.
@property(nonatomic, copy, nullable) NSString* currentClickKey;

/// Becomes YES only after Dart has initialized the controller and sent
/// the `configure` handshake. Until then, raw touch messages are held
/// back so startup does not spam channel-buffer overflow warnings.
@property(nonatomic, assign) BOOL frameworkReadyForTouches;
@property(nonatomic, assign) BOOL frameworkHandlesBack;

@end

@implementation FlutterTvRemotePlugin

- (instancetype)initWithEngine:(FlutterEngine*)engine {
  NSAssert(engine, @"engine must be non-nil");
  self = [super init];
  if (self) {
    _engine = engine;
    _pressRecognizers = [NSMutableArray array];
    _configuredControllers = [NSHashTable weakObjectsHashTable];
    _mediaCommandBindings = [NSMutableArray array];
    _mediaCommandsRegistered = NO;
    _continuousSwipeDirection = nil;
    _continuousSwipeMoveCount = 0;
    _dpadDeadZone = kDefaultDpadDeadZone;
    _shortSwipeThreshold = kDefaultShortSwipeThreshold;
    _fastSwipeThreshold = kDefaultFastSwipeThreshold;
    _continuousSwipeMoveThreshold = kDefaultContinuousSwipeMoveThreshold;
    _lastDpadX = 0;
    _currentClickKey = nil;
    _frameworkReadyForTouches = NO;
    _frameworkHandlesBack = NO;

    _buttonChannel =
        [FlutterMethodChannel methodChannelWithName:kButtonChannelName
                                    binaryMessenger:engine.binaryMessenger
                                              codec:[FlutterJSONMethodCodec sharedInstance]];
    _touchesChannel = [FlutterBasicMessageChannel
        messageChannelWithName:kTouchesChannelName
               binaryMessenger:engine.binaryMessenger
                         codec:[FlutterJSONMessageCodec sharedInstance]];

    // The touches stream can start producing events before Dart has
    // attached its listener during startup. Treat that as expected for
    // this channel: preserve a short burst of early events and suppress
    // overflow warnings if the framework has not subscribed yet.
    [_touchesChannel resizeChannelBuffer:kTouchesChannelStartupBufferSize];
    [_touchesChannel setWarnsOnOverflow:NO];

    __weak FlutterTvRemotePlugin* weakSelf = self;
    _keyRepeater =
        [[FlutterTvKeyRepeater alloc] initWithSendBlock:^(NSString* _Nonnull keyName, BOOL isDown) {
          [weakSelf sendKey:keyName isDown:isDown];
        }];

    // Listen for `configure` calls from the Dart side — `TvRemoteConfig`
    // mutations are shipped through this method channel.
    [_buttonChannel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
      FlutterTvRemotePlugin* strongSelf = weakSelf;
      if (strongSelf == nil) {
        result(nil);
        return;
      }
      if ([call.method isEqualToString:kFlutterTvRemoteMethodConfigure]) {
        [strongSelf applyConfigure:call.arguments];
        result(nil);
        return;
      }
      result(FlutterMethodNotImplemented);
    }];
  }
  return self;
}

/// Apply a subset of `TvRemoteConfig` fields sent from Dart. Unknown keys
/// are ignored so future Dart versions can ship new fields without
/// requiring a matching engine rebuild.
- (void)applyConfigure:(id)arguments {
  // Mark the framework as ready for touch forwarding. This is the
  // handshake point — whether reached via the method channel or called
  // directly (e.g. from tests).
  self.frameworkReadyForTouches = YES;

  if (![arguments isKindOfClass:[NSDictionary class]]) {
    return;
  }
  NSDictionary* args = arguments;
  NSNumber* shortSwipe = args[kFlutterTvRemoteConfigShortSwipeThreshold];
  if ([shortSwipe isKindOfClass:[NSNumber class]]) {
    self.shortSwipeThreshold = shortSwipe.doubleValue;
  }
  NSNumber* fastSwipe = args[kFlutterTvRemoteConfigFastSwipeThreshold];
  if ([fastSwipe isKindOfClass:[NSNumber class]]) {
    self.fastSwipeThreshold = fastSwipe.doubleValue;
  }
  NSNumber* dpadDz = args[kFlutterTvRemoteConfigDpadDeadZone];
  if ([dpadDz isKindOfClass:[NSNumber class]]) {
    self.dpadDeadZone = dpadDz.doubleValue;
  }
  NSNumber* moveThreshold = args[kFlutterTvRemoteConfigContinuousSwipeMoveThreshold];
  if ([moveThreshold isKindOfClass:[NSNumber class]]) {
    self.continuousSwipeMoveThreshold = moveThreshold.integerValue;
  }
  NSNumber* initialDelayMs = args[kFlutterTvRemoteConfigKeyRepeatInitialDelayMs];
  if ([initialDelayMs isKindOfClass:[NSNumber class]]) {
    self.keyRepeater.initialDelay = initialDelayMs.doubleValue / 1000.0;
  }
  NSNumber* intervalMs = args[kFlutterTvRemoteConfigKeyRepeatIntervalMs];
  if ([intervalMs isKindOfClass:[NSNumber class]]) {
    self.keyRepeater.repeatInterval = intervalMs.doubleValue / 1000.0;
  }
}

- (void)dealloc {
  [_keyRepeater stopRepeat];
  [self detach];
}

#pragma mark - Key simulation

- (void)sendKey:(NSString*)keyName isDown:(BOOL)isDown {
  FlutterTvKeyEncoding encoding = _KeyEncodingForLogicalName(keyName);
  if (encoding.keymap == nil) {
    return;
  }
  FlutterEngine* engine = self.engine;
  if (engine == nil) {
    return;
  }
  NSMutableDictionary<NSString*, id>* message = [@{
    @"keymap" : encoding.keymap,
    @"type" : isDown ? @"keydown" : @"keyup",
    @"keyCode" : @(encoding.keyCode),
    @"modifiers" : @(0),
  } mutableCopy];
  if ([encoding.keymap isEqualToString:@"macos"]) {
    message[@"characters"] = @"";
    message[@"charactersIgnoringModifiers"] = @"";
  } else {
    // Android keymap fields expected by `RawKeyEventDataAndroid`. `source`
    // is 0x401 (SOURCE_GAMEPAD | SOURCE_CLASS_BUTTON) to match what a
    // physical Siri Remote would report on Android — any app that filters
    // by `event.data.source` for gamepad input will see our synthesized
    // Select events. `scanCode: 0` produces a synthetic `PhysicalKeyboardKey`
    // — logical-key shortcuts work, physical-key shortcuts for Select do
    // not. Acceptable tradeoff since macOS has no native Select keycode.
    message[@"scanCode"] = @(0);
    message[@"metaState"] = @(0);
    message[@"source"] = @(0x401);
  }
  [engine.keyEventChannel sendMessage:message];
}

#pragma mark - Attach / Detach

- (void)attachToViewController:(UIViewController*)viewController {
  if (self.viewController == viewController) {
    return;
  }
  if (self.viewController != nil) {
    [self detach];
  }

  self.viewController = viewController;
  [self installPressRecognizersOn:viewController.view];
  [self updateMenuRecognizerEnabled];
  [self setupAllConnectedControllers];
  [self registerMediaCommandsOnce];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(controllerDidConnect:)
                                               name:GCControllerDidConnectNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(controllerDidDisconnect:)
                                               name:GCControllerDidDisconnectNotification
                                             object:nil];
}

- (void)setFrameworkHandlesBack:(BOOL)frameworkHandlesBack {
  _frameworkHandlesBack = frameworkHandlesBack;
  [self updateMenuRecognizerEnabled];
}

- (void)detach {
  [self.keyRepeater stopRepeat];
  [self resetContinuousSwipeState];
  // Close any dangling click without emitting another channel message
  // (the view is going away).
  if (self.currentClickKey != nil) {
    [self sendKey:self.currentClickKey isDown:NO];
    self.currentClickKey = nil;
  }
  self.selectConsumedByKeyboard = NO;
  self.lastDpadX = 0;
  self.frameworkReadyForTouches = NO;

  UIView* view = self.viewController.view;
  for (UIGestureRecognizer* recognizer in self.pressRecognizers) {
    [view removeGestureRecognizer:recognizer];
  }
  [self.pressRecognizers removeAllObjects];

  for (GCController* controller in self.configuredControllers.allObjects) {
    GCMicroGamepad* gamepad = controller.microGamepad;
    if (gamepad != nil) {
      gamepad.dpad.valueChangedHandler = nil;
    }
  }
  [self.configuredControllers removeAllObjects];

  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:GCControllerDidConnectNotification
                                                object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:GCControllerDidDisconnectNotification
                                                object:nil];

  // Remove lock-screen media handlers from the shared command center so
  // they don't accumulate across engine restarts.
  [self unregisterMediaCommands];

  self.viewController = nil;
}

#pragma mark - Press recognizers

- (void)installPressRecognizersOn:(UIView*)view {
  NSArray<NSNumber*>* pressTypes = @[
    @(UIPressTypeUpArrow),
    @(UIPressTypeDownArrow),
    @(UIPressTypeLeftArrow),
    @(UIPressTypeRightArrow),
    @(UIPressTypeSelect),
    @(UIPressTypePlayPause),
    @(UIPressTypeMenu),
  ];
  for (NSNumber* typeNumber in pressTypes) {
    [self addPressRecognizerForType:(UIPressType)typeNumber.integerValue toView:view];
  }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
  if (@available(tvOS 14.3, *)) {
    [self addPressRecognizerForType:UIPressTypePageUp toView:view];
    [self addPressRecognizerForType:UIPressTypePageDown toView:view];
  }
#pragma clang diagnostic pop
}

- (void)addPressRecognizerForType:(UIPressType)pressType toView:(UIView*)view {
  UILongPressGestureRecognizer* recognizer =
      [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlePress:)];
  recognizer.allowedPressTypes = @[ @(pressType) ];
  recognizer.minimumPressDuration = 0.0;
  recognizer.delegate = self;
  if (pressType == UIPressTypeMenu) {
    self.menuPressRecognizer = recognizer;
  }
  [view addGestureRecognizer:recognizer];
  [self.pressRecognizers addObject:recognizer];
}

- (void)updateMenuRecognizerEnabled {
  // Always intercept the Menu button so Flutter can handle popRoute.
  // The Flutter framework does not send SystemNavigator.setFrameworkHandlesBack
  // on iOS/tvOS, so we cannot rely on frameworkHandlesBack here.
  // When at the root route, the framework will call SystemNavigator.pop(),
  // which the engine handles by suspending the app (see FlutterPlatformPlugin).
  self.menuPressRecognizer.enabled = YES;
}

- (void)handlePress:(UILongPressGestureRecognizer*)recognizer {
  // `allowedPressTypes` is installed with exactly one element in
  // `addPressRecognizerForType:`. A misconfigured recognizer (no types
  // or multiple types) is a programming error — assert in debug and
  // early-return rather than misrouting to Select.
  NSAssert(recognizer.allowedPressTypes.count == 1,
           @"press recognizer must have exactly one allowed type");
  if (recognizer.allowedPressTypes.count != 1) {
    return;
  }
  UIPressType pressType = (UIPressType)[recognizer.allowedPressTypes.firstObject integerValue];

  // Select is special: emits a directional-click-biased key event
  // (arrowLeft / arrowRight / select) plus a raw `click_s` / `click_e`
  // for any Dart-side `addRawListener` consumer. Keyboard handoff for
  // focused text fields runs first and may consume the press entirely.
  if (pressType == UIPressTypeSelect) {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
      FlutterTextInputPlugin* textInputPlugin = self.engine.textInputPlugin;
      if (textInputPlugin != nil && textInputPlugin.tvosKeyboardPending) {
        if ([textInputPlugin tvosActivateKeyboard]) {
          self.selectConsumedByKeyboard = YES;
          return;
        }
#ifdef DEBUG
        NSLog(@"FlutterTvRemote: tvosActivateKeyboard returned NO; falling "
              @"back to normal Select handling.");
#endif
      }
      self.selectConsumedByKeyboard = NO;
      [self handleClickDown];
    } else if (recognizer.state == UIGestureRecognizerStateEnded ||
               recognizer.state == UIGestureRecognizerStateCancelled ||
               recognizer.state == UIGestureRecognizerStateFailed) {
      if (self.selectConsumedByKeyboard) {
        self.selectConsumedByKeyboard = NO;
        return;
      }
      [self handleClickUp];
    }
    return;
  }

  BOOL isDown = recognizer.state == UIGestureRecognizerStateBegan;
  BOOL isUp = recognizer.state == UIGestureRecognizerStateEnded ||
              recognizer.state == UIGestureRecognizerStateCancelled;
  if (!isDown && !isUp)
    return;

  NSString* keyName = _LogicalKeyNameForPressType(pressType);
  if (keyName.length == 0)
    return;

  // Arrow and page keys route through the key repeater — holding the
  // physical button auto-repeats like a real keyboard.
  BOOL isRepeatable =
      [keyName isEqualToString:@"arrowUp"] || [keyName isEqualToString:@"arrowDown"] ||
      [keyName isEqualToString:@"arrowLeft"] || [keyName isEqualToString:@"arrowRight"] ||
      [keyName isEqualToString:@"pageUp"] || [keyName isEqualToString:@"pageDown"];
  if (isRepeatable) {
    if (isDown) {
      [self.keyRepeater startRepeat:keyName];
    } else {
      [self.keyRepeater stopRepeat];
    }
    return;
  }

  // Menu → flutter/navigation popRoute (Flutter Android parity). Emit
  // once per press, on Began only — matches Android back-button semantics.
  if ([keyName isEqualToString:@"menu"]) {
    if (isDown) {
      [self.engine.navigationChannel invokeMethod:@"popRoute" arguments:nil];
    }
    return;
  }

  // Physical Play/Pause → LogicalKeyboardKey.mediaPlayPause via the
  // Android keymap (Flutter's macOS table has no mediaPlayPause entry).
  if ([keyName isEqualToString:@"playPause"]) {
    [self sendKey:@"mediaPlayPause" isDown:isDown];
    return;
  }
}

#pragma mark - Touchpad click

/// Translate a Select press into the right logical key, applying the
/// directional-click bias based on the last D-pad `loc` position. Also
/// emits a raw `click_s` so Dart-side `addRawListener` consumers see
/// the unsynthesized event.
- (void)handleClickDown {
  if (self.currentClickKey != nil) {
    // Previous `click_s` has no matching `click_e` — emit the keyup so
    // `HardwareKeyboard.logicalKeysPressed` doesn't stay stuck in the
    // old state.
    [self sendKey:self.currentClickKey isDown:NO];
    self.currentClickKey = nil;
  }
  NSString* key = [self debugClickKeyNameForDpadX:self.lastDpadX deadZone:self.dpadDeadZone];
  self.currentClickKey = key;
  [self sendKey:key isDown:YES];
  [self sendTouchEventOfType:kFlutterTvRemoteTouchPhaseClickStart x:0.0 y:0.0];
}

- (NSString*)debugClickKeyNameForDpadX:(double)x deadZone:(double)deadZone {
  if (fabs(x) >= deadZone) {
    return x >= 0 ? @"arrowRight" : @"arrowLeft";
  }
  return @"select";
}

- (void)handleClickUp {
  NSString* key = self.currentClickKey;
  self.currentClickKey = nil;
  if (key != nil) {
    [self sendKey:key isDown:NO];
  }
  [self sendTouchEventOfType:kFlutterTvRemoteTouchPhaseClickEnd x:0.0 y:0.0];
}

#pragma mark - Touches

- (void)handleTouches:(NSSet<UITouch*>*)touches phase:(NSString*)phase view:(UIView*)view {
  CGSize size = view.bounds.size;
  if (size.width <= 0 || size.height <= 0)
    return;

  BOOL isStart = [phase isEqualToString:kFlutterTvRemoteTouchPhaseStarted];
  BOOL isMove = [phase isEqualToString:kFlutterTvRemoteTouchPhaseMove];
  BOOL isEnd = [phase isEqualToString:kFlutterTvRemoteTouchPhaseEnded] ||
               [phase isEqualToString:kFlutterTvRemoteTouchPhaseCancelled];

  for (UITouch* touch in touches) {
    CGPoint location = [touch locationInView:view];
    double x = (location.x / size.width) * 2.0 - 1.0;
    double y = (location.y / size.height) * 2.0 - 1.0;
    [self sendTouchEventOfType:phase x:x y:y];

    if (isStart) {
      // Reset first — the reset method clears `lastTouchX/Y` as part of
      // its bookkeeping. If we assigned them before calling reset, the
      // first `move` delta would be computed from (0, 0) instead of
      // the actual touch-start point, delaying auto-repeat by one move.
      [self resetContinuousSwipeState];
      self.lastTouchX = x;
      self.lastTouchY = y;
    } else if (isMove) {
      [self updateContinuousSwipeWithX:x y:y];
      self.lastTouchX = x;
      self.lastTouchY = y;
    }
  }

  if (isEnd) {
    [self.keyRepeater stopRepeat];
    [self resetContinuousSwipeState];
  }
}

- (void)sendTouchEventOfType:(NSString*)type x:(double)x y:(double)y {
  if (!self.frameworkReadyForTouches) {
    return;
  }
  [self.touchesChannel sendMessage:@{
    @"type" : type,
    @"x" : @(x),
    @"y" : @(y),
  }];
}

#pragma mark - Continuous swipe detection

/// Maps a move delta to the dominant cardinal direction as an arrow key
/// name, or nil if the delta is effectively zero. Implementation lives
/// in the class method `+debugDirectionFromDeltaX:y:` (see Testing
/// category in `_Internal.h`) so unit tests can call it directly.
+ (nullable NSString*)debugDirectionFromDeltaX:(double)dx y:(double)dy {
  const double kDeadZone = 0.02;  // ignore micro-jitter
  double adx = fabs(dx);
  double ady = fabs(dy);
  if (adx < kDeadZone && ady < kDeadZone)
    return nil;
  if (adx >= ady) {
    return dx >= 0 ? @"arrowRight" : @"arrowLeft";
  }
  return dy >= 0 ? @"arrowDown" : @"arrowUp";
}

- (void)updateContinuousSwipeWithX:(double)x y:(double)y {
  double dx = x - self.lastTouchX;
  double dy = y - self.lastTouchY;
  NSString* direction = [FlutterTvRemotePlugin debugDirectionFromDeltaX:dx y:dy];
  if (direction == nil)
    return;

  if ([direction isEqualToString:self.continuousSwipeDirection]) {
    self.continuousSwipeMoveCount += 1;
  } else {
    self.continuousSwipeDirection = direction;
    self.continuousSwipeMoveCount = 1;
    // Direction change cancels any prior repeat.
    [self.keyRepeater stopRepeat];
  }

  if (self.continuousSwipeMoveCount >= self.continuousSwipeMoveThreshold) {
    [self.keyRepeater startRepeat:direction];
  }
}

- (void)resetContinuousSwipeState {
  self.continuousSwipeDirection = nil;
  self.continuousSwipeMoveCount = 0;
  self.lastTouchX = 0;
  self.lastTouchY = 0;
}

#pragma mark - Game controllers (D-pad)

- (void)setupAllConnectedControllers {
  for (GCController* controller in [GCController controllers]) {
    [self configureController:controller];
  }
}

- (void)configureController:(GCController*)controller {
  GCMicroGamepad* gamepad = controller.microGamepad;
  if (gamepad == nil) {
#ifdef DEBUG
    NSLog(@"FlutterTvRemote: controller '%@' has no microGamepad projection; D-pad events "
          @"will not be forwarded.",
          controller.vendorName ?: @"(unknown vendor)");
#endif
    return;
  }

  gamepad.dpad.valueChangedHandler = nil;
  gamepad.reportsAbsoluteDpadValues = YES;
  __weak FlutterTvRemotePlugin* weakSelf = self;
  gamepad.dpad.valueChangedHandler =
      ^(GCControllerDirectionPad* _Nonnull dpad, float xValue, float yValue) {
        [weakSelf debugHandleDpadX:xValue y:yValue];
      };
  [self.configuredControllers addObject:controller];
}

- (void)debugHandleDpadX:(float)x y:(float)y {
  // Cache x for the directional-click bias. Raw listeners on the
  // touches channel still see the full event.
  self.lastDpadX = x;
  [self sendTouchEventOfType:kFlutterTvRemoteTouchPhaseLoc x:x y:y];
}

- (void)controllerDidConnect:(NSNotification*)notification {
  dispatch_async(dispatch_get_main_queue(), ^{
    GCController* controller = notification.object;
    if ([controller isKindOfClass:[GCController class]]) {
      [self configureController:controller];
    } else {
      [self setupAllConnectedControllers];
    }
  });
}

- (void)controllerDidDisconnect:(NSNotification*)notification {
  // Notification may be posted on a background thread on real hardware.
  // Mirror `controllerDidConnect:` — bounce to main so mutations on
  // `configuredControllers` and `gamepad.dpad` stay race-free.
  dispatch_async(dispatch_get_main_queue(), ^{
    GCController* controller = notification.object;
    if ([controller isKindOfClass:[GCController class]]) {
      GCMicroGamepad* gamepad = controller.microGamepad;
      if (gamepad != nil) {
        gamepad.dpad.valueChangedHandler = nil;
      }
      [self.configuredControllers removeObject:controller];
    }
  });
}

#pragma mark - Media commands (MPRemoteCommandCenter)

/// Registers a handler on a command and records the `(command, token)`
/// pair so `unregisterMediaCommands` can remove it on detach.
- (void)addMediaHandlerOn:(MPRemoteCommand*)command
                    block:(MPRemoteCommandHandlerStatus (^)(MPRemoteCommandEvent* event))block {
  id token = [command addTargetWithHandler:block];
  [self.mediaCommandBindings addObject:@{@"command" : command, @"token" : token}];
}

- (void)registerMediaCommandsOnce {
  if (self.mediaCommandsRegistered)
    return;

  MPRemoteCommandCenter* center = [MPRemoteCommandCenter sharedCommandCenter];
  __weak FlutterTvRemotePlugin* weakSelf = self;

  // All handlers emit through `flutter/keyevent` (via sendKey:) so the
  // lock-screen controls land in HardwareKeyboard / focus / shortcuts
  // exactly like a physical keyboard event. No app-level listener
  // needed — any widget reacting to LogicalKeyboardKey.mediaPlayPause
  // et al. is activated out of the box. The dispatch helpers
  // (`debugDispatchMediaSeekKey:isDown:`, `debugDispatchMediaDiscreteKey:`,
  // `debugDispatchMediaPlaybackRate:`) are exposed via the Testing
  // category for unit tests; the inline blocks here just forward.
  [self addMediaHandlerOn:center.seekForwardCommand
                    block:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent* event) {
                      MPSeekCommandEventType type = ((MPSeekCommandEvent*)event).type;
                      BOOL isDown = type == MPSeekCommandEventTypeBeginSeeking;
                      [weakSelf debugDispatchMediaSeekKey:@"mediaFastForward" isDown:isDown];
                      return MPRemoteCommandHandlerStatusSuccess;
                    }];

  [self addMediaHandlerOn:center.seekBackwardCommand
                    block:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent* event) {
                      MPSeekCommandEventType type = ((MPSeekCommandEvent*)event).type;
                      BOOL isDown = type == MPSeekCommandEventTypeBeginSeeking;
                      [weakSelf debugDispatchMediaSeekKey:@"mediaRewind" isDown:isDown];
                      return MPRemoteCommandHandlerStatusSuccess;
                    }];

  [self addMediaHandlerOn:center.playCommand
                    block:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent* event) {
                      [weakSelf debugDispatchMediaDiscreteKey:@"mediaPlay"];
                      return MPRemoteCommandHandlerStatusSuccess;
                    }];

  [self addMediaHandlerOn:center.pauseCommand
                    block:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent* event) {
                      [weakSelf debugDispatchMediaDiscreteKey:@"mediaPause"];
                      return MPRemoteCommandHandlerStatusSuccess;
                    }];

  [self addMediaHandlerOn:center.stopCommand
                    block:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent* event) {
                      [weakSelf debugDispatchMediaDiscreteKey:@"mediaStop"];
                      return MPRemoteCommandHandlerStatusSuccess;
                    }];

  [self addMediaHandlerOn:center.togglePlayPauseCommand
                    block:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent* event) {
                      [weakSelf debugDispatchMediaDiscreteKey:@"mediaPlayPause"];
                      return MPRemoteCommandHandlerStatusSuccess;
                    }];

  [self addMediaHandlerOn:center.changePlaybackRateCommand
                    block:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent* event) {
                      float rate = ((MPChangePlaybackRateCommandEvent*)event).playbackRate;
                      [weakSelf debugDispatchMediaPlaybackRate:rate];
                      return MPRemoteCommandHandlerStatusSuccess;
                    }];

  // Set the flag only after every handler is installed — if an
  // exception interrupts registration, re-attach can retry.
  self.mediaCommandsRegistered = YES;
}

#pragma mark - Media dispatch helpers (Testing surface)

- (void)debugDispatchMediaSeekKey:(NSString*)keyName isDown:(BOOL)isDown {
  [self sendKey:keyName isDown:isDown];
}

- (void)debugDispatchMediaDiscreteKey:(NSString*)keyName {
  // Discrete (not hold-able) media commands emit a full keydown+keyup
  // pair so HardwareKeyboard state does not get stuck with the key
  // logically held.
  [self sendKey:keyName isDown:YES];
  [self sendKey:keyName isDown:NO];
}

- (void)debugDispatchMediaPlaybackRate:(float)rate {
  if (rate > 0) {
    [self sendKey:@"mediaFastForward" isDown:YES];
    [self sendKey:@"mediaFastForward" isDown:NO];
  } else if (rate < 0) {
    [self sendKey:@"mediaRewind" isDown:YES];
    [self sendKey:@"mediaRewind" isDown:NO];
  }
}

- (void)debugSendTouchEventOfType:(NSString*)type x:(double)x y:(double)y {
  [self sendTouchEventOfType:type x:x y:y];
}

#pragma mark - Internal state mirrors (Testing surface)

- (NSString* _Nullable)debugContinuousSwipeDirection {
  return self.continuousSwipeDirection;
}
- (NSInteger)debugContinuousSwipeMoveCount {
  return self.continuousSwipeMoveCount;
}
- (double)debugLastDpadX {
  return self.lastDpadX;
}
- (double)debugLastTouchX {
  return self.lastTouchX;
}
- (double)debugLastTouchY {
  return self.lastTouchY;
}
- (NSString* _Nullable)debugCurrentClickKey {
  return self.currentClickKey;
}
- (double)debugDpadDeadZone {
  return self.dpadDeadZone;
}
- (double)debugShortSwipeThreshold {
  return self.shortSwipeThreshold;
}
- (double)debugFastSwipeThreshold {
  return self.fastSwipeThreshold;
}
- (NSInteger)debugContinuousSwipeMoveThreshold {
  return self.continuousSwipeMoveThreshold;
}
- (BOOL)debugSelectConsumedByKeyboard {
  return self.selectConsumedByKeyboard;
}
- (BOOL)debugMediaCommandsRegistered {
  return self.mediaCommandsRegistered;
}
- (NSArray<NSDictionary<NSString*, id>*>*)debugMediaCommandBindings {
  return self.mediaCommandBindings;
}
- (NSArray<UIGestureRecognizer*>*)debugPressRecognizers {
  return self.pressRecognizers;
}
- (FlutterTvKeyRepeater*)debugKeyRepeater {
  return self.keyRepeater;
}

/// Remove every handler installed by `registerMediaCommandsOnce`.
/// Safe to call when idle.
- (void)unregisterMediaCommands {
  for (NSDictionary<NSString*, id>* binding in self.mediaCommandBindings) {
    MPRemoteCommand* command = binding[@"command"];
    id token = binding[@"token"];
    [command removeTarget:token];
  }
  [self.mediaCommandBindings removeAllObjects];
  self.mediaCommandsRegistered = NO;
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)other {
  return YES;
}

@end

NS_ASSUME_NONNULL_END

#endif  // TARGET_OS_TV
