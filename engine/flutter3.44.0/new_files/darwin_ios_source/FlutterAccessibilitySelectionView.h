// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_FLUTTERACCESSIBILITYSELECTIONVIEW_H_
#define FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_FLUTTERACCESSIBILITYSELECTIONVIEW_H_

#import <UIKit/UIKit.h>

// A UIView subclass used on tvOS to represent the current accessibility
// selection rectangle. The system focus engine tracks this view's frame to
// draw the selection indicator.
@interface FlutterAccessibilitySelectionView : UIView
@end

#endif  // FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_FLUTTERACCESSIBILITYSELECTIONVIEW_H_
