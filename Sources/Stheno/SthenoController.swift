// SthenoController.swift — Tweak 入口 + 全局协调器
//
// 二进制里 `_TtC6Stheno16SthenoController`（0x86e50 类型描述符，0 个 ObjC 字段）
// 就是 Orion 的 Tweak 实现体；它同时承担了"全局单例协调器"的角色：
//   * 0x765b8 之后的一系列 glue 都会回读它的状态
//   * 0x10058（SthenoWindow 创建）、0x5b2f8（手势状态推进）、0x5d9cc（z 序参与器）
//     都通过它拿 Environment / DeviceInfo / ReflectManager
//
// 注意：原始源码的方法名已被剥离，下面的方法名是按调用点语义命名的，
// 每个方法都标注了对应实现地址，便于对照。

import Orion
import UIKit
import SwiftUI
import Combine

final class SthenoController {
    // ---- 全局单例（对应二进制里 __data 的 swift_once 惰性初始化）----
    static let shared = SthenoController()

    let environment = Environment.shared
    let deviceInfo = DeviceInfo()
    let gesture = GestureCoordinator()
    let sceneSettingsInterceptor = SceneSettingsInterceptor()

    /// 窗口：0x10058 创建，_UIHostingView<Container> 承载 SwiftUI 根视图
    private lazy var overlay = SthenoOverlayPresenter<Container>(content: { Container() })
    var window: SthenoWindow? { overlay.window }
    private var bootstrapped = false
    private var startupSubscriptions = Set<AnyCancellable>()

    var isLongPressing = false
    var isClosingSet = Set<String>()

    private init() {}

    // MARK: - 启动（0x715c0 → 0x10058 → 0x1027c）

    func bootstrap() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.bootstrap() }
            return
        }
        guard !bootstrapped else {
            refreshOverlayPresentation()
            return
        }
        bootstrapped = true
        environment.load()
        deviceInfo.refreshScreenMetrics()
        refreshFrontmost()

        // receive(on:) observes the completed mutation, not objectWillChange's
        // old state. No timer, guessed startup delay, or permanent nil-scene latch.
        Publishers.Merge(environment.objectWillChange, deviceInfo.$state.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshOverlayPresentation() }
            .store(in: &startupSubscriptions)
        NotificationCenter.default.publisher(for: UIScene.didActivateNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshOverlayPresentation() }
            .store(in: &startupSubscriptions)
        refreshOverlayPresentation()

        // 0x4d7e8：把环境变化广播给 SthenoKeyboard
        environment.postEnvironmentChange()
    }

    private func refreshOverlayPresentation() {
        // Display preferences alone must never publish a modal window at boot.
        let presented = deviceInfo.state != .ended || !environment.floatings.isEmpty || environment.invalid
        overlay.update(presented: presented)
    }

    // MARK: - 前台应用（0x71488 / 0x4f8e4）

    func refreshFrontmost() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let foreground = scenes.first { $0.activationState == .foregroundActive }
        let bundleID = foreground?.activationState == .foregroundActive
            ? (foreground?.keyWindow?.windowScene?.session.persistentIdentifier ?? "")
            : ""

        deviceInfo.frontmost = bundleID
        environment.persistFrontmost(bundleID: bundleID, sceneID: foreground?.session.persistentIdentifier)
    }

    // MARK: - 浮窗生命周期（0x72088 / 0x71a54 / 0x77c7c）

    func openFloating(bundleID: String) {
        if let existing = environment.floatings.first(where: { $0.id == bundleID }) {
            existing.launching = true
            return
        }
        let manager = ReflectManager(id: bundleID, scene: nil)
        manager.launching = true
        environment.floatings.append(manager)

        // 走系统启动链路，让 FBSystemService 那边的 hook 打上标记
        // 注意：SBApplication 没有公开的 initWithBundleIdentifier:，
        // 这里通过 SBApplicationController 取实例（私有 API，签名待实机校验）。
        if let app = SBApplicationController.sharedInstance().application(withBundleIdentifier: bundleID) {
            app.launchSuspended()
        }
    }

    func close(manager: ReflectManager, animated: Bool) {
        isClosingSet.insert(manager.id)
        environment.floatings.removeAll { $0 === manager }
        isClosingSet.remove(manager.id)
        environment.persist()
    }

    func isClosing(managerID: String) -> Bool {
        isClosingSet.contains(managerID)
    }

    func bundleIdentifier(ofIconView iconView: AnyObject?) -> String? {
        // 0x72088 里通过 Orion 的 Ivars 动态成员读 SBIconView 的 icon → applicationBundleID。
        // 这里改成强类型访问（等价且能通过编译）。
        (iconView as? SBIconView)?.icon?.applicationBundleID
    }

    // MARK: - 场景视图挂载（0x765b8）

    func attachSceneViewIfNeeded(controller: UIViewController) {
        guard let manager = environment.floatings.first(where: { $0.cover == nil }) else { return }
        manager.views.append(controller.view)
        controller.view.clipsToBounds = true
        controller.view.layer.cornerRadius = manager.finalCardCorner
    }

    // MARK: - 横幅转浮窗（0x75fec）

    func presentAsFloating(presentable: AnyObject) -> Bool {
        // 0x75fec 只做参数搬运后调 initializeStorage；真正的转浮窗发生在
        // BNContentViewController 的宿主替换。此处作为策略开关。
        guard environment.showEdgeBar else { return false }
        return false
    }

    // MARK: - z 序（0x5d9cc）

    func updateZStack(_ participant: SBFZStackParticipant) {
        // ownsHomeGesture 决定 Home 手势归谁；有浮窗时必须由我们持有
        if !environment.floatings.isEmpty {
            participant.ownsHomeGesture = true
        }
    }

    /// 0x74c54 里用来过滤 reasons 的掩码
    var suspendableReasonMask: UInt64 { 0 }
}

