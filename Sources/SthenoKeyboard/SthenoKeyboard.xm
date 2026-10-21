// SthenoKeyboard.xm
// 注入目标：UIKit（见 SthenoKeyboard.plist），实际作用于键盘宿主进程
//
// 还原置信度：中高。0x8d0 字节代码，已逐函数识别：
//   0x4000 写日志       0x419c 读 /tmp/stheno_frontmost.json
//   0x4304 读 plist "169"   0x43b4 读 plist "Apps" 判断白名单
//   0x4498 注册 Darwin 通知  0x44bc 通知回调（重读环境 + 调整键盘窗口）
//   0x4544 ctor          0x46b4/0x46fc/0x463c 三处 MSHookMessageEx
//   0x482c UIScene -initWithSession:connectionOptions:
//
// 作用：把一个「浮窗键盘」的宿主窗口撑到全屏尺寸，使键盘在浮窗里以完整宽度渲染；
// 是否生效由主模块写出的 plist / json 决定。

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <notify.h>

#import <UIKit/UIKit.h>
#import "../Support/SthenoPaths.h"

static NSString *const kPreferencePlist = @"/var/mobile/Library/Preferences/com.nx.stheno.plist";
static NSString *const kFrontmostJSON   = @"/tmp/stheno_frontmost.json";
static NSString *const kLogPath         = @"/var/mobile/Documents/AppLecard.log";
static NSString *const kDarwinNotify    = @"com.nx.SthenoKeyboard";

static BOOL      gKeyboardOverrideEnabled = NO;   // __common+0x0（plist "169"）
static NSDictionary *gFrontmostSnapshot   = nil;  // __bss+0x8
static NSString *gFrontmostBundleID       = nil;  // __common+0x10
static BOOL      gAdjustingKeyboardWindow = NO;   // __data+0x8（重入保护）

#pragma mark - 日志（0x4000）

static void SthenoLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], message];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:SthenoJBRootPath(kLogPath)]) {
        [fm createFileAtPath:SthenoJBRootPath(kLogPath) contents:nil attributes:nil];
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:SthenoJBRootPath(kLogPath)];
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

#pragma mark - 环境快照（0x419c）

// 读取主模块（SpringBoard 侧）写出的前台应用快照。
// 文件不存在 / 解析失败时保持上一次的值。
static void SthenoReloadFrontmostSnapshot(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:SthenoJBRootPath(kFrontmostJSON)]) return;

    NSData *data = [NSData dataWithContentsOfFile:SthenoJBRootPath(kFrontmostJSON) options:0 error:nil];
    if (data == nil) return;

    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([object isKindOfClass:[NSDictionary class]]) {
        gFrontmostSnapshot = object;
    }
}

#pragma mark - 开关（0x4304）

static void SthenoReloadKeyboardPreference(void) {
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:SthenoJBRootPath(kPreferencePlist)];
    if (preferences == nil) return;

    NSNumber *value = preferences[@"169"];
    if (value == nil) return;

    gKeyboardOverrideEnabled = [value boolValue];
}

#pragma mark - 白名单（0x43b4）

// bundleID 是否在 plist 的 "Apps" 数组里（由主模块维护的「浮窗应用」列表）
static BOOL SthenoIsBundleInFloatingList(NSString *bundleID) {
    if (bundleID == nil) return NO;

    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:SthenoJBRootPath(kPreferencePlist)];
    if (preferences == nil) return NO;

    NSArray *apps = preferences[@"Apps"];
    if (apps == nil) return NO;

    return [apps containsObject:bundleID];
}

#pragma mark - Hooks

static id (*orig_activeInstance)(id, SEL);

// 0x46b4 — +[UIKeyboardImpl activeInstance]：每次取实例前刷新环境快照
static id hook_activeInstance(id self, SEL _cmd) {
    SthenoReloadFrontmostSnapshot();
    return orig_activeInstance(self, _cmd);
}

static id (*orig_remoteKeyboardWindowForScreen)(id, SEL, id, BOOL);

