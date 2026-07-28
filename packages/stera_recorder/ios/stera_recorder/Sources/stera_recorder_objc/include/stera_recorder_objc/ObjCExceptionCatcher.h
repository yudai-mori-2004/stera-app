#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Executes @p block inside @try/@catch.
/// Returns the NSException if one was thrown, nil otherwise.
NSException * _Nullable ObjCTryBlock(void(NS_NOESCAPE ^block)(void));

NS_ASSUME_NONNULL_END
