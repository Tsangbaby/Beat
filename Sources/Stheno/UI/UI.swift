// UI.swift — 窗口 + SwiftUI 视图骨架
//
// 视图清单全部来自类型元数据（kind=17 的 struct 即为 SwiftUI View），
// 每个 struct 的字段名逐字来自 __swift5_fieldmd，字段前的 `@` 语义由字段名推断：
//   _env / _device / _manager / _colorScheme / _gestureState  → @EnvironmentObject / @Environment
//   size / name / _active / _edge / _text / _added / _color       → 普通 @State 或入参
//
// 视图体（body）在二进制里是庞大的 SwiftUI 泛型展开代码（例如 0x40a9c 单函数 6772 字节），
// 无法逐行还原；这里保留结构、语义与 SF Symbol 名称（__cstring 里可读），
// 便于后续按截图/实机逐个补齐。

import SwiftUI
import UIKit

// SthenoWindow and its tested owner live in OverlayWindow.swift.

// MARK: - 根容器

/// Stheno.Container（0 字段）—— UIHostingView 的根视图
public struct Container: View {
    public init() {}

    public var body: some View {
        // Stheno.Container（0 字段）＝ _UIHostingView 的根视图
        // 依据：0x7f5a0 的 "_UIHostingView<Container>"，以及 0x10058 里 setRootViewController
        ZStack {
            Switcher()
        }
        .ignoresSafeArea()
        .environmentObject(SthenoController.shared.environment)
        .environmentObject(SthenoController.shared.deviceInfo)
        .environmentObject(SignedStamp())
    }
}

// MARK: - 主界面

/// Stheno.Switcher（_env / _device / _colorScheme / _signedstamp）
/// 0x2ab20（3160 字节）里读 UILaunchStoryboardName / UIStoryboard / instantiateInitialViewController
/// → 说明切换器同时负责"用 App 自己的启动图做占位"。
public struct Switcher: View {
    @EnvironmentObject var env: Environment
    @EnvironmentObject var device: DeviceInfo
    @SwiftUI.Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var signedstamp: SignedStamp

    public var body: some View {
        // 依据字段 `_env/_device/_colorScheme/_signedstamp` 与 0x2ab20（读 UILaunchStoryboardName）
        // → 主界面是「相册 / 网格」二选一，外加手势环与边缘条两层覆盖
        ZStack {
            if signedstamp.showGallery {
                GalleryView()
            } else {
                AppGrid(tab: selectedTab)
            }

            // 手势环（0x3cd50）
            RingView(ringState: ringState)
                .opacity(env.showRing ? 1 : 0)
                .allowsHitTesting(env.showRing)

            // 边缘条（0x23be8 的第三行）
            if env.showEdgeBar {
                EdgeBarControlView(size: 17, name: "", active: true, edge: 0)
            }

            // 授权失效提示（0x17a54 引用 EXTNT093476981HP）
            if env.invalid {
                Color.black.opacity(SthenoMetrics.ratio30).ignoresSafeArea()
                LicenseInputView()
            }
        }
    }

    @State private var selectedTab: Tab = .user
    @StateObject private var ringState = RingState()
}

/// Stheno.ReflectView（_device / interfaceOrientation / view / medusaed）
/// 0x65ac8（1260 字节）：UIViewRepresentable + CGAffineTransformMakeScale/Rotate
/// → 把一个真实 UIView（App 的场景视图）按浮窗几何做缩放/旋转。
public struct ReflectView: UIViewRepresentable {
    @EnvironmentObject var device: DeviceInfo
    public var interfaceOrientation: Int
    public var view: UIView
    public var medusaed: Bool

    public func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        container.addSubview(view)
        return container
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        uiView.transform = CGAffineTransform(rotationAngle: CGFloat(interfaceOrientation) * .pi / 2)
    }
}

/// Stheno.ReflectKeyboardView（_device / interfaceOrientation / view）
public struct ReflectKeyboardView: UIViewRepresentable {
    @EnvironmentObject var device: DeviceInfo
    public var interfaceOrientation: Int
    public var view: UIView

