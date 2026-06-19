#import "MacdaObjC.h"

BOOL MacdaTryCatch(void (^block)(void), NSError **error) {
    @try {
        block();
        return YES;
    }
    @catch (NSException *exception) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"%@: %@",
                              exception.name, exception.reason ?: @"(no reason)"];
            *error = [NSError errorWithDomain:@"MacdaException"
                                         code:0
                                     userInfo:@{ NSLocalizedDescriptionKey: desc }];
        }
        return NO;
    }
}
