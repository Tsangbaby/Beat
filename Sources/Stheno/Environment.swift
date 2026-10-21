// Environment.swift — 全局设置 / 运行时状态中枢
//
// 证据：
//   * 类型 Stheno.Environment，25 个字段（__swift5_fieldmd @0x8842c）
//   * 是 ObservableObject：字段成对出现 `_x`（@Published 存储）+ Combine 的
//     `Published._enclosingInstance(wrapped:storage:)` 调用（0x4df50 / 0x4e814 等）
//   * 0x4c438 读取 plist（NSFileManager.fileExists → 不存在则 0x21cbc 写默认）
//   * 0x58518 写盘（Data.write(to:options:) + AppStorage.wrappedValue setter）
//   * 0x4fe44 写 /tmp/stheno_env.json（供 mediaserverd / UIKit 进程读取）
//   * 0x4d7e8 post Darwin 通知 "com.nx.SthenoKeyboard"
//   * 三个显式 AppStorage key（字符串直接可见）：
//       "InterfaceOrientationMode"(0x80680) / "SystemServiceMask"(0x806a0) /
//       "BaseKeyboardOffset"(0x80460)
//
// 注意：其余字段的持久化 key 在二进制里没有对应字符串，说明作者不是逐项
// 写死 @AppStorage("…")，而是把整个 Environment 反射序列化成字典再落盘
// （这正是工程里内置一套 Swift 反射库的原因，见 Reflection/）。
// 因此下面用 `@Published` + `SettingsStore` 镜像的方式重建，语义等价。

import Foundation
import Combine
import SwiftUI

public final class Environment: ObservableObject {

    // MARK: - 单例
    //
    // 二进制中通过 __data 里的 swift_once 惰性单例持有（Environment 被大量
    // SwiftUI 视图以 @EnvironmentObject 注入，见各 View 的 `_env` 字段）。

    public static let shared = Environment()

    // MARK: - 浮窗运行时状态
    //
    // 这几个不是用户设置，而是「当前有哪些浮窗」的活状态；
    // 类型来自字段元数据 + ReflectManager/TrashAppState 的交叉引用。

    /// 0x80550 "floatingsHasKeyboard" —— 当前浮窗中是否有键盘
    @Published public var floatingsHasKeyboard: Bool = false
    /// 0x8057c "_floatings" —— 当前活动的浮窗管理器集合
    @Published public var floatings: [ReflectManager] = []
    /// 0x80587 "_dualManagers" —— 双窗口（分屏）配对的管理器
    @Published public var dualManagers: [ReflectManager] = []
    /// 0x80566 "_modify" —— 正在批量修改状态（抑制中间态刷新）
    public var modify: Bool = false
    /// 0x8056e "floatingsLast" —— 上一帧的浮窗集合，用于 diff
    public var floatingsLast: [ReflectManager] = []

    /// 0x80595 "trash" —— 已进入回收站的应用
    @Published public var trash: [TrashAppState] = []
    /// 0x805a0 "system" / 0x…"user" —— 系统应用 / 用户应用分组（AppSearcher 结果）
    @Published public var system: [AppSearcher.Snapshot] = []
    @Published public var user: [AppSearcher.Snapshot] = []
    /// 0x805a7 "previewIndex" —— 切换器当前预览页
    @Published public var previewIndex: Int = 0

    // MARK: - 手势区域设置

    /// 0x805b4 "_rightPecent" —— 右侧手势区宽度占比（0…1）
    @Published public var rightPecent: Double = 0.12
    /// 0x805c1 "_leftPecent"
    @Published public var leftPecent: Double = 0.12
    /// 0x805cd "_edgeWidth" —— 边缘判定宽度（pt）
    @Published public var edgeWidth: Double = 22
    /// 0x805e0 "_interfaceOrientationMode" —— 屏幕方向策略
    @Published public var interfaceOrientationMode: InterfaceOrientationMode = .follow
    /// 0x805fa "_URLScheme" —— 允许 URL Scheme 以浮窗打开
    @Published public var URLScheme: Bool = false
    /// 0x80605 "_ringOnly" —— 仅用手势环（不做边缘拖动）
    @Published public var ringOnly: Bool = false
    /// 0x8060f "_ssMask" —— 系统服务掩码（哪些服务随浮窗挂起/保活）
    @Published public var ssMask: SystemServiceMask = []
    /// 0x80617 "_fourEdge" —— 四边都可触发
    @Published public var fourEdge: Bool = false
    /// 0x80621 "_camera" —— 相机保活（对应 SthenoCamera 读的 "Camera"）
    @Published public var camera: Bool = false
    /// 0x80629 "_effectEdge" —— 边缘视觉效果
    @Published public var effectEdge: EffectEdge = .none
    /// 0x80635 "_synchronize" —— 单/多窗口状态同步
    @Published public var synchronize: Bool = false
    /// 0x80642 "__169" —— 对应 plist 键 "169"，SthenoKeyboard 读它
    @Published public var _169: Bool = false

    // MARK: - 面板显示开关

    /// 0x80648 "_showEdgeBar"
    @Published public var showEdgeBar: Bool = true
    /// 0x80655 "_invalid" —— 授权失效提示
    @Published public var invalid: Bool = false
    /// 0x8065e "_showRing"
    @Published public var showRing: Bool = true
    /// 0x80668 "_showLicense"
    @Published public var showLicense: Bool = false