// MARK: - 手势协调器
//
// 0x5b2f8（5376 字节）是整份二进制里最大的业务函数，它就是手势状态机：
// 读 Date/timeIntervalSinceNow 做长按判定、写 PanGestureState、驱动 RingState 与
// ReflectManager 的几何。下面按其分支结构重建。

final class GestureCoordinator {

    private var beganAt = Date()
    private var startLocation: CGPoint = .zero

    func began(touches: Set<UITouch>, event: UIEvent?) {
        beganAt = Date()
        startLocation = touches.first?.location(in: nil) ?? .zero
        SthenoController.shared.deviceInfo.longPress = false
        SthenoController.shared.deviceInfo.state = .began
    }

    func moved(touches: Set<UITouch>, event: UIEvent?) {
        // 0x5b2f8：`Date().timeIntervalSinceNow` 与阈值比较 → 长按
        let elapsed = -beganAt.timeIntervalSinceNow
        if elapsed > 0.35 {
            SthenoController.shared.deviceInfo.longPress = true
        }
        SthenoController.shared.deviceInfo.state = .changed
    }

    func ended(touches: Set<UITouch>, event: UIEvent?) {
        SthenoController.shared.deviceInfo.state = .ended
    }

    func cancelled() {
        SthenoController.shared.deviceInfo.state = .ended
        SthenoController.shared.deviceInfo.longPress = false
    }

    /// 从底部上滑：0x73d84 的 `_handleClickAndDragHomeGesture:`
    func homeSwipe(translation: CGPoint) {
        guard let manager = Environment.shared.floatings.last else { return }
        // 上滑 → 把浮窗压回图标（scaleToIcon）
        manager.scaleToIcon = translation.y < -60
    }

    /// 卡片堆拖拽：0x73d84 的 `_handleDeckSwitcherPanGesture:`
    func deckPan(translation: CGPoint, velocity: CGPoint) {
        guard let manager = Environment.shared.floatings.last else { return }
        manager.offset = CGSize(width: manager.offset.width + translation.x,
                                height: manager.offset.height + translation.y)
    }
}

// MARK: - 场景 settings 拦截记录

final class SceneSettingsInterceptor {
    private(set) var lastScene: AnyObject?
    private(set) var lastSettings: AnyObject?

    func record(scene: AnyObject, settings: AnyObject) {
        lastScene = scene
        lastSettings = settings
    }
}
