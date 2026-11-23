#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface SBVirtualDisplay : NSObject
@property(class, nonatomic, readonly, getter=isAvailable) BOOL available;
@property(nonatomic, readonly) CGDirectDisplayID displayID;

- (nullable instancetype)initWithName:(NSString *)name
                               width:(uint32_t)width
                              height:(uint32_t)height
                         refreshRate:(double)refreshRate
                               error:(NSError * _Nullable * _Nullable)error;
- (void)invalidate;
@end

/// Nil means the runtime cannot provide the hardware metadata needed for scaling.
FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
SBDisplayInfo(CGDirectDisplayID displayID);

NS_ASSUME_NONNULL_END
