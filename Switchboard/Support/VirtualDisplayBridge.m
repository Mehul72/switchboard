#import "VirtualDisplayBridge.h"
#import <dlfcn.h>
#import <math.h>
#import <os/log.h>

@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic, strong) NSString *name;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) CGPoint redPrimary;
@property(nonatomic) CGPoint greenPrimary;
@property(nonatomic) CGPoint bluePrimary;
@property(nonatomic) CGPoint whitePoint;
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int serialNumber;
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height
                  refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic, strong) NSArray *modes;
@property(nonatomic) unsigned int hiDPI;
@end

@interface CGVirtualDisplay : NSObject
@property(nonatomic, readonly) unsigned int displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

static NSString * const SBVirtualDisplayErrorDomain = @"Switchboard.DisplayScaling";

static void SBSetDisplayError(NSError **error, NSInteger code, NSString *description) {
    if (error) {
        *error = [NSError errorWithDomain:SBVirtualDisplayErrorDomain code:code
                                userInfo:@{NSLocalizedDescriptionKey: description}];
    }
}

static BOOL SBClassSupports(NSString *name, NSArray<NSString *> *selectors) {
    Class type = NSClassFromString(name);
    if (!type) return NO;
    for (NSString *selector in selectors) {
        if (![type instancesRespondToSelector:NSSelectorFromString(selector)]) return NO;
    }
    return YES;
}

@implementation SBVirtualDisplay {
    CGVirtualDisplay *_display;
    CGDirectDisplayID _displayID;
}

+ (BOOL)isAvailable {
    return SBClassSupports(@"CGVirtualDisplay", @[@"initWithDescriptor:", @"applySettings:", @"displayID"])
        && SBClassSupports(@"CGVirtualDisplayDescriptor", @[@"setName:", @"setQueue:",
            @"setMaxPixelsWide:", @"setMaxPixelsHigh:", @"setSizeInMillimeters:",
            @"setRedPrimary:", @"setGreenPrimary:", @"setBluePrimary:", @"setWhitePoint:",
            @"setVendorID:", @"setProductID:", @"setSerialNum:"])
        && SBClassSupports(@"CGVirtualDisplayMode", @[@"initWithWidth:height:refreshRate:"])
        && SBClassSupports(@"CGVirtualDisplaySettings", @[@"setModes:", @"setHiDPI:"]);
}

- (instancetype)initWithName:(NSString *)name width:(uint32_t)width height:(uint32_t)height
                refreshRate:(double)refreshRate error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    // Bound the backing allocation before crossing the private framework boundary.
    if (width < 800 || height < 600 || width > 4096 || height > 4096
        || (uint64_t)width * height * 4 > 33554432
        || !isfinite(refreshRate) || refreshRate < 1 || refreshRate > 240) {
        SBSetDisplayError(error, 1, @"This scaling size or refresh rate is outside the supported range.");
        return nil;
    }
    if (![SBVirtualDisplay isAvailable]) {
        SBSetDisplayError(error, 2, @"This version of macOS does not expose the required display-scaling support.");
        return nil;
    }
    @try {
        CGVirtualDisplayDescriptor *descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
        descriptor.name = name;
        descriptor.queue = dispatch_get_main_queue();
        descriptor.maxPixelsWide = width * 2;
        descriptor.maxPixelsHigh = height * 2;
        descriptor.sizeInMillimeters = CGSizeMake(width * 2 * 25.4 / 220, height * 2 * 25.4 / 220);
        descriptor.redPrimary = CGPointMake(0.64, 0.33);
        descriptor.greenPrimary = CGPointMake(0.30, 0.60);
        descriptor.bluePrimary = CGPointMake(0.15, 0.06);
        descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
        descriptor.vendorID = 0x5357;
        descriptor.productID = 1;
        unsigned int serial = arc4random_uniform(UINT32_MAX - 1) + 1;
        descriptor.serialNum = serial;
        if ([descriptor respondsToSelector:@selector(setSerialNumber:)]) descriptor.serialNumber = serial;

        _display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
        if (!_display || _display.displayID == kCGNullDirectDisplay) {
            SBSetDisplayError(error, 3, @"macOS could not create the HiDPI desktop.");
            return nil;
        }
        _displayID = _display.displayID;
        CGVirtualDisplayMode *mode = [[NSClassFromString(@"CGVirtualDisplayMode") alloc]
                                     initWithWidth:width height:height refreshRate:refreshRate];
        CGVirtualDisplaySettings *settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
        settings.hiDPI = 1;
        settings.modes = mode ? @[mode] : @[];
        if (!mode || ![_display applySettings:settings]) {
            [self invalidate];
            SBSetDisplayError(error, 4, @"macOS rejected the requested HiDPI desktop size.");
            return nil;
        }
    } @catch (NSException *exception) {
        [self invalidate];
        os_log_error(OS_LOG_DEFAULT, "Switchboard display setup exception: %{public}@", exception.name);
        SBSetDisplayError(error, 5, @"macOS display-scaling support failed. Your original display settings will be restored.");
        return nil;
    }
    return self;
}

- (CGDirectDisplayID)displayID { return _displayID; }

- (void)invalidate {
    _displayID = kCGNullDirectDisplay;
    _display = nil;
}
@end

NSDictionary<NSString *, id> *SBDisplayInfo(CGDirectDisplayID displayID) {
    typedef CFDictionaryRef (*CopyDisplayInfo)(CGDirectDisplayID);
    static CopyDisplayInfo copyInfo;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *framework = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY | RTLD_LOCAL);
        if (framework) copyInfo = (CopyDisplayInfo)dlsym(framework, "CoreDisplay_DisplayCreateInfoDictionary");
    });
    if (!copyInfo) return nil;
    @try {
        return CFBridgingRelease(copyInfo(displayID));
    } @catch (NSException *exception) {
        os_log_error(OS_LOG_DEFAULT, "Switchboard display information exception: %{public}@", exception.name);
        return nil;
    }
}