    public func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.addSubview(view)
        return container
    }

    public func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - 手势环

/// Stheno.RingView（12 字段）
/// 0x3ac34 / 0x3cd50：SwiftUI.Angle.animatableData + ___sincos_stret + _fmod
/// → 环上每个 app 图标按角度三角定位，是真·环形排布（不是网格旋转）。
public struct RingView: View {
    @EnvironmentObject var device: DeviceInfo
    @ObservedObject var ringState: RingState

    // Authorized phase-one display reconstruction; not an original body restoration.
    // No launch, keep-alive, Scene or licensing behavior is added here.
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    .frame(width: max(0, ringState.radius) * 2,
                           height: max(0, ringState.radius) * 2)
                ForEach(Array(device.apps.enumerated()), id: \.element.id) { item in
                    let offset = ringOffset(for: item.offset)
                    TabIcon(app: item.element, added: ringState.selected == item.offset)
                        .offset(x: offset.width, y: offset.height)
                }
            }
            .scaleEffect(ringState.scale)
            .position(x: geometry.size.width / 2 + ringState.offset.width,
                      y: geometry.size.height / 2 + ringState.offset.height)
        }
    }

    private func ringOffset(for index: Int) -> CGSize {
        let ringIndex = ringState.rings.firstIndex(where: { $0.contains(index) })
        let indices = ringIndex.map { ringState.rings[$0] } ?? 0..<device.apps.count
        let count = max(indices.count, 1)
        let angle = SthenoMetrics.twoPi * CGFloat(index - indices.lowerBound) / CGFloat(count)
            + ringState.rotationAngle - SthenoMetrics.halfPi
        let radius = max(0, SthenoGeometry.ringRadius(
            index: ringIndex ?? 0, base: ringState.radius,
            spacing: ringState.radius * SthenoMetrics.ratio70))
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }
}

/// Stheno.TrashAppView（_state / _gestureState）
public struct TrashAppView: View {
    @EnvironmentObject var state: TrashAppState
    @SwiftUI.Environment(\.gestureState) var gestureState

    public var body: some View {
        // 依据 `_state/_gestureState`；"trash" 符号见 __cstring 0x80595
        Image(systemName: "trash")
            .font(.system(size: 22, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 52, height: 52)
            .background(Circle().fill(Color.red.opacity(SthenoMetrics.damping095)))
            .offset(state.offset)
            .scaleEffect(gestureState == .changing ? SthenoMetrics.overshoot : 1)
    }
}

// MARK: - 相册 / 网格

/// Stheno.GalleryView（_device / _selectedTab / _scale）
public struct GalleryView: View {
    @EnvironmentObject var device: DeviceInfo
    @State var selectedTab: Tab = .user
    @State var scale: CGFloat = 1

    public var body: some View {
        // 依据 `_device/_selectedTab/_scale` 与 TabBar/AppGrid 的引用关系
        VStack(spacing: 0) {
            TabBar(color: .accentColor, selectedTab: $selectedTab)
            AppGrid(tab: selectedTab)
        }
        .scaleEffect(scale)
        .onAppear { scale = 1 }
    }
}

/// Stheno.TabBar（_color / _selectedTab）
public struct TabBar: View {
    @SwiftUI.Environment(\.colorScheme) var colorScheme
    var color: Color
    @Binding var selectedTab: Tab

    public var body: some View {
        // 依据 `_color/_selectedTab`；Tab 的三个 case（star/user/system）来自 __swift5_reflstr
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                TabItem(name: tab.title, icon: tab.symbol, color: color, selection: tab)
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: SthenoMetrics.damping086)) {
                            selectedTab = tab
                        }
                    }
            }
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func tabItem(_ tab: Tab, name: String, icon: String) -> some View {
        TabItem(name: name, icon: icon, color: color, selection: tab)
            .onTapGesture { selectedTab = tab }
    }
}

/// Stheno.TabItem（name / icon / color / selection）
public struct TabItem: View {
    var name: String
    var icon: String
    var color: Color
    var selection: Tab

