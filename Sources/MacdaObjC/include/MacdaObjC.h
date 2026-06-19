#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block`, catching any Objective-C exception (e.g. AVFoundation's
/// installTapOnBus assertions) and reporting it as an NSError instead of
/// aborting the whole process. Returns YES on success.
BOOL MacdaTryCatch(void (^_Nonnull block)(void), NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
