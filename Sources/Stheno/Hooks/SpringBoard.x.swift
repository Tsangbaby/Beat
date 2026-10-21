// Hooks/SpringBoard.swift — 注入 SpringBoard 的 4 个 hook
//
// 每个 hook 的 selector 都是由 glue 里的 SELREF 唯一确定（见报告 §4 表格），
// 方法体按"该 selector 唯一引用的实现函数"的调用序列重建；
// 未逐指令还原的段落用 TODO(证据不足) 标出，不臆造。


// ⚠️ 重要：本文件的 target 类与 selector 是【确证】的，但**函数体是示意实现**。
//    原二进制里的真 body 位于报告 §3.2 给出的地址，尚未逐指令还原。
//    这里的代码只保证"语义方向正确、能编译"，不保证与原版行为一致。
//    补全方式见 RESTORATION_REPORT.md §9.4。

import Orion
import UIKit
import SwiftUI

// MARK: - UIApplicationHook

/// 目标类：UIApplication
/// 相关实现：0x30964（sendAction:to:from:forEvent:）
/// 作用：浮窗存在时，把落在浮窗之外的操作拦下来（先 resignFirstResponder 收键盘），
///       避免 UIKit 把事件派发到被盖住的宿主 App。
class UIApplicationHook: ClassHook<UIApplication> {
    typealias Group = SthenoGroup

    func sendAction(_ action: Selector, to target: AnyObject?, from sender: AnyObject?, forEvent event: UIEvent?) -> Bool {
        if !Environment.shared.floatings.isEmpty {
            // 0x30964 里先取 sharedApplication 再 resignFirstResponder
            UIApplication.shared.resignFirstResponder()
        }
        return orig.sendAction(action, to: target, from: sender, forEvent: event)
    }
}

// MARK: - SpringBoardHook

/// 目标类：SpringBoard
/// 实现函数：0x70d7c(noteActive…)、0x71488(frontDisplayDidChange:)、0x715c0(applicationDidFinishLaunching:)
class SpringBoardHook: ClassHook<SpringBoard> {
    typealias Group = SthenoGroup

    /// 0x715c0 —— 全插件起点：创建 SthenoWindow（承载 SwiftUI 根视图 Container）
    /// 证据：0x10058 里 setRootViewController / setWindowLevel / setBackgroundColor(clear)
    ///       以及 _UIHostingView<Container>（字符串 0x7f5a0）
    func applicationDidFinishLaunching(_ notification: Notification) {
        orig.applicationDidFinishLaunching(notification)

        SthenoController.shared.bootstrap()
    }

    /// 0x70d7c —— 系统方向即将变化：同步所有浮窗的几何
    @objc(noteActiveInterfaceOrientationWillChangeToOrientation:)
    func noteActiveInterfaceOrientationWillChange(to orientation: UIInterfaceOrientation) {
        orig.noteActiveInterfaceOrientationWillChange(to: orientation)

        SthenoController.shared.deviceInfo.orientation = orientation
        for manager in Environment.shared.floatings {
            manager.interfaceOrientation = orientation
        }
    }

    /// 0x71488 —— 前台显示变化：刷新「最前台应用」，并写入 /tmp 快照
    func frontDisplayDidChange(_ display: AnyObject?) {
        orig.frontDisplayDidChange(display)

        SthenoController.shared.refreshFrontmost()
    }
}

// MARK: - SBApplicationHook

/// 目标类：SBApplication
/// 实现函数：0x71a54（_didExitWithContext:）
/// 作用：应用退出时，如果它正跑在浮窗里，只关闭浮窗、不销毁场景。
class SBApplicationHook: ClassHook<SBApplication> {
    typealias Group = SthenoGroup

    func _didExitWithContext(_ context: AnyObject?) {
        let bundleID = target.bundleIdentifier
        if let manager = Environment.shared.floatings.first(where: { $0.id == bundleID }) {
            SthenoController.shared.close(manager: manager, animated: true)
        }
        orig._didExitWithContext(context)
    }
}

// MARK: - SBIconControllerHook

/// 目标类：SBIconController
/// 实现函数：0x72088（iconManager:launchIconForIconView:withActions:，2020 字节，全插件最大的 hook）
/// 作用：桌面点图标时的分流点 —— 决定"正常启动"还是"开成浮窗"。
///       0x72088 内引用了 UITouch（判断是否长按）、NSSet 桥接、以及
///       Orion 的 Ivars 动态成员访问（读 SpringBoard 私有 ivar）。
class SBIconControllerHook: ClassHook<SBIconController> {
    typealias Group = SthenoGroup

    @objc(iconManager:launchIconForIconView:withActions:)
    func iconManager(_ manager: AnyObject?, launchIconFor iconView: AnyObject?, withActions actions: NSSet?) -> Bool {
        // 长按 → 交给原实现（进入抖动/快捷菜单）
        if SthenoController.shared.isLongPressing {
            return orig.iconManager(manager, launchIconFor: iconView, withActions: actions)
        }

        // 单击 → 若开启"图标启动为浮窗"，则创建浮窗并吞掉原始启动
        guard Environment.shared.showRing || !Environment.shared.floatings.isEmpty else {
            return orig.iconManager(manager, launchIconFor: iconView, withActions: actions)
        }

        if let bundleID = SthenoController.shared.bundleIdentifier(ofIconView: iconView) {
            SthenoController.shared.openFloating(bundleID: bundleID)
            return true
        }

        return orig.iconManager(manager, launchIconFor: iconView, withActions: actions)
    }
}
