#pragma once
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
// Outer ABI only. Never asserts an object class or a block's invoke signature.
bool SthenoTypesAreABICompatible(const char *original, const char *replacement,
                                bool allowOpaqueBlockArgument);
#ifdef __cplusplus
}
#endif
