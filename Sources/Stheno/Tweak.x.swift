// Tweak.swift — Hook 分组声明
//
// 证据：
//   * 0x78d60（%ctor）→ Orion.Backends.Substrate
//   * 0x78f04 → DefaultTweak.activate(backend: .Substrate, hooks: [ …16 项… ])
//     16 项由 __bss+0x4c40 起连续写入（stp x8,x0,[x23,#0xf0/#0x100/#0x110]）
//   * __cstring 中依次出现 16 组
//       _TtCOC6Stheno<HookName>5_Glue8OrigType / 8SuprType
//     → 每个 hook 都有独立的 _Glue 命名空间（Orion 编译器插件产物）
//
// 结论：16 个 hook 同属一个分组，一次性激活。
// 入口类见 SthenoController.swift（对应二进制的 _TtC6Stheno16SthenoController）。

import Orion

/// 全局分组：与二进制中 DefaultTweak 的单一分组一致
struct SthenoGroup: HookGroup { }

/// Orion owns this short-lived entry; the coordinator remains one singleton.
struct SthenoEntry: Tweak {
    init() {
        SthenoGroup().activate()
    }
}

// 16 个 hook 的清单（顺序 = 二进制中 16 项数组的写入顺序
// = __cstring 里 _Glue 名称的出现顺序）：
//
//   1. UIApplicationHook
//   2. SpringBoardHook
//   3. SBApplicationHook
//   4. SBIconControllerHook
//   5. _SBFluidSwitcherPanGestureRecognizerHook
//   6. SBGrabberTongueHook
//   7. SBFluidSwitcherGestureManagerHook
//   8. SBMainDisplaySceneManagerHook
//   9. UIApplicationSceneDeactivationManagerHook
//  10. FBSceneHook
//  11. BNContentViewControllerHook
//  12. SBDeviceApplicationSceneViewControllerHook
//  13. SBApplicationControllerHook
//  14. FBSceneManagerHook
//  15. FBSystemServiceHook
//  16. UIStatusBarWindowHook
