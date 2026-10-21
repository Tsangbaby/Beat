# 构建就绪度评估（Build Readiness）

> 结论：**不是"拿到就能 `make package`"**。需要补齐 4 类外部条件，其中 2 类本机无法验证。
> 这份文件把"能编译到哪一步、还差什么"逐条列清，避免你在 Mac 上第一次构建时踩空。

---

## 一句话回答

| 问题 | 回答 |
|---|---|
| 语法/类型层面能过编译吗？ | **大概率能**（已做静态引用审计 + 修补，见下） |
| 我验证过吗？ | **没有**。本机 Windows，无 Theos / iOS SDK / swiftc，无法执行 `swift build` |
| 能构建出可加载的 deb 吗？ | 需要 macOS + Theos + Orion + iOS 15+ SDK；工程已提供 Makefile/control/plists |
| 行为与原版一致吗？ | **不一致**。16 个 hook 的方法体仍是示意实现（报告 §11） |

---

## 本轮为"能编译"做的修补

### 1. 新增 `Sources/Stheno/PrivateSDK.swift`

这是**编译的硬前提**。Swift 要写 `ClassHook<SpringBoard>`，编译器必须先认识 `SpringBoard` 这个类型。
原工程链的是私有头文件，我们只有类名。

处理方式：用 Orion 官方推荐的 `@objc(真实类名)` 声明同名 Swift 类 —— 只用于静态类型检查，
运行期 `objc_getClass("SpringBoard")` 拿到的仍是系统类。

共声明 **19 个类型 + 5 个方法族**：

```
SpringBoard  SBApplication  SBApplicationController  SBIcon  SBIconView  SBIconController
_SBFluidSwitcherPanGestureRecognizer  SBGrabberTongue  SBFZStackParticipant
SBFluidSwitcherGestureManager  FBScene  FBSceneManager  FBSystemService
SBMainDisplaySceneManager  UIApplicationSceneDeactivationManager
BNPresentable  BNContentViewController  SBDeviceApplicationSceneViewController
UIStatusBarWindow  LSApplicationProxy  LSApplicationWorkspace
```

方法签名全部按「selector + ObjC type encoding」还原（来源：报告 §3.2 的编码列表，
例如 `_TtC6Stheno40_SBFluidSwitcherPanGestureRecognizerHook` 的 `B32@0:8@16@24` → `(id, SEL, id, id) -> Bool`）。

### 2. 修掉 3 处必然编译失败的错误

| 位置 | 原写法 | 问题 | 已改为 |
|---|---|---|---|
| `State.swift` `ReflectManager` | `@Environment(\.colorScheme) public var colorScheme` | `@Environment` 只能用于 `View`/`App`/`ViewModifier`，**放在 class 上是编译错误** | 普通存储属性 `public var colorScheme: ColorScheme = .light`，由视图赋值 |
| `State.swift` 末尾 | `@objc public protocol FBScene: AnyObject {}` | `FBScene` 是 ObjC **类**，用协议做 `ClassHook<T>` 的泛型参数会失败 | 删除协议声明，改为 `PrivateSDK.swift` 里的 `@objc(FBScene) class` |
| `SthenoController.swift` | `SBApplication(bundleIdentifier:)` / `Ivars(iconView).icon?.applicationBundleID` | 前者不存在该初始化器；后者 `Ivars` 的动态成员返回 `Any`，无法直接取属性 | 改走 `SBApplicationController.sharedInstance().application(withBundleIdentifier:)`；后者改成 `(iconView as? SBIconView)?.icon?.applicationBundleID` |

### 3. 静态引用审计

写了脚本对全部 `.swift/.xm` 做「大写标识符 − 项目内声明 − Apple 公开 API」的差集，
剩下的都是私有类型 —— 已全部进 `PrivateSDK.swift`。当前**没有悬空的私有类型引用**。

---

## 仍然可能导致构建失败的 4 个点（我无法验证）

### ① Orion 入口写法依赖版本

二进制里实际行为是 `DefaultTweak.activate(backend: .Substrate, hooks: [16 项])`。
本工程写成：

```swift
class SthenoController: Tweak {
    static var tweaks: [Tweak.Type] { [SthenoController.self] }
}
```

但不同 Orion 版本的 `Tweak` 协议要求不同（有的用 `@main struct … : Tweak`，
有的要求实现 `static var tweaks`）。**这是第一个要改的地方**，编译报错信息会直接告诉你。

### ② Orion 的 `orig` 成员名

`orig.applicationDidFinishLaunching(notification)` 这种写法要求 hook 方法与
目标方法同名同参。如果 Orion 版本要求显式 `orig.method(_:)` 或 `%orig`，
按报错调整即可——16 个 hook 的 selector 都已确证，改名字是机械工作。

### ③ 私有 API 签名可能与真机不符

我用 type encoding 还原了签名，但：
- `FBScene`/`FBSystemService` 的方法在不同 iOS 版本上参数个数会变；
- `SBFZStackParticipant.activationState` 我声明成 `Int`，真实类型是 `enum`；
- `LSApplicationWorkspace.enumerateApplications(ofType:block:)` 的 block 签名可能带 `NSError`。

对策：这些方法**只影响 hook 是否注册成功**，不影响整个 dylib 的编译。
若某条 hook 注册失败，Orion 会在日志里报 "method not found"，删掉对应方法即可。

### ④ 缺少链接期私有框架

Makefile 里已列 `FrontBoard / BaseBoard / BackBoardServices / SpringBoardUI` 等。
若 Theos 的 SDK 里没有这些 `.tbd`，需要在 Makefile 里补 `-undefined dynamic_lookup`
（tweak 常规做法，可绕过框架 tbd 缺失）：

```make
Stheno_LDFLAGS = -undefined dynamic_lookup
```

---

## 建议的第一次构建顺序

```bash
# 1) 先只编「相机」那一个模块 —— 它 100% 还原、只依赖 Foundation + substrate
#    改 Makefile 的 TWEAK_NAME 只留 SthenoCamera
make package

# 2) 相机跑通后，再编 SthenoKeyboard（ObjC，依赖 UIKit，签名已核对）

# 3) 最后编主模块：先把 Hooks/ 下 16 个文件临时移走，
#    只留 Tweak/Global/Environment/DeviceInfo/State/Geometry/Reflection/UI
#    确认「空壳能加载」——这一步验证的是 Orion 入口写法 + 私有类型声明

# 4) 再把 Hook 一个一个加回来，每加一个看日志
```

关键心态：**先用"空壳 + 无 hook"验证工程骨架，再逐个加 hook**。
主模块一次全量编译，报错会淹没在 SwiftUI 泛型推断里，很难定位。

---

## 我能确定的部分

- 三个 dylib 的**注入目标与 plist filter** 与原包一致（可直接用）。
- `control` 与原包逐字一致。
- `SthenoCamera` 的逻辑是逐指令还原的，**编出来行为就该是原版**。
- 全部类型名/字段名/枚举 case/常量是确证的，不存在"编造的类型名"。
- 唯一编造的是**方法体**（已在每个文件头标注 ⚠️）。