    // MARK: - 生命周期

    private var cancellables = Set<AnyCancellable>()

    private init() {
        load()
        // 任一设置变化 → 落盘 + 通知子进程（0x58518 / 0x4d7e8 的组合行为）
        objectWillChange
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.persist()
                self?.postEnvironmentChange()
            }
            .store(in: &cancellables)
    }

    // MARK: - 持久化

    /// 0x4c438
    public func load() {
        let path = jbroot(SthenoPath.preferences)
        guard FileManager.default.fileExists(atPath: path),
              let dictionary = NSDictionary(contentsOfFile: path) as? [String: Any]
        else {
            // 0x21cbc：文件不存在 → 写入一份默认值
            persist()
            return
        }

        if let value = dictionary["Camera"] as? NSNumber { camera = value.boolValue }
        if let value = dictionary["169"] as? NSNumber { _169 = value.boolValue }
        if let value = dictionary["InterfaceOrientationMode"] as? NSNumber,
           let mode = InterfaceOrientationMode(rawValue: value.intValue) { interfaceOrientationMode = mode }
        if let value = dictionary["SystemServiceMask"] as? NSNumber { ssMask = SystemServiceMask(rawValue: value.intValue) }
        if let value = dictionary["rightPecent"] as? NSNumber { rightPecent = value.doubleValue }
        if let value = dictionary["leftPecent"] as? NSNumber { leftPecent = value.doubleValue }
        if let value = dictionary["edgeWidth"] as? NSNumber { edgeWidth = value.doubleValue }
        if let value = dictionary["URLScheme"] as? NSNumber { URLScheme = value.boolValue }
        if let value = dictionary["ringOnly"] as? NSNumber { ringOnly = value.boolValue }
        if let value = dictionary["fourEdge"] as? NSNumber { fourEdge = value.boolValue }
        if let value = dictionary["synchronize"] as? NSNumber { synchronize = value.boolValue }
        if let value = dictionary["showEdgeBar"] as? NSNumber { showEdgeBar = value.boolValue }
        if let value = dictionary["showRing"] as? NSNumber { showRing = value.boolValue }
        if let value = dictionary["showLicense"] as? NSNumber { showLicense = value.boolValue }
    }

    /// 0x58518 / 0x4fe44
    public func persist() {
        // 1) 设置 plist（供 SthenoCamera / SthenoKeyboard 读取）
        let dictionary: [String: Any] = [
            "Camera": camera,
            "169": _169,
            "InterfaceOrientationMode": interfaceOrientationMode.rawValue,
            "SystemServiceMask": ssMask.rawValue,
            "rightPecent": rightPecent,
            "leftPecent": leftPecent,
            "edgeWidth": edgeWidth,
            "URLScheme": URLScheme,
            "ringOnly": ringOnly,
            "fourEdge": fourEdge,
            "synchronize": synchronize,
            "showEdgeBar": showEdgeBar,
            "showRing": showRing,
            "showLicense": showLicense,
            "Apps": floatings.compactMap { $0.id },
        ]
        (dictionary as NSDictionary).write(toFile: jbroot(SthenoPath.preferences), atomically: true)

        // 2) 运行时快照 JSON（浮窗几何等，子进程只读这一份）
        let dump: [String: Any] = [
            "floatingsHasKeyboard": floatingsHasKeyboard,
            "previewIndex": previewIndex,
            "floatings": floatings.map { $0.snapshot() },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dump, options: []) {
            try? data.write(to: URL(fileURLWithPath: jbroot(SthenoPath.environmentDump)))
        }
    }

    /// 0x4f8e4 —— 单独写「前台应用」快照，SthenoKeyboard 用它决定是否接管键盘
    public func persistFrontmost(bundleID: String, sceneID: String?) {
        var payload: [String: Any] = ["bundleIdentifier": bundleID]
        if let sceneID { payload["sceneIdentifier"] = sceneID }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []) {
            try? data.write(to: URL(fileURLWithPath: jbroot(SthenoPath.frontmostDump)))
        }
    }

    /// 0x4d7e8 —— CFNotificationCenterGetDarwinNotifyCenter + Post
    public func postEnvironmentChange() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(SthenoNotification.keyboard as CFString),
            nil, nil, true
        )
    }
}

// MARK: - 枚举（值语义来自字段名与取值点）

/// 0x80680 "InterfaceOrientationMode"
public enum InterfaceOrientationMode: Int, CaseIterable {
    case follow = 0      // 跟随设备
    case locked = 1      // 锁定当前
    case landscape = 2   // 强制横屏
    case portrait = 3    // 强制竖屏
}

/// 0x806a0 "SystemServiceMask" —— OptionSet，参与挂起/保活决策
public struct SystemServiceMask: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let audio    = SystemServiceMask(rawValue: 1 << 0)
    public static let camera   = SystemServiceMask(rawValue: 1 << 1)
    public static let location = SystemServiceMask(rawValue: 1 << 2)
    public static let voip     = SystemServiceMask(rawValue: 1 << 3)
    public static let screen   = SystemServiceMask(rawValue: 1 << 4)
}

/// 0x80629 "_effectEdge" —— 边缘视觉样式
public enum EffectEdge: Int {
    case none = 0
    case blur = 1
    case dim = 2
}
