# 手势层闭包地图（GESTURE_MAP）

> 更正：`0x5b2f8`（5376 B）**不是**手势状态机，它是 `_SBFluidSwitcherPanGestureRecognizerHook`
> 的 Orion glue（末尾整段是 `ClassHookProtocol` 的协议见证 thunk + `swift_once`）。
> 之前按"体积最大"推断为状态机是错的。
>
> 真正的手势逻辑在 **6 个 SwiftUI 闭包**里，按 `DragGesture` / `TapGesture` 的
> `onChanged` / `onEnded` 区分。

## 一、6 个闭包的分工

| 地址 | 大小 | 关键调用 | 角色（推断依据） |
|---|---|---|---|
| **0x3c9e0** | 880 B | `DragGesture.Value.predictedEndLocation` + `withAnimation` + `SwiftUI.Angle.animatableData` get/set + `AudioServicesPlaySystemSound` | **环的 `onEnded`**：用「预测终点」决定松手后的吸附角度，带动画回落，并播放反馈音 |
| **0x3b4b8** | 1516 B | `Published._enclosingInstance(wrapped:storage:)` + `DragGesture.Value.location` + `State.wrappedValue` get/set | **环的 `onChanged`**：拖动过程中直接改 `RingState` 的 `@Published` 字段（`_scale/_offset/_rotationAngle/_selected`） |
| **0x4da70** | 664 B | `TapGesture(count:)` + `DragGesture(minimumDistance:)` + `onChanged` + `onEnded` | **环上的 tap + drag 复合手势**：轻点选 app、拖动转环 |
| **0x54f28** | 1248 B | `DragGesture(minimumDistance:coordinateSpace:)` + `StateObject` + `EnvironmentObject` + `onEnded` + `Material.ultraThick` | **浮窗拖拽面板**：拖动整个浮窗，尽头用 `ultraThick` 材质做视觉反馈 |
| **0x3780c** | 728 B | `DragGesture` + `Image.resizable` + `onChanged` + `_FrameLayout` | **图标拖动**：拖动 app 图标到环上/回收站 |
| **0x555a4** | 964 B | `DragGesture.Value.location` + `_ConditionalContent` | **条件拖拽视图**：按手势状态在两个视图间切换 |

## 二、这解释了"手感"从哪来

1. **`predictedEndLocation`**（0x3c9e0）：松手时不是用当前位置，而是用系统预测的终点，
   这是"甩一下就到位"的来源。
2. **`withAnimation` + `Angle.animatableData`**：回弹是 SwiftUI 声明式动画，
   不是手写逐帧插值。
3. **`AudioServicesPlaySystemSound`**：吸附到槽位时有系统音反馈。
4. **`@Published` 直改**（0x3b4b8）：拖动过程每帧写 `RingState`，视图自动重绘。

## 三、与常量表的对应

`__const` 里的角度常量（±57.2958 / π 系列 / 360·720·1080）正好服务于这层：
- `predictedEndLocation` → 角度增量 → `fmod` 归一（RingView body, 0x3cd50）
- 吸附目标角度 → `withAnimation` 的 `Angle`
- ±720/±1080 说明**允许连续转多圈**再吸附

## 四、仍未拿到的

- 六个闭包内部的**具体阈值**（多快算"甩"、多远算"选中"）：需要逐条读
  `fcmp` + 常量加载，工作量约 6 × 150 行。
- 吸附算法（四舍五入到 1/N 圈？还是按图标中心？）


## 五、阈值与公式（第 11 轮补：逐指令读出）

### 5.1 环 `onChanged`（0x3b4b8）—— 以视图中心为原点

```
0x3b7a8  d11 = -0.5
0x3b7ac  d0  = d0 * -0.5
0x3b7b0  d10 = d9 + d0          →  x - size.width  * 0.5
0x3b7cc  d0  = d0 * -0.5
0x3b7d0  d11 = d8 + d0          →  y - size.height * 0.5
0x3b804  d8  = d10 - d8         →  相对中心的 x 偏移
0x3b808  d9  = d11 - d9         →  相对中心的 y 偏移
```

**结论**：拖动时先把触摸点换算成「相对视图中心」的向量（`location - size/2`），
再据此算角度与半径。`-0.5` 这个常量就是中心偏移，不是经验值。

其它确定项：

| 地址 | 内容 |
|---|---|
| 0x3b580 | `cmp w8, #2` —— 手势状态与 2 比较（对应 `GestureState.transition`） |
| 0x3b6a0 | `cmp x27, #0x3e7` —— 999 上限（与 RingView body 的上限一致） |

### 5.2 环 `onEnded`（0x3c9e0）—— 角度归一 + **×0.5 衰减**

