// SthenoCamera.xm
// 注入目标：mediaserverd（见 SthenoCamera.plist）
//
// 还原置信度：高。整个 dylib 只有 0x17c 字节代码、2 个函数 + 1 个 ctor，
// 指令级已逐条核对（见 RESTORATION_REPORT.md §6.1）。
//
// 作用：当设置项 "Camera" 为真时，吞掉
//   -[FigCaptureClientSessionMonitor _updateClientStateCondition:newValue:]
// 使相机客户端状态不再被系统回收，从而让浮窗里的相机/扫码页持续预览。

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../Support/SthenoPaths.h"
#import "../Support/SthenoMethodABI.h"

static BOOL gCameraKeepAlive = NO;   // 对应 __common+0x0（文件偏移 0xc028）

// 0x4000 — 每次调用都重新读取 plist，作者故意不做缓存，
// 这样在设置里改开关后无需 respring 即可生效。
static void SthenoReloadCameraPreference(void) {
    NSString *plistPath = SthenoJBRootPath(@"/var/mobile/Library/Preferences/com.nx.stheno.plist");
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (preferences == nil) return;

    NSNumber *cameraValue = preferences[@"Camera"];
    if (cameraValue == nil) return;

    gCameraKeepAlive = [cameraValue boolValue];
}

static void (*orig_updateClientStateCondition)(id, SEL, void *, id);

// 0x4100
static void hook_updateClientStateCondition(id self, SEL _cmd, void *condition, id newValue) {
    id retainedValue = newValue;  // ARC owns the strong local for this call.
    SthenoReloadCameraPreference();

    // 注意：只有"开启"时才跳过原实现；关闭时完全透传。
    if (!gCameraKeepAlive) {
        orig_updateClientStateCondition(self, _cmd, condition, retainedValue);
    }

}

// 0x40b0 — %ctor
%ctor {
    Class monitorClass = objc_getClass("FigCaptureClientSessionMonitor");
    const char *args[] = { @encode(id), @encode(SEL), @encode(void *), @encode(id) };
    Method method = class_getInstanceMethod(monitorClass, @selector(_updateClientStateCondition:newValue:));
    if (!SthenoMethodMatchesTypes(method, @encode(void), args, 4)) return;
    MSHookMessageEx(monitorClass,
                    @selector(_updateClientStateCondition:newValue:),
                    (IMP)&hook_updateClientStateCondition,
                    (IMP *)&orig_updateClientStateCondition);
}
