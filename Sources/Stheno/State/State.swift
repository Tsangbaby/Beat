// State.swift — 手势 / 窗口状态机
//
// 全部字段名来自 __swift5_fieldmd，枚举 case 名来自 __swift5_reflstr，
// 未经推断的地方已单独标注。

import Foundation
import UIKit
import SwiftUI

// MARK: - 枚举（case 名逐字来自 __swift5_reflstr）

/// Stheno.GestureState（4 case，reflstr 顺序：begin/changing/end/transition）
public enum GestureState: Int {
    case begin
    case changing
    case end
    case transition
}

/// Stheno.PanGestureSubType（7 case）
public enum PanGestureSubType: Int {
    case corner
    case edge
    case home
    case icon
    case window
    case keyboard
    case none
}

/// Stheno.PanGestureState（3 case）
public enum PanGestureState: Int {
    case began
    case changed
    case ended
}

/// Stheno.Tab（3 case）—— 切换器/相册的分页
public enum Tab: Int, CaseIterable {
    case star
    case user
    case system
}

/// Stheno.LoadCommandType（12 case）—— 反射库读取 Mach-O 时用
public enum LoadCommandType: Int {
    case Unknown
    case SymTab
    case UnixThread
    case DSymTab
    case Segment64
    case UUID
    case CodeSignature
    case DYLDInfo
    case DYLDInfoOnly
    case Main
    case ChainedFixups
    case FilesetEntry
}

/// Stheno.BaseScale —— 四种「基准态」的缩放系数
/// 字段名 pp / pl / lp / ll 是「竖/横」双拼，具体语义见报告 §5.3（推断）
public struct BaseScale {
    public var pp: CGFloat = 1
    public var pl: CGFloat = 1
    public var lp: CGFloat = 1
    public var ll: CGFloat = 1
}

/// Stheno.BaseOffset —— 与 BaseScale 对应的基准偏移
public struct BaseOffset {
    public var pp: CGSize = .zero
    public var pl: CGSize = .zero
    public var lp: CGSize = .zero
    public var ll: CGSize = .zero
}

// MARK: - RingState（手势环）

/// Stheno.RingState（16 字段）
/// 证据：0x87af0 类型描述符；字段顺序来自 fieldmd；
///       0x5b2f8 / 0x5c7f8 两个大函数驱动其状态推进。
public final class RingState: ObservableObject {

    @Published public var scale: CGFloat = 1
    @Published public var offset: CGSize = .zero
    @Published public var rotationAngle: CGFloat = 0
    @Published public var selected: Int = 0
    @Published public var trash: Bool = false
    @Published public var radius: CGFloat = 60

    // 非发布状态（用于帧间差分）
    public var offsetLast: CGSize = .zero
    public var radiusLast: CGFloat = 0
    public var fingerLocation: CGPoint = .zero
    public var fingerStartLocation: CGPoint = .zero
    public var translationPadding: CGSize = .zero
    public var longPress: Bool = false
    public var subGestureType: PanGestureSubType = .none
    public var state: PanGestureState = .ended
    /// reflstr: `rings: Array<Range<Int>>` —— 每一环包含的 app 索引区间
    public var rings: [Range<Int>] = []
    /// 是否「钉住」（不随手指回落）
    public var pinned: Bool = false
}

// MARK: - ReflectManager（单个浮窗的核心状态机）

/// Stheno.ReflectManager（39 字段）
///
/// 这是整个插件最重要的类：一个实例 == 一个浮窗。
/// 字段名全部来自 fieldmd；类型中标注 `~` 的为推断
/// （元数据里 CGSize/CGRect 在反射信息中不可区分，按语义取 CGRect）。
public final class ReflectManager: ObservableObject {

    // ---- 场景 ----
    public var forceForeground: Bool = false
    public var scene: FBScene?                       // 私有框架 FrontBoard
    public var transitionContext: AnyObject?         // FBTransitionContext
    public var id: String = ""                       // bundle identifier
    public var icon: UIImage?
    public var running: Bool = false
    public var authorize: Bool = false

    // ---- 几何 ----
    public var paddingScale: CGFloat = 1
    public var covered: Bool = false
    public var fingerStartLocation: CGPoint = .zero
    public var translationPadding: CGSize = .zero