```
0x3cb24  DragGesture.Value.predictedEndLocation      ← 用预测终点，不是当前位置
0x3cb30  sub_347bc                                     算出 -π..π 的弧度
0x3cb38  d9 = 57.29577951308232                      = 180/π
0x3cb3c  d8 = d0 * 180/π                             → 角度
0x3cb78  d0 = d8 - d0                                → 与当前角度的差
0x3cb80  fcmp d0, -180
0x3cb9c  fcmp d0,  180
0x3cbb0  d0 += -360                                  → 归一化到 (-180, 180]
0x3cbbc  d0 *= 0.0174533                             → 转回弧度
0x3cbc4  Angle.animatableData (get)
0x3cbcc  d0 *= 0.5                                   ★ 角度取一半
0x3cbd4  Angle.animatableData (set)
...
0x3cc14  d0 = d8 * 180/π
0x3cc18  d0 = d0 + d0                                ×2
0x3cc1c  fcmp d10, d0
0x3cc90  withAnimation { ... }
0x3cc9c  AudioServicesPlaySystemSound                ★ 吸附成功音
```

**两个关键结论**：

1. **`×0.5`**（0x3cbcc）：松手后环的旋转量只有手指位移的一半 —— 这是"转两倍才转一圈"的
   手感来源，也让长列表更容易精准停在目标上。这是一个**作者刻意的手感调参**，
   不是随手写的系数。
2. **`×2` 再比较**（0x3cc18–0x3cc1c）：因为前面取了 `×0.5`，判定吸附时又乘回 2，
   说明作者在写"半量旋转 + 全量判定"这一对逻辑时是配平的。

### 5.3 可直接写进源码的公式

```swift
// onChanged（0x3b4b8）
let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
let v = CGPoint(x: location.x - center.x, y: location.y - center.y)
let angle = atan2(v.y, v.x)                    // 弧度
let radius = hypot(v.x, v.y)
// 999 = 单环上限（0x3b6a0）

// onEnded（0x3c9e0）
var delta = (predictedAngle - currentAngle) * 180 / .pi
delta = fmod(delta + 180, 360) - 180           // 归一到 (-180, 180]
let target = Angle.degrees(delta * 0.5)        // ★ 半量旋转
withAnimation(.spring(...)) { ringState.rotationAngle = target.radians }
AudioServicesPlaySystemSound(...)              // 吸附音
```

> 上面这段已经可以替换 `RingView` / 手势闭包里的示意实现，
> 只剩 `spring` 的具体参数（response / damping）待定 —— 在 `__const` 里
> 0.825 / 0.86 / 0.95 三个值中挑，`VERIFY_PLAYBOOK` 里可用手感对照确认。


## 六、其余 4 个闭包的阈值（第 12 轮补）

### 6.1 浮窗拖拽（0x54f28）：起手距离 **20pt**

```
0x55070  fmov d0, #20.00000000
0x5507c  DragGesture(minimumDistance:coordinateSpace:)   ← minimumDistance = 20
0x55004  Material.ultraThick                              ← 拖动时背板材质
0x55128  .onEnded { ... }
0x551d8  View.gesture(_:including: .all)
```

**`20.0` 是立即数，确证**。也就是说手指移动超过 20pt 才开始拖浮窗，
低于这个值交给 TapGesture（点选），避免"想点一下却拖走了"。

### 6.2 条件拖拽视图（0x555a4）

```
0x55890  fmov d0, #-0.50000000      ← 同样是"减去一半尺寸"求中心
0x55894  cmp x8, #2                 ← 与 GestureState.transition 比较
0x555dc  SwiftUI._ConditionalContent(storage:)   ← 按状态二选一渲染
```

与环的 onChanged 是**同一套坐标约定**（`location - size*0.5`），
说明作者在整个手势层统一用"以视图中心为原点"。

### 6.3 环上的 tap+drag（0x4da70）

```
0x4dbf4  DragGesture(minimumDistance:coordinateSpace:)
0x4dc34  .onChanged
0x4dcb4  .onEnded
0x4dce4  TapGesture(count:)          ← count 来自闭包捕获，非立即数
```

`TapGesture.count` 与 `DragGesture.minimumDistance` 都是**从上层闭包捕获**的变量
（不是写死的），说明这两个值由调用方（视图）传入，不是全局常量。

### 6.4 图标拖动（0x3780c）

```
0x3796c  _FrameLayout(width:height:alignment:)
0x37908  Image.resizable(capInsets:resizingMode:)
0x37a2c  DragGesture(minimumDistance:coordinateSpace:)
0x37ad4  .onChanged
```

没有立即数阈值 —— `minimumDistance` 同样由调用方传入。

### 6.5 汇总：手势层的常量清单

| 位置 | 值 | 性质 |
|---|---|---|
| 0x55070 | **20.0** | 浮窗拖拽起手距离（立即数，确证） |
| 0x3b7a8 / 0x55890 | **-0.5** | 中心偏移（`location - size*0.5`，多处复用） |
| 0x3b6a0 / RingView | **999** | 单环图标上限 |
| 0x3cbcc | **0.5** | 环旋转半量衰减 |
| 0x3cc18 | **×2** | 吸附判定配平 |
| 0x3cb38 / 0x3cbb8 | **180/π / π/180** | 角度单位换算 |

其余 `minimumDistance` / `TapGesture.count` 均由调用方传入，不是常量。
