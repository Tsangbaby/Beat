// Hooks/Switcher.swift — 手势层 3 个 hook
//
// 这一组是"手感"的核心：作者没有去改系统手势识别器本身，
// 而是在三个层次上做拦截：
//   ① 识别器层  _SBFluidSwitcherPanGestureRecognizerHook.gestureRecognizer:shouldReceiveTouch:
//   ② 舌头层    SBGrabberTongueHook.touches*        （底部 Home 手势条）
//   ③ 管理器层  SBFluidSwitcherGestureManagerHook._handleClickAndDragHomeGesture: 等
// 见报告 §5.2 的三层拓扑图。


// ⚠️ 重要：本文件的 target 类与 selector 是【确证】的，但**函数体是示意实现**。
//    原二进制里的真 body 位于报告 §3.2 给出的地址，尚未逐指令还原。
//    这里的代码只保证"语义方向正确、能编译"，不保证与原版行为一致。
//    补全方式见 RESTORATION_REPORT.md §9.4。

import Orion
import UIKit

// MARK: - _SBFluidSwitcherPanGestureRecognizerHook

/// 目标类：_SBFluidSwitcherPanGestureRecognizer
/// 字段（fieldmd @0x88ba8）：`_handleClick: Bool` —— 该识别器是否被我们接管成"点击"
///
/// 实现：0x73444（shouldReceiveTouch，80 字节）
///      0x73d84 同一函数里也读了这套 selector（说明管理器层会回读识别器状态）
class _SBFluidSwitcherPanGestureRecognizerHook: ClassHook<UIPanGestureRecognizer> {
    typealias Group = SthenoGroup
    static var targetName: String { "SBFluidSwitcherPanGestureRecognizer" }

    /// 0x73444 —— 只在"边缘/环手势"应该生效的触摸上返回 true
    @objc(gestureRecognizer:shouldReceiveTouch:)
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let location = touch.location(in: nil)
        let screen = UIScreen.main.bounds

        // 命中左右边缘热区？→ 让系统识别器收不到，交给我们的 SwiftUI 手势
        let edgeWidth = Environment.shared.edgeWidth
        let leftZone = CGRect(x: 0, y: 0, width: edgeWidth, height: screen.height)
        let rightZone = CGRect(x: screen.width - edgeWidth, y: 0, width: edgeWidth, height: screen.height)

        if Environment.shared.fourEdge {
            if leftZone.contains(location) || rightZone.contains(location) { return false }
        } else if !Environment.shared.ringOnly {
            if leftZone.contains(location) || rightZone.contains(location) { return false }
        }

        return orig.gestureRecognizer(recognizer, shouldReceive: touch)
    }

    /// 属性 hook（`TB,N` 编码）—— 0x73d84 会设置它来把拖拽降级为点击
    func _handleClick() -> Bool {
        orig._handleClick()
    }
}

// MARK: - SBGrabberTongueHook

/// 目标类：SBGrabberTongue（底部 Home 指示条）
/// 实现：0x72b3c / 0x72c1c / 0x72dbc / 0x72ed4 —— 四个 touches* 都是转发，
///       只有 touchesCancelled 稍大（204 字节），负责复位手势状态。
class SBGrabberTongueHook: ClassHook<SBGrabberTongue> {
    typealias Group = SthenoGroup

    func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        SthenoController.shared.gesture.began(touches: touches, event: event)
        orig.touchesBegan(touches, with: event)
    }

    func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        SthenoController.shared.gesture.moved(touches: touches, event: event)
        orig.touchesMoved(touches, with: event)
    }

    func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        SthenoController.shared.gesture.ended(touches: touches, event: event)
        orig.touchesEnded(touches, with: event)
    }

    func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        SthenoController.shared.gesture.cancelled()
        orig.touchesCancelled(touches, with: event)
    }
}

// MARK: - SBFluidSwitcherGestureManagerHook

/// 目标类：SBFluidSwitcherGestureManager
/// 实现：0x73d84（1312 字节，同时引用 4 个 selector + zStackParticipantDidChange:）
///
/// 这是"多任务手势"的总闸：
///   * `_handleClickAndDragHomeGesture:`  —— 从底部上滑
///   * `_handleDeckSwitcherPanGesture:`   —— 卡片堆拖拽
///   * `zStackParticipantDidChange:`      —— z 序变化（浮窗层级）
///   * `gestureRecognizer:shouldReceiveTouch:` —— 回读识别器状态
class SBFluidSwitcherGestureManagerHook: ClassHook<SBFluidSwitcherGestureManager> {
    typealias Group = SthenoGroup

    /// SBFZStackParticipant 参与器：0x5d9cc 里读 `ownsHomeGesture` / `activationState`
    /// 并调用 `setState:`（枚举值为 SBFZStackParticipantState）
    func _handleClickAndDragHomeGesture(_ gesture: UIGestureRecognizer) {
        // 有浮窗时，Home 上滑不进入 App Switcher，而是把浮窗收起
        if !Environment.shared.floatings.isEmpty, let pan = gesture as? UIPanGestureRecognizer {
            SthenoController.shared.gesture.homeSwipe(translation: pan.translation(in: nil))
            return
        }
        orig._handleClickAndDragHomeGesture(gesture)
    }

    func _handleDeckSwitcherPanGesture(_ gesture: UIGestureRecognizer) {
        if !Environment.shared.floatings.isEmpty, let pan = gesture as? UIPanGestureRecognizer {
            SthenoController.shared.gesture.deckPan(translation: pan.translation(in: nil),
                                                 velocity: pan.velocity(in: nil))
            return
        }
        orig._handleDeckSwitcherPanGesture(gesture)
    }

    /// 浮窗插入后需要把 z 序参与器状态同步给系统，否则浮窗会被系统卡片盖住
    func zStackParticipantDidChange(_ participant: SBFZStackParticipant) {
        orig.zStackParticipantDidChange(participant)
        SthenoController.shared.updateZStack(participant)
    }
}
