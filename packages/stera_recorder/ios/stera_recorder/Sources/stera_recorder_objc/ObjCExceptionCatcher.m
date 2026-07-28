#import "./include/stera_recorder_objc/ObjCExceptionCatcher.h"

NSException * _Nullable ObjCTryBlock(void(NS_NOESCAPE ^block)(void)) {
    @try {
        block();
        return nil;
    }
    @catch (NSException *exception) {
        return exception;
    }
}