    public var body: some View {
        // 依据 `name/icon/color/selection` 四字段
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: selection == current ? .semibold : .regular))
            Text(name).font(.caption2)
        }
        .foregroundColor(selection == current ? color : .secondary)
    }

    /// 当前选中项来自 TabBar 的 Binding
    private var current: Tab { selection }
}

/// Stheno.AppGrid（_colorScheme / tab）
/// 0x448a8：LazyVGrid + GridItem → 应用图标网格
public struct AppGrid: View {
    @SwiftUI.Environment(\.colorScheme) var colorScheme
    var tab: Tab

    public var body: some View {
        // 依据 0x448a8（1152 B）：LazyVGrid + GridItem + PinnedScrollableViews.sectionHeaders
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)],
                  alignment: .center,
                  spacing: 16,
                  pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(apps, id: \.id) { app in
                    TabIcon(app: app, added: false)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    /// 依据 0x428c4 / 0x2b784：由 Environment / AppSearcher 提供
    private var apps: [AppSearcher.Snapshot] {
        let env = SthenoController.shared.environment
        switch tab {
        case .star:   return env.trash.map { AppSearcher.Snapshot(name: $0.manager.id, id: $0.manager.id) }
        case .user:   return env.user
        case .system: return env.system
        }
    }
}

/// Stheno.TabIcon（app / _added）
public struct TabIcon: View {
    var app: AppSearcher.Snapshot
    @State var added: Bool = false

    public var body: some View {
        // 依据 `app/_added` 两字段 + 0x448a8 的 LazyVGrid 单元格
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.secondary.opacity(SthenoMetrics.ratio15))
                    .frame(width: 56, height: 56)

                if added {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .offset(x: 4, y: -4)
                }
            }
            Text(app.name)
                .font(.system(size: 10))
                .lineLimit(1)
        }
    }
}

/// Stheno.App（name / id）
public struct App: View {
    var name: String
    var id: String
    public var body: some View { Text(name) }
}

// MARK: - 设置面板（16 个 ControlView）
//
// 【这一段的还原依据（非占位）】
//   0x24e10 是其中一个 ControlView 的 body，可读出完整模板：
//     SwiftUI.RoundedRectangle 元数据（0x24e3c → GOT(_$s7SwiftUI16RoundedRectangleVMa)）
//     Environment.shared 取某项设置（0x24e8c → sub_4f5ec）
//     swift_getKeyPath(0x827d0) + State<Bool>.init(wrappedValue:)（0x24eb0 / 0x24f20）
//     写 Double 字段 size（0x24ed4 ldrsw [x22,#0x14]; str d8）
//     写 18 字符大字符串 = "circle.hexagonpath"（0x24ee4 movk 拼长度 0x12，指针 0x7fc80）
//     LocalizedStringKey.stringLiteral（0x24f4c）+ Text(_:tableName:bundle:comment:)（0x24f74）
//   16 个 ControlView 的字段也完全一致：`_colorScheme + size + name + _active (+ _edge/_activeName)`
//   → 说明作者写了一个统一的"开关行"模板，各视图只是换了符号与文案。
//
// 下面的 `ControlRow` 就是这个模板的重建。每个视图的 symbol / 文案都有出处，已逐条标注；
// 没有出处的一律标 TODO，不臆造。

import SwiftUI

/// 统一的"开关行"模板（对应 0x24e10 / 0x25020 / 0x1f528 三处共同结构）
struct ControlRow: View {
    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    let symbol: String          // SF Symbol 名（实读自 __cstring）
    let title: LocalizedStringKey
    let subtitle: String?
    let size: CGFloat
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: size * SthenoMetrics.ratio15) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: size * SthenoMetrics.overshoot, height: size * SthenoMetrics.overshoot)
                .background(
                    RoundedRectangle(cornerRadius: size * SthenoMetrics.ratio30,
                                     style: .continuous)
                        .fill(Color.primary.opacity(isOn ? SthenoMetrics.ratio15 : SthenoMetrics.ratio05))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: size, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: size * SthenoMetrics.ratio70))
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .scaleEffect(SthenoMetrics.ratio80)
        }
    }
}