    // ---- SwiftUI 环境 ----
    // 注意：@Environment 只能用在 View/App/ViewModifier 里，不能放在 class 上。
    // 原工程是通过 EnvironmentValues 传入的，这里改为普通存储属性，
    // 由 SwiftUI 视图在 updateUIView / body 里赋值。
    public var colorScheme: ColorScheme = .light

    // ---- 多任务态 ----
    @Published public var medusaed: Bool = false      // 是否处于分屏/多窗口
    public var medusaFrameLast: CGRect = .zero
    public var iconOffsetLast: CGSize = .zero
    public var finalFrame: CGRect = .zero
    public var finalScale: CGFloat = 1
    public var finalOffset: CGSize = .zero
    public var finalCardFrame: CGRect = .zero
    public var finalCardCorner: CGFloat = 0

    // ---- 启动/覆盖 ----
    @Published public var launching: Bool = false
    @Published public var showCover: Bool = false
    @Published public var interfaceOrientation: UIInterfaceOrientation = .portrait
    public var supportedLaunchOrientation: Int = 0
    @Published public var views: [UIView] = []

    // ---- 键盘 / 封面 ----
    public var keyboard: [UIView] = []
    public var cover: UIView?
    public var iconMoved: Bool = false

    // ---- 手势 ----
    @Published public var offset: CGSize = .zero
    @Published public var iconOffset: CGSize = .zero
    @Published public var dragScale: CGFloat = 1
    public var baseOffsetLast: BaseOffset = .init()
    public var baseScaleLast: BaseScale = .init()
    @Published public var scale: CGFloat = 1
    @Published public var scaleToIcon: Bool = false
    public var subGestureType: PanGestureSubType = .none
    public var longPress: Bool = false
    public var state: PanGestureState = .ended

    // ---- 呈现 ----
    public var presenter: AnyObject?                  // BNPresentable

    public init(id: String, scene: FBScene?) {
        self.id = id
        self.scene = scene
    }

    /// 供 Environment 序列化到 /tmp/stheno_env.json
    public func snapshot() -> [String: Any] {
        [
            "id": id,
            "medusaed": medusaed,
            "launching": launching,
            "running": running,
            "frame": NSCoder.string(for: finalFrame),
            "scale": finalScale,
        ]
    }
}

// MARK: - TrashAppState

/// Stheno.TrashAppState（2 字段）
public final class TrashAppState: ObservableObject {
    public var manager: ReflectManager
    @Published public var offset: CGSize = .zero

    public init(manager: ReflectManager) {
        self.manager = manager
    }
}

// MARK: - AppSearcher

/// Stheno.AppSearcher（1 字段：snapshots: Dictionary<String, …>）
/// 0x428c4 里对 LSApplicationWorkspace 做 enumerateApplicationsOfType:block:，
/// 并按 com.apple.mobilephone / com.apple.camera 白名单过滤。
public final class AppSearcher {

    public struct Snapshot {
        public let name: String
        public let id: String
    }

    /// id → Snapshot（元数据给出 Dictionary<String, …>）
    public var snapshots: [String: Snapshot] = [:]

    public init() {}

    /// 0x428c4
    public func reload() {
        snapshots.removeAll()

        let workspace = LSApplicationWorkspace.default()
        workspace.enumerateApplications(ofType: 0) { proxy in
            guard let bundleID = proxy.applicationIdentifier() else { return }
            // 系统电话 / 相机默认不参与（隐藏项）
            if bundleID == "com.apple.mobilephone" { return }
            if proxy.isLaunchProhibited() { return }
            let name = proxy.localizedName() ?? bundleID
            snapshots[bundleID] = Snapshot(name: name, id: bundleID)
        }
    }
}

// MARK: - SignedStamp（授权/签名校验）

/// Stheno.SignedStamp（4 字段）
/// 0x16ef0 附近做 Data.base64EncodedString + uppercased + 字符串拼接，
/// 0x17a54 引用常量 "EXTNT093476981HP"，可判断是「机器码 + 授权码」的校验流程。
public final class SignedStamp: ObservableObject {

    @Published public var showGallery: Bool = false
    @Published public var loaded: Bool = false
    @Published public var needActivate: Bool = false
    @Published public var alertView: LecardAlertView?