// 0x46fc — 强制键盘宿主窗口使用「长边正方形」尺寸，让浮窗键盘不被裁切
static id hook_remoteKeyboardWindowForScreen(id self, SEL _cmd, UIScreen *screen, BOOL create) {
    id window = orig_remoteKeyboardWindowForScreen(self, _cmd, screen, create);

    BOOL shouldAdjust = (gKeyboardOverrideEnabled || window != nil) && SthenoIsBundleInFloatingList(gFrontmostBundleID);
    if (!shouldAdjust || window == nil) return window;

    gAdjustingKeyboardWindow = NO;
    UIScreen *mainScreen = [UIScreen mainScreen];
    CGSize screenSize = [mainScreen bounds].size;

    CGFloat longSide = MAX(screenSize.width, screenSize.height);
    CGFloat shortSide = MIN(screenSize.width, screenSize.height);
    // 取长边为边长、以屏幕中心对齐，得到一个正方形宿主区域
    CGRect hostFrame = CGRectMake(0, (longSide - shortSide) * -0.5, longSide, longSide);

    [window setFrame:hostFrame];
    gAdjustingKeyboardWindow = YES;
    return window;
}

static id (*orig_initWithSession)(id, SEL, id, id);

// 0x482c — 给键盘宿主 UIScene 打标记，后续据此识别「浮窗键盘」
static id hook_initWithSession(id self, SEL _cmd, id session, id options) {
    SthenoReloadKeyboardPreference();
    return orig_initWithSession(self, _cmd, session, options);
}

static id (*orig_boundsForInterfaceOrientation)(id, SEL, NSInteger);

// 0x4880 — 键盘尺寸计算入口（hook 体在 0x4880 之后，几何分支未逐指令还原）
static id hook_boundsForInterfaceOrientation(id self, SEL _cmd, NSInteger orientation) {
    if (gKeyboardOverrideEnabled) {
        SthenoReloadFrontmostSnapshot();
    }
    return orig_boundsForInterfaceOrientation(self, _cmd, orientation);
}

#pragma mark - Darwin 通知（0x4498 / 0x44bc）

// 0x44bc — 主模块 post "com.nx.SthenoKeyboard" 后触发：重读环境并刷新键盘
static void SthenoKeyboardNotifyHandler(int token) {
    SthenoReloadKeyboardPreference();
    SthenoReloadFrontmostSnapshot();

    id keyboardWindow = orig_remoteKeyboardWindowForScreen(objc_getClass("UIRemoteKeyboardWindow"),
                                                           @selector(remoteKeyboardWindowForScreen:create:),
                                                           [UIScreen mainScreen], NO);
    if (keyboardWindow != nil) {
        [keyboardWindow setNeedsLayout];
    }
}

#pragma mark - 初始化（0x4544）

%ctor {
    SthenoReloadKeyboardPreference();
    SthenoReloadFrontmostSnapshot();

    if (!gKeyboardOverrideEnabled) {
        // 开关关闭时仍安装 hook，但运行时短路，避免用户切换后需要重启进程
        SthenoLog(@"SthenoKeyboard loaded (disabled)");
    }

    Class keyboardImpl = objc_getClass("UIKeyboardImpl");
    MSHookMessageEx(object_getClass(keyboardImpl), @selector(activeInstance),
                    (IMP)&hook_activeInstance, (IMP *)&orig_activeInstance);

    Class keyboardWindow = objc_getClass("UIRemoteKeyboardWindow");
    MSHookMessageEx(object_getClass(keyboardWindow), @selector(remoteKeyboardWindowForScreen:create:),
                    (IMP)&hook_remoteKeyboardWindowForScreen, (IMP *)&orig_remoteKeyboardWindowForScreen);

    Class scene = objc_getClass("UIScene");
    MSHookMessageEx(scene, @selector(initWithSession:connectionOptions:),
                    (IMP)&hook_initWithSession, (IMP *)&orig_initWithSession);

    Class keyboardImpl2 = objc_getClass("UIKeyboardImpl");
    MSHookMessageEx(keyboardImpl2, @selector(_boundsForInterfaceOrientation:),
                    (IMP)&hook_boundsForInterfaceOrientation, (IMP *)&orig_boundsForInterfaceOrientation);

    int token = 0;
    notify_register_dispatch(kDarwinNotify.UTF8String, &token, dispatch_get_main_queue(), ^(int t) {
        SthenoKeyboardNotifyHandler(t);
    });
}