/// 段落容器（对应 0x23be8 / 0x24f6c 的共同结构）
///
/// 依据：两处都大量调用
///   SwiftUI.VerticalAlignment.top      → VStack(alignment: .leading)
///   SwiftUI.EdgeInsets.all             → .padding(...)
///   SwiftUI.Edge.Set.leading           → Section header 对齐
///   LocalizedStringKey.stringLiteral ×3 + Text(_:tableName:bundle:comment:) ×3
///   sub_26c80 / sub_26cd4              → SwiftUI 视图列表构建（逐行追加/收尾）
/// 即：一个 VStack，内含 3 行，每行是一个 ControlView。
struct SettingsSection<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(LocalizedStringKey(title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            content
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(SthenoMetrics.ratio05))
        )
    }
}

// MARK: 16:9 窗口（body 实现函数 = 0x22f58）
//
// 0x22f58 里读 `Environment.shared` 的两项（sub_4f7a0 / sub_4f61c），
// 并把 size 写入 Doubles；SF Symbol = "rectangle.topthird.inset.filled"(0x7fd90)，
// 文案 = "16:9比例窗口, 可长安浮窗四角重启强制匹配UI。"（"长安"为原作者笔误）
public struct _169ControllView: View {
    @EnvironmentObject public var env: Environment
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    @State public var active: Bool = false

    public init(size: CGFloat, active: Bool = false) {
        self.size = size
        self._active = State(initialValue: active)
    }

    public var body: some View {
        ControlRow(symbol: "rectangle.topthird.inset.filled",
                   title: "16:9比例窗口, 可长安浮窗四角重启强制匹配UI。",
                   subtitle: nil,
                   size: size,
                   isOn: $active)
    }
}

// MARK: 单/多窗口切换（body 实现函数 = 0x1f528）
//
// 0x1f528 同时引用 "rectangle.portrait.on.rectangle.portrait.angled"(0x7fe00)
// 与 "rectangle.portrait"(0x7fe30) → 用 _ConditionalContent 在两个图标间切换
public struct WindowGestureControlView: View {
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    public var name: String
    @State public var active: Bool = false

    public init(size: CGFloat, name: String, active: Bool = false) {
        self.size = size; self.name = name
        self._active = State(initialValue: active)
    }

    public var body: some View {
        ControlRow(symbol: active ? "rectangle.portrait.on.rectangle.portrait.angled"
                                  : "rectangle.portrait",
                   title: LocalizedStringKey(name),
                   subtitle: "单多窗口切换, 单窗口状态同步, 切换还原几何尺寸。",
                   size: size,
                   isOn: $active)
    }
}

// MARK: 边缘手势区域（body 实现函数 = 0x23be8 的第三行）
//
// 字段：_rightPecentLast/_leftPecentLast/_edgeWidthLast（"Last" 为差分缓存）
// 文案 = "点击调节边缘手势区域大小, 继续点击切换手势触发边。"
public struct RingGestureRegionControlView: View {
    @EnvironmentObject public var env: Environment
    @EnvironmentObject public var device: DeviceInfo
    @State public var rightPecentLast: CGFloat = 0
    @State public var leftPecentLast: CGFloat = 0
    @State public var edgeWidthLast: CGFloat = 0
    @State public var rightPecent: CGFloat = 0
    @State public var leftPecent: CGFloat = 0
    @State public var edgeWidth: CGFloat = 0
    public var translationPadding: CGSize = .zero
    @SwiftUI.Environment(\.gestureState) public var gestureState: GestureState

    public init() {}

    public var body: some View {
        ControlRow(symbol: "circle.hexagonpath",
                   title: "点击调节边缘手势区域大小, 继续点击切换手势触发边。",
                   subtitle: nil,
                   size: 17,
                   isOn: Binding(get: { env.showEdgeBar }, set: { env.showEdgeBar = $0 }))
    }
}

