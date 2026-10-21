// DeviceInfo.swift — 设备/运行时信息
//
// 证据：
//   * 类型 Stheno.DeviceInfo，13 字段（fieldmd @0x88164）
//   * 0x4c070  mainScreen + valueForKey:@"_displayCornerRadius"   → cornerRadius
//   * 0x1374c  UIScreen.mainScreen.scale
//   * 0x2b784  读 Info.plist 的 UISupportedInterfaceOrientations(～iphone/～ipad)
//              + enumerateScenesWithBlock: → 计算 supportedLaunchOrientation
//   * 0x59bb4  UIApplication.shared.connectedScenes / statusBarManager.statusBarFrame
//   * 0x4e814  @AppStorage("BaseKeyboardOffset")
//   * 0x51d0/0x5a6d0  监听 UIKeyboardDidShow/Hide 通知维护 _keyboardHeight
//
// 作用：给所有几何运算提供「一块屏幕的基准」，浮窗的 frame/scale 都以它为准。

import Foundation
import UIKit
import SwiftUI
import Combine

public final class DeviceInfo: ObservableObject {

    // MARK: - 应用清单

    /// 元数据里是 `_key`（String）与 `_apps`
    @Published public var key: String = ""
    @Published public var apps: [AppSearcher.Snapshot] = []

    // MARK: - 键盘

    /// @AppStorage("BaseKeyboardOffset")（0x80460 / 0x4e814）
    @AppStorage("BaseKeyboardOffset") public var baseKeyboardOffset: Double = 0
    @Published public var keyboardHeight: CGFloat = 0
    public var baseKeyboardOffsetLast: Double = 0

    // MARK: - 屏幕

    @Published public var unlocked: Bool = true
    @Published public var orientation: UIInterfaceOrientation = .portrait
    @Published public var managers: [ReflectManager] = []
    /// 0x4c070：`[[UIScreen mainScreen] valueForKey:@"_displayCornerRadius"]`
    @Published public var cornerRadius: CGFloat = 0
    /// 当前最前台应用的 bundle id（写入 /tmp/stheno_frontmost.json）
    @Published public var frontmost: String = ""

    // MARK: - 手势镜像
    //
    // 这三个字段与 ReflectManager / RingState 同名，说明 DeviceInfo 里保存了
    // 「最后一次手势」的全局副本，供 SwiftUI 视图在管理器切换时保持连续性。
    public var longPress: Bool = false
    public var subGestureType: PanGestureSubType = .none
    @Published public var state: PanGestureState = .ended

    private var cancellables = Set<AnyCancellable>()

    public init() {
        refreshScreenMetrics()
        observeKeyboard()
        observeOrientation()
    }

    // MARK: - 屏幕度量

    public func refreshScreenMetrics() {
        let screen = UIScreen.main
        if screen.responds(to: Selector(("_displayCornerRadius"))) {
            let value = screen.value(forKey: "_displayCornerRadius") as? NSNumber
            cornerRadius = CGFloat(value?.doubleValue ?? 0)
        }
        orientation = currentInterfaceOrientation()
    }

    /// 0x63f4c / 0x59bb4：从 connectedScenes 里挑出前台 UIWindowScene
    public func currentInterfaceOrientation() -> UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let foreground = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return foreground?.interfaceOrientation ?? .portrait
    }

    /// 0x2b784 —— 从 Info.plist 读取允许的启动方向
    public func supportedLaunchOrientation(for bundle: Bundle = .main) -> UIInterfaceOrientationMask {
        let info = bundle.infoDictionary ?? [:]
        let keys = ["UISupportedInterfaceOrientations~iphone",
                    "UISupportedInterfaceOrientations~ipad",
                    "UISupportedInterfaceOrientations"]
        for key in keys {
            guard let values = info[key] as? [String] else { continue }
            var mask: UIInterfaceOrientationMask = []
            for value in values {
                switch value {
                case "UIInterfaceOrientationPortrait": mask.insert(.portrait)
                case "UIInterfaceOrientationPortraitUpsideDown": mask.insert(.portraitUpsideDown)
                case "UIInterfaceOrientationLandscapeLeft": mask.insert(.landscapeLeft)
                case "UIInterfaceOrientationLandscapeRight": mask.insert(.landscapeRight)
                default: break
                }
            }
            if !mask.isEmpty { return mask }
        }
        return .all
    }

    // MARK: - 键盘

    private func observeKeyboard() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIResponder.keyboardDidShowNotification,
                           object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            self.baseKeyboardOffsetLast = self.baseKeyboardOffset
            self.keyboardHeight = frame?.height ?? 0
            Environment.shared.floatingsHasKeyboard = true
        }
        center.addObserver(forName: UIResponder.keyboardDidHideNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.keyboardHeight = 0
            Environment.shared.floatingsHasKeyboard = false
        }
    }

    // MARK: - 方向

    private func observeOrientation() {
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.orientation = self?.currentInterfaceOrientation() ?? .portrait
        }
    }
}
