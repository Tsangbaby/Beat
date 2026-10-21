#import "SthenoMethodABI.h"
#include "SthenoTypeEncoding.h"
#include <stdlib.h>

BOOL SthenoMethodsHaveSameABI(Method original, Method replacement, NSInteger opaqueBlockArgumentIndex) {
    if (original == NULL || replacement == NULL) return NO;
    unsigned int count = method_getNumberOfArguments(original);
    if (count < 2 || count != method_getNumberOfArguments(replacement)) return NO;
    char *left = method_copyReturnType(original);
    char *right = method_copyReturnType(replacement);
    BOOL same = SthenoTypesAreABICompatible(left, right, false);
    free(left); free(right);
    if (!same) return NO;
    for (unsigned int i = 0; i < count; ++i) {
        left = method_copyArgumentType(original, i);
        right = method_copyArgumentType(replacement, i);
        same = SthenoTypesAreABICompatible(left, right, (NSInteger)i == opaqueBlockArgumentIndex);
        free(left); free(right);
        if (!same) return NO;
    }
    return YES;
}

BOOL SthenoMethodMatchesTypes(Method method, const char *returnType,
                             const char *const *argumentTypes, size_t argumentCount) {
    if (method == NULL || argumentTypes == NULL || argumentCount < 2 ||
        method_getNumberOfArguments(method) != argumentCount) return NO;
    char *type = method_copyReturnType(method);
    BOOL same = SthenoTypesAreABICompatible(type, returnType, false);
    free(type);
    if (!same) return NO;
    for (unsigned int i = 0; i < argumentCount; ++i) {
        type = method_copyArgumentType(method, i);
        same = SthenoTypesAreABICompatible(type, argumentTypes[i], false);
        free(type);
        if (!same) return NO;
    }
    return YES;
}