// MARK: 四个服务开关（body 实现函数 = 0x24f6c：一次生成三行）
//
// 0x24f6c 引用：arrowshape.turn.up.forward.fill(0x7fc20) / exclamationmark.arrow.circlepath(0x7fba0)
//               gearshape.arrow.triangle.2.circlepath(0x7fbd0) / clock.arrow.2.circlepath(0x7fb80)
// 及三条文案（URLScheme / 消息通知 / 账号授权）
public struct URLControlView: View {
    @EnvironmentObject public var env: Environment
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    public var name: String
    @State public var active: Bool = false

    public init(size: CGFloat, name: String = "URLScheme", active: Bool = false) {
        self.size = size; self.name = name
        self._active = State(initialValue: active)
    }

    public var body: some View {
        ControlRow(symbol: "arrowshape.turn.up.forward.fill",
                   title: "URLScheme以浮窗打开。",
                   subtitle: nil, size: size, isOn: $active)
    }
}

public struct NotificationControlView: View {
    @EnvironmentObject public var env: Environment
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    public var name: String
    @State public var active: Bool = false

    public init(size: CGFloat, name: String = "通知", active: Bool = false) {
        self.size = size; self.name = name
        self._active = State(initialValue: active)
    }

    public var body: some View {
        ControlRow(symbol: "exclamationmark.arrow.circlepath",
                   title: "消息通知以浮窗打开。",
                   subtitle: nil, size: size, isOn: $active)
    }
}

public struct AuthorizeControlView: View {
    @EnvironmentObject public var env: Environment
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    public var name: String
    @State public var active: Bool = false

    public init(size: CGFloat, name: String = "授权", active: Bool = false) {
        self.size = size; self.name = name
        self._active = State(initialValue: active)
    }

    public var body: some View {
        ControlRow(symbol: "gearshape.arrow.triangle.2.circlepath",
                   title: "账号授权以浮窗打开。",
                   subtitle: nil, size: size, isOn: $active)
    }
}

public struct SynchronizeControlView: View {
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    @State public var active: Bool = false

    public init(size: CGFloat, active: Bool = false) {
        self.size = size
        self._active = State(initialValue: active)
    }

    public var body: some View {
        ControlRow(symbol: "clock.arrow.2.circlepath",
                   title: "单多窗口切换, 单窗口状态同步, 切换还原几何尺寸。",
                   subtitle: nil, size: size, isOn: $active)
    }
}

// MARK: 其余 ControlView（符号/文案尚无唯一出处，保持结构 + TODO）
//
// 这几个的 SF Symbol 与文案没有在 0x23be8 / 0x24f6c / 0x1f528 里出现，
// 说明它们的 body 在别的函数里（可用 tools/dx.py 的 summarize 继续指纹定位）。
// 结构（size + name + _active）已确证，若套到 ControlRow 上即可用。

public struct GlobalControlView: View {
    @EnvironmentObject public var env: Environment
    @EnvironmentObject public var device: DeviceInfo
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    public init(size: CGFloat) { self.size = size }
    public var body: some View {
        // body 实现函数 = 0x23be8（3740 B）
        // 该函数内出现 3 条中文文案 + 3 次 Text(...) 构造：
        //   "16:9比例窗口, 可长安浮窗四角重启强制匹配UI。"
        //   "单多窗口切换, 单窗口状态同步, 切换还原几何尺寸。"
        //   "点击调节边缘手势区域大小, 继续点击切换手势触发边。"
        // 且各以 sub_26c80/sub_26cd4（SwiftUI 视图列表构建）追加 → 三行段落
        SettingsSection(title: "窗口") {
            VStack(alignment: .leading, spacing: 12) {
                _169ControllView(size: size, active: env._169)
                WindowGestureControlView(size: size, name: "单/多窗口", active: env.fourEdge)
                RingGestureRegionControlView()
            }
        }
    }   // TODO(指纹未命中)
}

