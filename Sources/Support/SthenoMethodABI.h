#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// Full method arity includes self and _cmd. -1 allows no opaque block slots.
BOOL SthenoMethodsHaveSameABI(Method original, Method replacement, NSInteger opaqueBlockArgumentIndex);
BOOL SthenoMethodMatchesTypes(Method method, const char *returnType,
                             const char *const *argumentTypes, size_t argumentCount);
#ifdef __cplusplus
}
#endif
