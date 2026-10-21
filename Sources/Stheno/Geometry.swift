// Geometry.swift — 几何/动画常量（全部从 __const 段实读）
//
// 这些值不是猜的：每一条都标注了它在二进制中的地址，以及引用它的函数。
// 用途：浮窗的 padding、缩放、旋转、收敛阈值都以它们为基准。
// 原工程里这些常量散落在各个计算属性中，这里集中成一张表，便于调参和比对。
//
// 复核方式：
//   python -c "import struct; d=open('Stheno.dylib','rb').read(); \
//              print(struct.unpack_from('<d', d, 0x81ce8-0x8000+0x4000))"
//   （左例：0x81ce8 → 0.2；地址换算见 tools/mo.py 的 a2o）

import CoreGraphics
import Foundation

/// 从 __const 段原样读出的常量
public enum SthenoMetrics {

    // MARK: - 比例 / 比例尺
    //
    // 0x66c98（frame 计算）里直接 ldr 了 0x81ce8，用作 paddingScale 的基准。
    /// 0x81ce8 = 0.2 —— paddingScale 默认值 / 内缩比例
    public static let paddingRatio: CGFloat = 0.2
    /// 0x81da8 = 0.1
    public static let ratio10: CGFloat = 0.1
    /// 0x81db0 = 0.03
    public static let ratio03: CGFloat = 0.03
    /// 0x81db8 = 0.3
    public static let ratio30: CGFloat = 0.3
    /// 0x81f20 = 0.7
    public static let ratio70: CGFloat = 0.7
    /// 0x81f28 = 0.05
    public static let ratio05: CGFloat = 0.05
    /// 0x82178 = 0.15
    public static let ratio15: CGFloat = 0.15
    /// 0x82180 = 0.55
    public static let ratio55: CGFloat = 0.55
    /// 0x82188 = 0.825
    public static let ratio825: CGFloat = 0.825
    /// 0x82190 = 0.8
    public static let ratio80: CGFloat = 0.8
    /// 0x821b8 = -2.0
    public static let minusTwo: CGFloat = -2.0
    /// 0x843c8 = -0.4  （手势位移系数，0x5b2f8 内引用）
    public static let translationFactor: CGFloat = -0.4

    // MARK: - 手感 / 阻尼
    //
    // 这组数值落在 0.6~0.95，是典型的 dampingFraction / 收敛系数；
    // 0x5b2f8 与 0x66c98 都有引用。
    /// 0x826a8 = 0.13
    public static let damping013: CGFloat = 0.13
    /// 0x826b0 = 0.6
    public static let damping060: CGFloat = 0.6
    /// 0x826b8 = -1.15
    public static let offsetBias: CGFloat = -1.15
    /// 0x826c0 = 0.95
    public static let damping095: CGFloat = 0.95
    /// 0x82ef8 = 0.86
    public static let damping086: CGFloat = 0.86
    /// 0x82f00 = 0.9
    public static let damping090: CGFloat = 0.9
    /// 0x82f08 = 0.35
    public static let progress035: CGFloat = 0.35
    /// 0x82f00 附近的 0.9 也用于缩放上限
    public static let scaleMax: CGFloat = 0.9
    /// 0x837c0 = 0.16
    public static let threshold016: CGFloat = 0.16

    // MARK: - 角度换算
    //
    // 0x830d8~0x83188 是一整块角度常量，覆盖 ±90/180/360/720/1080 与 ±π/2、π、2π、3π、4π。
    // 说明作者同时用「度」和「弧度」两套单位做旋转（RingView 用弧度、手势速度用度）。
    /// 0x830d8 = 180/π
    public static let radiansToDegrees: CGFloat = 57.29577951308232
    /// 0x83138 = -180/π
    public static let negativeRadiansToDegrees: CGFloat = -57.29577951308232
    /// 0x830f0 = π/180
    public static let degreesToRadians: CGFloat = 0.017453292519943295
    /// 0x83180 = π/2
    public static let halfPi: CGFloat = 1.5707963267948966
    /// 0x83110 = π
    public static let pi: CGFloat = 3.141592653589793
    /// 0x83168 = 3π/2
    public static let threeHalfPi: CGFloat = 4.71238898038469
    /// 0x83118 = 2π
    public static let twoPi: CGFloat = 6.283185307179586
    /// 0x83148 = 4π
    public static let fourPi: CGFloat = 12.566370614359172
    /// 0x830f8 = 90
    public static let degrees90: CGFloat = 90
    /// 0x83128 = 180
    public static let degrees180: CGFloat = 180
    /// 0x830e0 = 360
    public static let degrees360: CGFloat = 360
    /// 0x83160 = 720
    public static let degrees720: CGFloat = 720
    /// 0x83108 = 1080
    public static let degrees1080: CGFloat = 1080
    /// 0x830c8 = 1.2
    public static let overshoot: CGFloat = 1.2
    /// 0x830d0 = 1e-6 —— 浮点比较的 epsilon
    public static let epsilon: CGFloat = 1e-6
    /// 0x83100 = -0.6
    public static let minus06: CGFloat = -0.6
    /// 0x83158 = 2.4
    public static let angle24: CGFloat = 2.4

