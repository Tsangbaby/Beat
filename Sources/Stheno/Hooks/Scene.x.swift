// Hooks/Scene.swift — 场景/生命周期层 9 个 hook
//
// 这一层决定"浮窗里的 App 为什么不会被系统杀掉/挂起"，
// 也就是整个插件最关键的"保活"逻辑。三处闸门：
//   ① _createSceneWithDefinition…  —— 造场景（0x77494）
//   ② _setDeactivationReasons…     —— 清挂起原因（0x74c54，2676 字节，最大的一处）
//   ③ deactivateWithTransitionContext: / _killForReason…  —— 退出与杀进程（0x1572c / 0x6006c）


// ⚠️ 重要：本文件的 target 类与 selector 是【确证】的，但**函数体是示意实现**。
//    原二进制里的真 body 位于报告 §3.2 给出的地址，尚未逐指令还原。
//    这里的代码只保证"语义方向正确、能编译"，不保证与原版行为一致。
//    补全方式见 RESTORATION_REPORT.md §9.4。

import Orion
import UIKit

// MARK: - SBMainDisplaySceneManagerHook

/// 0x748b4（60 字节）：只做透传 + 记录，属于"观察点"
/// 说明作者在这里拿场景的最新 settings（浮窗插入时要读/改 frame、level、deactivation）
class SBMainDisplaySceneManagerHook: ClassHook<SBMainDisplaySceneManager> {
    typealias Group = SthenoGroup

    func _scene(_ scene: FBScene, interceptUpdateWithNewSettings settings: AnyObject) {
        SthenoController.shared.sceneSettingsInterceptor.record(scene: scene, settings: settings)
        orig._scene(scene, interceptUpdateWithNewSettings: settings)
    }
}

// MARK: - UIApplicationSceneDeactivationManagerHook

/// 0x74c54（2676 字节）—— 保活核心
/// 系统在 App 退到后台时会给 scene 加 deactivation reason（导致挂起）。
/// 这里把"属于浮窗的 scene"的 reasons 过滤掉，让它保持前台态。
class UIApplicationSceneDeactivationManagerHook: ClassHook<UIApplicationSceneDeactivationManager> {
    typealias Group = SthenoGroup

    @objc(_setDeactivationReasons:onScene:withSettings:reason:)
    func _setDeactivationReasons(_ reasons: UInt64,
                                 on scene: UIScene,
                                 withSettings settings: AnyObject,
                                 reason: String) {
        // 判断该 scene 是否由我们托管（Environment.floatings 里的 manager.scene）
        let managed = Environment.shared.floatings.contains { manager in
            (manager.scene as AnyObject?) === scene
        }

        if managed && Environment.shared.ssMask.isEmpty == false {
            // 保留"必须挂起"的原因（如系统级），其余清掉
            let filtered = reasons & ~SthenoController.shared.suspendableReasonMask
            orig._setDeactivationReasons(filtered, on: scene, withSettings: settings, reason: reason)
            return
        }

        orig._setDeactivationReasons(reasons, on: scene, withSettings: settings, reason: reason)
    }
}

// MARK: - FBSceneHook

/// 0x1572c（deactivateWithTransitionContext:，516 字节，读 clientProcess）
/// 0x6006c（_killForReason:andReport:withDescription:completion:，512 字节）
class FBSceneHook: ClassHook<FBScene> {
    typealias Group = SthenoGroup

    @objc(deactivateWithTransitionContext:)
    func deactivate(withTransitionContext context: AnyObject?) {
        let managed = Environment.shared.floatings.contains { $0.id == target.identifier }
        if managed {
            // 浮窗关闭时才真正 deactivate；其余情况吞掉
            if SthenoController.shared.isClosing(managerID: target.identifier) {
                orig.deactivate(withTransitionContext: context)
            }
            return
        }
        orig.deactivate(withTransitionContext: context)
    }

    func _killForReason(_ reason: Int64, andReport report: Bool,
                        withDescription description: String?,
                        completion: AnyObject?) {
        // Owner/invoke ABI is unproven. The backend rejects this selector on
        // FBScene; never synthesize a result for an unknown system callback.
        orig._killForReason(reason, andReport: report, withDescription: description, completion: completion)
    }
}

// MARK: - BNContentViewControllerHook

