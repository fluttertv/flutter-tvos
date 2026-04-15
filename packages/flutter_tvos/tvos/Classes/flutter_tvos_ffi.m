// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "flutter_tvos_ffi.h"
#import <UIKit/UIKit.h>
#import <TargetConditionals.h>
#include <sys/sysctl.h>
#include <string.h>
#include <stdlib.h>

// Static buffers for string results (device info doesn't change at runtime).
static char s_system_version[64] = {0};
static char s_device_model[128] = {0};
static char s_machine_id[64] = {0};
static bool s_initialized = false;

static void _ensure_initialized(void) {
    if (s_initialized) return;
    s_initialized = true;

    @autoreleasepool {
        // System version
        NSString *version = [[UIDevice currentDevice] systemVersion];
        strncpy(s_system_version, [version UTF8String], sizeof(s_system_version) - 1);

        // Device model
        NSString *model = [[UIDevice currentDevice] model];
        strncpy(s_device_model, [model UTF8String], sizeof(s_device_model) - 1);

        // Machine identifier via sysctl
        size_t size = 0;
        sysctlbyname("hw.machine", NULL, &size, NULL, 0);
        if (size > 0 && size < sizeof(s_machine_id)) {
            sysctlbyname("hw.machine", s_machine_id, &size, NULL, 0);
        }
    }
}

bool flutter_tvos_is_tvos(void) {
#if TARGET_OS_TV
    return true;
#else
    return false;
#endif
}

const char* flutter_tvos_system_version(void) {
    _ensure_initialized();
    return s_system_version;
}

const char* flutter_tvos_device_model(void) {
    _ensure_initialized();
    return s_device_model;
}

const char* flutter_tvos_machine_id(void) {
    _ensure_initialized();
    return s_machine_id;
}

bool flutter_tvos_is_simulator(void) {
#if TARGET_OS_SIMULATOR
    return true;
#else
    return false;
#endif
}

bool flutter_tvos_supports_4k(void) {
    @autoreleasepool {
        CGFloat width = [UIScreen mainScreen].nativeBounds.size.width;
        return width >= 3840.0;
    }
}

bool flutter_tvos_supports_hdr(void) {
#if TARGET_OS_TV
    if (@available(tvOS 11.2, *)) {
        @autoreleasepool {
            UIScreen *screen = [UIScreen mainScreen];
            // Check for EDR headroom support as a proxy for HDR capability
            if ([screen respondsToSelector:@selector(potentialEDRHeadroom)]) {
                return true;
            }
        }
    }
#endif
    return false;
}

bool flutter_tvos_supports_multi_user(void) {
#if TARGET_OS_TV
    if (@available(tvOS 14.0, *)) {
        return true;
    }
#endif
    return false;
}

int32_t flutter_tvos_display_width(void) {
    @autoreleasepool {
        return (int32_t)[UIScreen mainScreen].nativeBounds.size.width;
    }
}

int32_t flutter_tvos_display_height(void) {
    @autoreleasepool {
        return (int32_t)[UIScreen mainScreen].nativeBounds.size.height;
    }
}