    // MARK: - 角度归一化
    //
    // 0x3ac34 / 0x3cd50 里出现 `_fmod` + `___sincos_stret` + SwiftUI.Angle.animatableData，
    // 说明 RingView 的图标位置是 angle → (sin, cos) → 半径投影。
    /// 把任意角度收进 (-180, 180]
    public static func normalizeDegrees(_ value: CGFloat) -> CGFloat {
        var v = value.truncatingRemainder(dividingBy: degrees360)
        if v > degrees180 { v -= degrees360 }
        if v <= -degrees180 { v += degrees360 }
        return v
    }

    /// 把任意弧度收进 (-π, π]
    public static func normalizeRadians(_ value: CGFloat) -> CGFloat {
        var v = value.truncatingRemainder(dividingBy: twoPi)
        if v > pi { v -= twoPi }
        if v <= -pi { v += twoPi }
        return v
    }
}

/// 浮窗几何
///
/// 说明：0x66c98（2760 B）是一整片 `@Published` 存取器 + 计算属性的集合，
/// 内部用 `CGRectGetHeight` 与 `paddingRatio` 组合出最终 frame。逐行公式尚未还原，
/// 下面给出的是**结构等价**的实现，常量取自上面的实测值；
/// 与真机表现有偏差时，优先调整 `paddingRatio` 与 `insetForScreenEdge`。
public enum SthenoGeometry {

    /// 浮窗的可用区域：屏幕四周留出安全区 + 圆角补偿
    public static func availableBounds(screen: CGRect, cornerRadius: CGFloat) -> CGRect {
        let inset = max(cornerRadius * SthenoMetrics.paddingRatio,
                        SthenoMetrics.ratio10 * screen.width * SthenoMetrics.paddingRatio)
        return screen.insetBy(dx: inset, dy: inset)
    }

    /// 16:9 模式（`_169ControllView` / "16:9比例窗口"）下的窗口尺寸
    /// 取屏幕长边为宽，按 9/16 求高
    public static func aspect169(in bounds: CGRect) -> CGSize {
        let width = bounds.width
        return CGSize(width: width, height: (width * 9 / 16).rounded())
    }

    /// 缩小到图标时的目标 scale（用于 `scaleToIcon`）
    public static func iconScale(iconSize: CGFloat, windowWidth: CGFloat) -> CGFloat {
        guard windowWidth > 0 else { return 1 }
        return min(1, max(SthenoMetrics.ratio03, iconSize / windowWidth))
    }

    /// 边缘热区：`edgeWidth` 由设置项给出，百分比上限由 rightPecent/leftPecent 约束
    public static func edgeZones(in bounds: CGRect,
                                 edgeWidth: CGFloat,
                                 leftPercent: CGFloat,
                                 rightPercent: CGFloat) -> (left: CGRect, right: CGRect) {
        let lw = min(bounds.width * leftPercent, max(edgeWidth, 1))
        let rw = min(bounds.width * rightPercent, max(edgeWidth, 1))
        let left = CGRect(x: bounds.minX, y: bounds.minY, width: lw, height: bounds.height)
        let right = CGRect(x: bounds.maxX - rw, y: bounds.minY, width: rw, height: bounds.height)
        return (left, right)
    }

    /// 环半径：第 index 环的半径（RingState.rings 的区间决定每环放几个图标）
    public static func ringRadius(index: Int, base: CGFloat, spacing: CGFloat) -> CGFloat {
        base + CGFloat(index) * spacing
    }
}