/// 0x75fec（644 字节）：横幅/通知的呈现入口
/// 开启"消息通知以浮窗打开"（字符串 0x…"消息通知以浮窗打开。"）时，
/// 把 presentable 转成浮窗宿主，而不是全屏横幅。
class BNContentViewControllerHook: ClassHook<BNContentViewController> {
    typealias Group = SthenoGroup

    @objc(presentPresentable:withOptions:userInfo:)
    func present(_ presentable: AnyObject, withOptions options: UInt, userInfo: [AnyHashable: Any]?) {
        if Environment.shared.ssMask.contains(.voip) || Environment.shared.showEdgeBar {
            if SthenoController.shared.presentAsFloating(presentable: presentable) {
                return
            }
        }
        orig.present(presentable, withOptions: options, userInfo: userInfo)
    }
}

// MARK: - SBDeviceApplicationSceneViewControllerHook

/// 0x765b8（520 字节）：每个 App 的宿主控制器 viewDidLoad
/// 这里拿到 App 的根视图，塞进浮窗容器；同时设置 clip/corner。
class SBDeviceApplicationSceneViewControllerHook: ClassHook<SBDeviceApplicationSceneViewController> {
    typealias Group = SthenoGroup

    func viewDidLoad() {
        orig.viewDidLoad()
        SthenoController.shared.attachSceneViewIfNeeded(controller: target)
    }
}

// MARK: - SBApplicationControllerHook

/// 0x76cc4（28 字节）：卸载应用 → 清掉回收站里的残留浮窗
class SBApplicationControllerHook: ClassHook<SBApplicationController> {
    typealias Group = SthenoGroup

    func uninstallApplication(_ application: SBApplication) {
        Environment.shared.trash.removeAll { $0.manager.id == application.bundleIdentifier }
        orig.uninstallApplication(application)
    }
}

// MARK: - FBSceneManagerHook

/// 0x77494（96 字节）：造场景
/// 分屏（medusa）需要第二块 scene，这里把 definition 复制一份并标记为副场景。
class FBSceneManagerHook: ClassHook<FBSceneManager> {
    typealias Group = SthenoGroup

    func _createSceneWithDefinition(_ definition: AnyObject,
                                    settings: AnyObject,
                                    initialClientSettings: AnyObject,
                                    transitionContext: AnyObject,
                                    fromRemnant remnant: AnyObject?,
                                    usingClientProvider provider: AnyObject,
                                    completion: AnyObject?) -> AnyObject? {
        // Opaque object/block pointer only: no invented block invocation ABI.
        return orig._createSceneWithDefinition(definition,
                                       settings: settings,
                                       initialClientSettings: initialClientSettings,
                                       transitionContext: transitionContext,
                                       fromRemnant: remnant,
                                       usingClientProvider: provider,
                                       completion: completion)
    }
}

// MARK: - FBSystemServiceHook

/// 0x77c7c（360 字节）：App 启动入口
/// 浮窗启动时把 `source`/`originalSource` 改写，让系统认为是前台启动（避免被限流）
class FBSystemServiceHook: ClassHook<FBSystemService> {
    typealias Group = SthenoGroup

    func _activateBundleID(_ bundleID: String,
                           requestID: String,
                           isTrusted: Bool,
                           options: [AnyHashable: Any],
                           source: AnyObject?,
                           originalSource: AnyObject?,
                           withResult result: AnyObject?) {
        var options = options
        if Environment.shared.floatings.contains(where: { $0.id == bundleID }) {
            options["STHENO_FLOATING"] = true
        }
        orig._activateBundleID(bundleID,
                              requestID: requestID,
                              isTrusted: isTrusted,
                              options: options,
                              source: source,
                              originalSource: originalSource,
                              withResult: result)
    }
}

// MARK: - UIStatusBarWindowHook

/// 0x78810（88 字节）：状态栏窗口
/// 浮窗铺满时把状态栏窗口提到最上层，否则会被浮窗遮住。
class UIStatusBarWindowHook: ClassHook<UIStatusBarWindow> {
    typealias Group = SthenoGroup

    func initWithFrame(_ frame: CGRect) -> UIStatusBarWindow? {
        guard let window = orig.initWithFrame(frame) else { return nil }
        window.windowLevel = UIWindow.Level.statusBar + 1
        return window
    }
}