    /// 授权码前缀（0x80f830）
    public static let keyPrefix = "EXTNT093476981HP"

    public init() {}

    /// 校验入口（实现函数 0x16ef4，740 B）
    ///
    /// 【逐指令读出，含地址】
    ///   0x16f00  x22 = __common+0x210        取全局槽（swift_once 保护的全局变量）
    ///   0x16f10  bl 0x1b66c                  swift_beginAccess（不是"取设备码"，见 §22 更正）
    ///   0x16f24  bl 0x4b9c8                  用该全局值取字段
    ///   0x16f3c  bl 0x4bbf4                  取到 String → (x22, x24)
    ///   0x16f50  mov w0, #0xe                常量 14
    ///   0x16f54  mov w1, #0x10               常量 16
    ///   0x16f60  bl 0x2bbd8                  String.index(_:offsetBy:) ×2 → 截 [14, 16)
    ///   0x17130  Data.base64EncodedString
    ///   0x17150  String.uppercased()
    ///   0x17188  ReversedCollection          反转
    ///   0x1704c  _stringCompareWithSmolCheck 比较
    ///
    /// 即：expected = reverse( uppercase( base64( value[14..<16] ) ) )
    public func validate(input: String) -> Bool {
        loaded = true

        guard input.hasPrefix(Self.keyPrefix) else {
            needActivate = true
            return false
        }

        // 0x16f00–0x16f3c：读全局值（原实现可能是设备码缓存或授权文件内容）
        let value = Self.cachedValue()
        guard value.count >= 16 else { needActivate = true; return false }

        // 0x16f50/0x16f54/0x16f60：截取第 14–16 位（2 个字符）
        let start = value.index(value.startIndex, offsetBy: 14)   // w0 = 0xE
        let end   = value.index(value.startIndex, offsetBy: 16)   // w1 = 0x10
        let slice = String(value[start..<end])

        // 0x17130 → 0x17150 → 0x17188
        let encoded = Data(slice.utf8).base64EncodedString()
        let upper = encoded.uppercased()
        let expected = String(upper.reversed())

        let ok = (input == expected)                              // 0x1704c
        needActivate = !ok
        return ok
    }

    /// 0x16f00 读的全局槽（__common+0x210）。原实现由 swift_once 初始化，
    /// 具体内容未定 —— 可能是设备码缓存，也可能是授权文件里的一段。
    private static var cachedValueStorage: String = ""
    private static let cachedValueOnce: Void = {
        cachedValueStorage = Self.deviceCode()
    }()

    static func cachedValue() -> String {
        _ = cachedValueOnce
        return cachedValueStorage
    }

    /// 设备码：优先 IORegistry 的 IOPlatformUUID，失败回落 UniqueDeviceID，
    /// 再回落 MobileGestalt（0x4b504 里 dlopen("/usr/lib/libMobileGestalt.dylib") + MGCopyAnswer）。
    static func deviceCode() -> String {
        if let uuid = ioPlatformUUID() { return uuid }
        if let udid = uniqueDeviceID() { return udid }
        return mobileGestalt("UniqueDeviceID") ?? ""
    }

    // IOKit C types and ownership annotations are imported by the bridge header.
    private static func ioPlatformUUID() -> String? {
        let service = IOServiceGetMatchingService(0,
                                                  IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service,
                                               "IOPlatformUUID" as CFString,
                                               nil, 0)?
            .takeRetainedValue() as? String
    }

    private static func uniqueDeviceID() -> String? { nil }   // 同上，键为 UniqueDeviceID

    private static func mobileGestalt(_ key: String) -> String? {
        guard let handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY),
              let sym = dlsym(handle, "MGCopyAnswer") else { return nil }
        typealias CopyAnswer = @convention(c) (CFString) -> Unmanaged<CFString>?
        let fn = unsafeBitCast(sym, to: CopyAnswer.self)
        return fn(key as CFString)?.takeRetainedValue() as String?
    }
}

// MARK: - 私有类型
//
// FBScene / LSApplicationProxy / LSApplicationWorkspace 的真实声明在
// PrivateSDK.swift（它们是 ObjC 类，不是协议——用协议做 ClassHook 的泛型参数会编译失败）。
