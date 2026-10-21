#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "SthenoMethodABI.h"
#include <stdio.h>
#include <stdlib.h>

@interface Original : NSObject
- (void)nothing;
- (id)object;
- (NSUInteger)options;
- (CGRect)bounds:(NSInteger)orientation;
- (void)callback:(void (^)(void))block;
- (void)two:(id)a other:(id)b;
@end
@implementation Original
- (void)nothing {}
- (id)object { return self; }
- (NSUInteger)options { return 1; }
- (CGRect)bounds:(NSInteger)orientation { return CGRectMake(1, 2, 3, 4); }
- (void)callback:(void (^)(void))block {}
- (void)two:(id)a other:(id)b {}
@end
@interface Replacement : NSObject
- (id)nothing;
- (void)object;
- (id)options;
- (id)bounds:(NSInteger)orientation;
- (void)callback:(id)block;
- (void)two:(id)a;
@end
@implementation Replacement
- (id)nothing { return self; }
- (void)object {}
- (id)options { return self; }
- (id)bounds:(NSInteger)orientation { return self; }
- (void)callback:(id)block {}
- (void)two:(id)a {}
@end
static void require(BOOL condition, const char *name) {
    if (!condition) { fprintf(stderr, "NATIVE_ABI_FAIL %s\n", name); exit(1); }
    printf("NATIVE_ABI_PASS %s\n", name);
}
int main(void) {
    @autoreleasepool {
        const SEL selectors[] = { @selector(nothing), @selector(object), @selector(options), @selector(bounds:) };
        for (unsigned int i = 0; i < 4; ++i) {
            Method actual = class_getInstanceMethod(Original.class, selectors[i]);
            Method wrong = class_getInstanceMethod(Replacement.class, selectors[i]);
            require(!SthenoMethodsHaveSameABI(actual, wrong, -1), sel_getName(selectors[i]));
            require(SthenoMethodsHaveSameABI(actual, actual, -1), "unchanged ABI admitted");
        }
        Method block = class_getInstanceMethod(Original.class, @selector(callback:));
        Method opaque = class_getInstanceMethod(Replacement.class, @selector(callback:));
        require(!SthenoMethodsHaveSameABI(block, opaque, -1), "block is not a generic object by default");
        require(SthenoMethodsHaveSameABI(block, opaque, 2), "specific opaque callback slot forwarded");
        require(!SthenoMethodsHaveSameABI(block, opaque, 3), "wrong callback slot rejected");
        require(!SthenoMethodsHaveSameABI(NULL, opaque, -1), "missing method rejected");
        require(!SthenoMethodsHaveSameABI(class_getInstanceMethod(Original.class, @selector(two:other:)),
                                        class_getInstanceMethod(Replacement.class, @selector(two:)), -1), "arity mismatch rejected");
        const char *boundsArgs[] = { @encode(id), @encode(SEL), @encode(NSInteger) };
        Method bounds = class_getInstanceMethod(Original.class, @selector(bounds:));
        require(SthenoMethodMatchesTypes(bounds, @encode(CGRect), boundsArgs, 3), "native CGRect accepted");
        require(!SthenoMethodMatchesTypes(bounds, @encode(id), boundsArgs, 3), "native id CGRect mismatch rejected");
        puts("NATIVE_ABI_ALL_PASS");
    }
    return 0;
}