public struct FourEdgeControlView: View {
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    public var name: String
    @State public var active: Bool = false
    public init(size: CGFloat, name: String, active: Bool = false) {
        self.size = size; self.name = name; self._active = State(initialValue: active)
    }
    public var body: some View {
        ControlRow(symbol: "rectangle.split.2x2", title: LocalizedStringKey(name),
                   subtitle: nil, size: size, isOn: $active)   // 符号 TODO
    }
}

public struct InterfaceOrientationModeView: View {
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    public var name: String
    @State public var active: Bool = false
    @State public var activeName: String = ""
    public init(size: CGFloat, name: String, active: Bool = false, activeName: String = "") {
        self.size = size; self.name = name
        self._active = State(initialValue: active)
        self._activeName = State(initialValue: activeName)
    }
    public var body: some View {
        ControlRow(symbol: "rectangle.portrait.rotate", title: LocalizedStringKey(name),
                   subtitle: activeName, size: size, isOn: $active)   // 符号 TODO
    }
}

public struct RingOnlyControlView: View {
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    public var name: String
    @State public var active: Bool = false
    public init(size: CGFloat, name: String, active: Bool = false) {
        self.size = size; self.name = name; self._active = State(initialValue: active)
    }
    public var body: some View {
        ControlRow(symbol: "circle.dashed", title: LocalizedStringKey(name),
                   subtitle: nil, size: size, isOn: $active)   // 符号 TODO
    }
}

public struct CameraControlView: View {
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    public var name: String
    @State public var active: Bool = false
    public init(size: CGFloat, name: String, active: Bool = false) {
        self.size = size; self.name = name; self._active = State(initialValue: active)
    }
    public var body: some View {
        ControlRow(symbol: "camera.viewfinder", title: LocalizedStringKey(name),
                   subtitle: nil, size: size, isOn: $active)   // 符号 TODO
    }
}

public struct ListenControlView: View {
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    public var name: String
    @State public var active: Bool = false
    public init(size: CGFloat, name: String, active: Bool = false) {
        self.size = size; self.name = name; self._active = State(initialValue: active)
    }
    public var body: some View {
        ControlRow(symbol: "ear", title: LocalizedStringKey(name),
                   subtitle: nil, size: size, isOn: $active)   // 符号 TODO
    }
}

public struct EdgeBarControlView: View {
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    public var name: String
    @State public var active: Bool = false
    @State public var edge: Int = 0
    public init(size: CGFloat, name: String, active: Bool = false, edge: Int = 0) {
        self.size = size; self.name = name
        self._active = State(initialValue: active)
        self._edge = State(initialValue: edge)
    }
    public var body: some View {
        ControlRow(symbol: "sidebar.left", title: LocalizedStringKey(name),
                   subtitle: nil, size: size, isOn: $active)   // 符号 TODO
    }
}

public struct GallerySwitchView: View {
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    @State public var active: Bool = false
    public init(size: CGFloat, active: Bool = false) {
        self.size = size; self._active = State(initialValue: active)
    }
    public var body: some View {
        ControlRow(symbol: "square.grid.2x2", title: "相册",
                   subtitle: nil, size: size, isOn: $active)   // 符号 TODO
    }
}

public struct IntroductionView: View {
    @EnvironmentObject public var env: Environment
    @EnvironmentObject public var device: DeviceInfo
    public var size: CGFloat
    public init(size: CGFloat) { self.size = size }
    public var body: some View {
        // body 实现函数 = 0x24f6c（2940 B，强推）
        // 该函数内 4 次 Text(...) + 3 条文案：
        //   "URLScheme以浮窗打开。" / "消息通知以浮窗打开。" / "账号授权以浮窗打开。"
        // 三个 SF Symbol（0x7fc20 / 0x7fba0 / 0x7fbd0）同处一个 VStack
        SettingsSection(title: "服务") {
            VStack(alignment: .leading, spacing: 12) {
                URLControlView(size: size, name: "URLScheme", active: env.URLScheme)
                NotificationControlView(size: size, name: "通知", active: env.ssMask.contains(.voip))
                AuthorizeControlView(size: size, name: "授权", active: env.showLicense)
            }
        }
    }   // TODO(指纹未命中)
}

