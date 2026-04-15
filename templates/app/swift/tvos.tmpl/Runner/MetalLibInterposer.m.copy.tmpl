// MetalLibInterposer.m
// Runtime swizzle [MTLDevice newLibraryWithData:error:] so that the iOS-targeted
// metallibs embedded in Flutter.framework are transparently replaced with
// correctly-targeted tvOS metallib equivalents loaded from the app bundle.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>

static NSDictionary<NSNumber *, NSString *> *sOriginalSizeToName;
static IMP sOriginalNewLibraryWithData;

static id tvos_newLibraryWithData(id self, SEL _cmd,
                                   dispatch_data_t data,
                                   NSError **error) {
    size_t dataSize = dispatch_data_get_size(data);
    NSString *name = sOriginalSizeToName[@(dataSize)];
    if (name) {
        NSString *path = [[NSBundle mainBundle]
            pathForResource:name ofType:@"metallib"
                inDirectory:@"tvos_metallibs"];
        if (path) {
            NSData *tvosData = [NSData dataWithContentsOfFile:path];
            if (tvosData) {
                __block NSData *retained = tvosData;
                dispatch_data_t tvosDD = dispatch_data_create(
                    retained.bytes, retained.length,
                    dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),
                    ^{ (void)retained; });

                NSLog(@"[MetalLibInterposer] Replaced '%@' metallib: "
                      @"iOS(%zu B) -> tvOS(%lu B)",
                      name, dataSize, (unsigned long)tvosData.length);

                return ((id (*)(id, SEL, dispatch_data_t, NSError **))
                        sOriginalNewLibraryWithData)(
                    self, _cmd, tvosDD, error);
            }
        }
        NSLog(@"[MetalLibInterposer] WARNING: tvOS metallib '%@' not found in bundle!", name);
    }
    return ((id (*)(id, SEL, dispatch_data_t, NSError **))
            sOriginalNewLibraryWithData)(self, _cmd, data, error);
}

@interface MetalLibInterposer : NSObject
@end

@implementation MetalLibInterposer

+ (void)load {
    sOriginalSizeToName = @{
        @8306  : @"compute",
        @251746: @"entity",
        @13794 : @"framebuffer_blend",
        @25567 : @"modern"
    };

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        NSLog(@"[MetalLibInterposer] No Metal device — skipping.");
        return;
    }

    Class cls = [device class];
    SEL sel   = @selector(newLibraryWithData:error:);
    Method m  = class_getInstanceMethod(cls, sel);
    if (!m) {
        NSLog(@"[MetalLibInterposer] Could not find -newLibraryWithData:error: on %@",
              NSStringFromClass(cls));
        return;
    }

    sOriginalNewLibraryWithData =
        method_setImplementation(m, (IMP)tvos_newLibraryWithData);

    NSLog(@"[MetalLibInterposer] Installed on %@ — will replace 4 metallibs at runtime.",
          NSStringFromClass(cls));
}

@end
