#include "SthenoTypeEncoding.h"
#include <string.h>

static const char *unqualified(const char *type) {
    if (type == NULL) return NULL;
    while (*type != '\0' && strchr("rnNoORV", *type) != NULL) ++type;
    return type;
}

static bool isObject(const char *type) {
    return type[0] == '@' && (type[1] == '\0' || type[1] == '"');
}

bool SthenoTypesAreABICompatible(const char *original, const char *replacement,
                                bool allowOpaqueBlockArgument) {
    original = unqualified(original);
    replacement = unqualified(replacement);
    if (original == NULL || replacement == NULL || *original == '\0' ||
        *replacement == '\0' || *original == '?' || *replacement == '?') return false;
    if (strcmp(original, replacement) == 0) return true;
    if (isObject(original) && isObject(replacement)) return true;
    // Deliberately one-way and opt-in at one specific argument index only.
    // The Swift hook passes the ObjC block object through without invoking it.
    return allowOpaqueBlockArgument && strcmp(original, "@?") == 0 && isObject(replacement);
}