public struct LicenseInputView: View {
    @EnvironmentObject public var device: DeviceInfo
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    @State public var text: String = ""
    public init() {}
    public var body: some View {
        TextField("授权码", text: $text)
            .textFieldStyle(.roundedBorder)
            .autocapitalization(.allCharacters)
            .disableAutocorrection(true)
    }
}

public struct PasteLicenceKeyView: View {
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat
    public var name: String
    public init(size: CGFloat, name: String) { self.size = size; self.name = name }
    public var body: some View {
        Button(LocalizedStringKey(name)) {
            UIPasteboard.general.string = SignedStamp.keyPrefix
        }
    }
}

public struct SeperatorView: View {
    public var size: CGFloat
    public var name: String
    public init(size: CGFloat, name: String) { self.size = size; self.name = name }
    public var body: some View { Divider() }
}

// MARK: - 弹窗

/// Stheno.AlertAction（title / action）
public struct AlertAction {
    public let title: String
    public let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
}

/// Stheno.LecardAlertView（_device / title / message / primaryAction / secondaryAction）
public struct LecardAlertView: View {
    @EnvironmentObject var device: DeviceInfo
    var title: String
    var message: String
    var primaryAction: AlertAction
    var secondaryAction: AlertAction

    public var body: some View {
        // 依据 0x46ec0（1176 B）：Button(action:label:) + Binding get/set
        //   + withAnimation + Animation.spring(response:dampingFraction:blendDuration:)
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button(secondaryAction.title) {
                    withAnimation(.spring(response: 0.3, dampingFraction: SthenoMetrics.damping086)) {
                        secondaryAction.action()
                    }
                }
                .buttonStyle(.bordered)

                Button(primaryAction.title) {
                    withAnimation(.spring(response: 0.3, dampingFraction: SthenoMetrics.damping095)) {
                        primaryAction.action()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .background(Material.ultraThin, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - 自定义形状 / 修饰符

/// Stheno.CustomRectangle（width / height）
public struct CustomRectangle: Shape {
    var width: CGFloat
    var height: CGFloat

    public func path(in rect: CGRect) -> Path {
        Path(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

/// Stheno.BlurFadeModifier（scaleWidth / scaleHeidth / blur / offset）
/// 注意字段名里 `scaleHeidth` 是原作者的拼写错误，保留原样。
public struct BlurFadeModifier: ViewModifier {
    var scaleWidth: CGFloat
    var scaleHeidth: CGFloat
    var blur: CGFloat
    var offset: CGSize

    public func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .offset(offset)
            .frame(width: scaleWidth, height: scaleHeidth)
    }
}

/// Stheno.GenericEightable（one…eight: Int）
public struct GenericEightable {
    var one: Int = 0
    var two: Int = 0
    var three: Int = 0
    var four: Int = 0
    var five: Int = 0
    var six: Int = 0
    var seven: Int = 0
    var eight: Int = 0
}

// MARK: - Environment 自定义键

private struct GestureStateKey: EnvironmentKey {
    static let defaultValue: GestureState = .end
}

public extension EnvironmentValues {
    var gestureState: GestureState {
        get { self[GestureStateKey.self] }
        set { self[GestureStateKey.self] = newValue }
    }
}

// MARK: - Tab 的展示属性
//
// 依据：Tab 的三个 case（star/user/system，逐字来自 __swift5_reflstr），
// 以及 __cstring 0x7f433 "star" / 0x7f438 "user" 两个 SF Symbol 名。
// "system" 的符号名未在字符串池中单独出现，按语义补 "gearshape"（TODO 待实机核对）。
extension Tab {
    var title: String {
        switch self {
        case .star:   return "收藏"
        case .user:   return "用户"
        case .system: return "系统"
        }
    }

    var symbol: String {
        switch self {
        case .star:   return "star"        // 0x7f433（实读）
        case .user:   return "user"        // 0x7f438（实读）
        case .system: return "gearshape"   // TODO(未在字符串池出现)
        }
    }
}
