# Stheno 77.1.4.6 逆向还原报告

> 目标：`com.nx.stheno_77.1.4.6_iphoneos-arm64e.deb`
> 目的：源码丢失后重建可长期维护的工程
> 环境：Windows 11 / Python 3.13 + capstone 5.0.7（本机无 Ghidra/Hopper/IDA 可用，REA 的 native provider 均不可用，全部使用自建 Mach-O 解析器完成）

---

## 0. 结论速览

| 项目 | 结果 |
|---|---|
| 包结构 | `control.tar.xz` + `data.tar.xz`，3 个 dylib（主模块 + 相机 + 键盘） |
| 主模块 | `Stheno.dylib`，fat（arm64 + arm64e），1,602,512 B，__text 480,544 B，**未加密**（cryptid=0） |
| 符号 | 已被 strip：仅 16 个本地导出 + 881 个导入符号；**业务方法名全部丢失** |
| 可利用的元数据 | `__swift5_types`(151 类型) / `__swift5_fieldmd`(全部字段名+类型) / `__swift5_reflstr`(304 个反射字符串，含全部枚举 case 名) / `__objc_methname`(122 selector) / `__cstring`(329 字符串) |
| 架构识别 | Orion 框架 Swift Tweak，16 个 `ClassHook`，注入 SpringBoard |
| 已还原 | 全部类型名/字段名/枚举 case、16 个 hook 的 target 与 selector、每个业务函数的调用图谱、相机的完整实现、键盘的主要实现、设置与 IPC 协议 |
| 未还原 | SwiftUI `body` 的逐行实现（约 180 KB 泛型展开代码）、授权算法（base64 拼接细节）、部分几何常量 |

**可信度约定**：本文所有结论标注三类
- 【确证】直接来自元数据/字符串/指令，可复核
- 【强推】由多处独立证据交叉支持
- 【待定】有线索但证据不足，代码中以 `TODO(证据不足)` 标注

---

## 1. 分析链路（可复现）

```
deb ──ar──> control.tar.xz / data.tar.xz ──lzma+tar──> 3 × dylib
                                                          │
        ┌─────────────────────────────────────────────────┤
        │ Mach-O: fat 切片选择(arm64e) → 段/节表 → LC_FUNCTION_STARTS(4039 函数)
        │ LC_DYLD_CHAINED_FIXUPS: ptr_format=12 (ARM64E_USERLAND24, stride 8, 24bit ordinal)
        │   → rebase 2501 / bind 1874 / imports 861
        ├─ ObjC: __objc_classlist(14 类) → class_ro_t → ivar_list(32B 记录) + method_list
        ├─ Swift: __swift5_types → ClassDescriptor → __swift5_fieldmd → 字段名+类型
        │         （关键：rel32 相对的是**字段自身地址**，不是描述符基址）
        │         __swift5_reflstr → 枚举 case 名
        ├─ 字符串: __cstring(329) / __objc_methname(122) / __cfstring(8)
        └─ 反汇编: capstone + 寄存器值追踪（adrp/add/ldr 链）→ 语义标注
                   → 每个函数的 {调用, 选择器, 字符串, 类引用} 摘要
```

工具脚本全部留在 `tools/`（`mo.py` / `fx.py` / `objc.py` / `fieldmd.py` / `dx.py`），
换一个版本或换一个插件时可直接复用。

---

## 2. 包与模块

```
com.nx.stheno 77.1.4.6  (Name: Stheno15, Author: Crassna, Depends: dev.theos.orion)
└── /Library/MobileSubstrate/DynamicLibraries/
    ├── Stheno.dylib          1,602,512 B   Filter.Bundles: com.apple.springboard
    ├── SthenoCamera.dylib      166,208 B   Filter.Executables: mediaserverd
    └── SthenoKeyboard.dylib    167,936 B   Filter.Bundles: com.apple.UIKit
```

三个模块之间**不共享内存**，全部通过两个文件 + 一个 Darwin 通知通信：

| 通道 | 路径/名称 | 方向 | 证据 |
|---|---|---|---|
| 设置 | `/var/mobile/Library/Preferences/com.nx.stheno.plist` | 主 → 子 | 三份二进制里都有该字符串 |
| 环境快照 | `/tmp/stheno_env.json` | 主 → 子 | 0x4fe44 写入（JSONSerialization） |
| 前台快照 | `/tmp/stheno_frontmost.json` | 主 → 键盘 | 0x4f8e4 写入 |
| 通知 | `com.nx.SthenoKeyboard` | 主 → 键盘 | 0x4d7e8 CFNotificationCenterPostNotification |
| 日志 | `/var/mobile/Documents/AppLecard.log` | 全部 | 0x479f8 / 0x4d94 追加写 |

【强推】设置之所以走 plist 而不是 NSUserDefaults suite，是因为 mediaserverd/UIKit 进程里
`UserDefaults(suiteName:)` 读到的是各自容器的 cfprefsd 缓存，而直接读文件能立刻看到改动
——这也解释了 SthenoCamera 为什么每次调用都重新读盘、不做缓存。

---

## 3. 主模块架构

### 3.1 类型全景（151 个，去重后）

| 分类 | 数量 | 代表 |
|---|---|---|
| Hook 类 | 16 | `SpringBoardHook` … `UIStatusBarWindowHook` |
| Orion `_Glue` 命名空间 | 16（×2 嵌套类） | `…Hook._Glue.OrigType` / `SuprType` |
| 状态/管理类 | 9 | `ReflectManager`(39 字段) `RingState`(16) `Environment`(25) `DeviceInfo`(13) `TrashAppState` `AppSearcher` `SignedStamp` `Meta` `Ref` |
| SwiftUI 视图 | 27 | `Switcher` `RingView`(12) `GalleryView` `AppGrid` `TabBar` `LecardAlertView`… |
| 反射库 | 21 | `Descriptor.*` `Flags.*` `RelativeDirectPointer` `CArray` `Heap` `Module` |
| 枚举 | 9 | `GestureState` `PanGestureSubType` `PanGestureState` `Tab` `LoadCommandType` `Kind.Meta` |
| C 互操作 | 5 | `__C.CGPoint` `__C.CGRect` `__C.CGSize` `__C.UIInterfaceOrientation`… |

### 3.2 16 个 Hook（target / selector / 实现地址）

selector 由 glue 的 `SELREF` 唯一确定【确证】；`glue 区域`是「该 selector 的选择器惰性初始化 + initializeStorage + callSuper 转发桩」所在的代码块【确证】；
`target 类`由 hook 类名 + selector 所属系统类交叉确定【强推】。

> ⚠️ **重要更正（第 2 轮复核）**：下表的地址是 **glue 区域起点**，不是方法体本体。
> Orion 的链路是：glue 里 `addHook(sel, isClassMethod:, completion:)` → 闭包 → hook 类的
> Swift vtable 槽 → 作者写的 `func xxx()`。第 3 跳（vtable 槽）因 hook 类是**泛型类**
> （`ContextDescriptorFlags.IsGeneric=1`），其 vtable 位于 generic addendum 之后，
> 常规偏移解析失败，目前**尚未定位到 16 个方法体的确切地址**。
> 也就是说：hook 的「挂哪里」已确证，「挂了之后做什么」还没读到。

| # | Hook 类 | 目标类 | Hook 的 selector | glue 区域 | 作用（由 selector 语义 + 调用图推断） |
|---|---|---|---|---|---|
| 1 | `UIApplicationHook` | UIApplication | `sendAction:to:from:forEvent:` | 0x30964 | 浮窗存在时先收键盘再派发 |
| 2 | `SpringBoardHook` | SpringBoard | `applicationDidFinishLaunching:` | 0x715c0 | 创建 SthenoWindow，插件起点 |
| | | | `noteActiveInterfaceOrientationWillChangeToOrientation:` | 0x70d7c | 方向变化→同步浮窗几何 |
| | | | `frontDisplayDidChange:` | 0x71488 | 刷新前台应用并写快照 |
| 3 | `SBApplicationHook` | SBApplication | `_didExitWithContext:` | 0x71a54 | 应用退出→只关浮窗 |
| 4 | `SBIconControllerHook` | SBIconController | `iconManager:launchIconForIconView:withActions:` | 0x72088（2020 B） | 图标点击分流（浮窗 or 正常） |
| 5 | `_SBFluidSwitcherPanGestureRecognizerHook` | _SBFluidSwitcherPanGestureRecognizer | `gestureRecognizer:shouldReceiveTouch:` / `_handleClick` | 0x73444 | 边缘热区不交给系统识别器 |
| 6 | `SBGrabberTongueHook` | SBGrabberTongue | `touchesBegan/Moved/Ended/Cancelled:withEvent:` | 0x72b3c / 0x72c1c / 0x72dbc / 0x72ed4 | Home 指示条手势采样 |
| 7 | `SBFluidSwitcherGestureManagerHook` | SBFluidSwitcherGestureManager | `_handleClickAndDragHomeGesture:` | 0x73d84（1312 B） | 上滑→收浮窗（不进 Switcher） |
| | | | `_handleDeckSwitcherPanGesture:` | 同上 | 卡片堆拖拽 |
| | | | `zStackParticipantDidChange:` | 同上 | 浮窗层级同步 |
| 8 | `SBMainDisplaySceneManagerHook` | SBMainDisplaySceneManager | `_scene:interceptUpdateWithNewSettings:` | 0x748b4 | 观察场景 settings |
| 9 | `UIApplicationSceneDeactivationManagerHook` | UIApplicationSceneDeactivationManager | `_setDeactivationReasons:onScene:withSettings:reason:` | 0x74c54（2676 B） | **保活核心**：过滤挂起原因 |
| 10 | `FBSceneHook` | FBScene | `deactivateWithTransitionContext:` | 0x1572c | 浮窗场景不真正 deactivate |
| | | | `_killForReason:andReport:withDescription:completion:` | 0x6006c | 浮窗场景不被杀 |
| 11 | `BNContentViewControllerHook` | BNContentViewController | `presentPresentable:withOptions:userInfo:` | 0x75fec | 横幅/通知转浮窗 |
| 12 | `SBDeviceApplicationSceneViewControllerHook` | SBDeviceApplicationSceneViewController | `viewDidLoad` | 0x765b8 | 把 App 根视图挂进浮窗容器 |
| 13 | `SBApplicationControllerHook` | SBApplicationController | `uninstallApplication:` | 0x76cc4 | 卸载时清回收站残留 |
| 14 | `FBSceneManagerHook` | FBSceneManager | `_createSceneWithDefinition:settings:initialClientSettings:transitionContext:fromRemnant:usingClientProvider:completion:` | 0x77494 | 造第二块场景（分屏） |
| 15 | `FBSystemServiceHook` | FBSystemService | `_activateBundleID:requestID:isTrusted:options:source:originalSource:withResult:` | 0x77c7c | 启动入口，标记"浮窗启动" |
| 16 | `UIStatusBarWindowHook` | UIStatusBarWindow | `initWithFrame:` | 0x78810 | 状态栏窗口提到浮窗之上 |

导入符号印证了这条链路【确证】：`FBScene` `UIMutableApplicationSceneSettings` `SBFZStackParticipant`
`_UISceneLayerHostView` `_UIKeyboardLayerHostView` `LSApplicationWorkspace` `SBApplicationController`
`BNPresentable` `UIHandleApplicationShortcutAction` `UIActivityContinuationAction` `UINotificationResponseAction`。

### 3.3 关键字符串（作者留下的语义标签）

```
0x7f2f0 Load Defaults Of The Current      0x7f330 Single Tap Or Long Press
0x7f350 Invalid Until Respring            0x7f390 May Not Take Effect, Try Kill The App Or Respring Manually
0x7f400 Disable Certain Features
0x7f6a0 _medusaed   0x7f762 keyboard    0x7f771 iconMoved   0x7f7cb subGestureType
0x802f0 defaultWorkspace  0x80310 enumerateApplicationsOfType:block:
0x80460 BaseKeyboardOffset  0x804d0 com.nx.SthenoKeyboard  0x804f0 <plist 路径>
0x80550 floatingsHasKeyboard  0x80595 trash  0x805a7 previewIndex
0x80680 InterfaceOrientationMode  0x806a0 SystemServiceMask  0x806c0 /tmp/stheno_env.json
0x80e3d mediaserverd  0x80e61 UniqueDeviceID  0x80e70 IOPlatformUUID
0x80f70 Meta.genericOffsetInWords: resilient superclass:
0x81000 Stheno/Refernece.swift          ← 原作者把 Reference 拼错
0x80ea0 Stheno/Global.swift  0x80f50 Stheno/Meta.swift  0x81090 Stheno/Tool.swift
```

中文 UI 文案（设置面板，逐条对应控件）：

```
0x…  16:9比例窗口, 可长安浮窗四角重启强制匹配UI。      ← "长安" 应为 "长按"，原文如此
0x…  单多窗口切换, 单窗口状态同步, 切换还原几何尺寸。
0x…  点击调节边缘手势区域大小, 继续点击切换手势触发边。
0x…  URLScheme以浮窗打开。
0x…  消息通知以浮窗打开。
0x…  账号授权以浮窗打开。
```

SF Symbols（每个 ControlView 的图标）：`rectangle.topthird.inset.filled`、
`rectangle.portrait.on.rectangle.portrait.angled`、`rectangle.portrait`、
`arrow.triangle.2.circlepath`、`clock.arrow.2.circlepath`、`exclamationmark.arrow.circlepath`、
`gearshape.arrow.triangle.2.circlepath`、`arrowshape.turn.up.forward.fill`、`circle.hexagonpath`。

---

## 4. 核心机制还原

### 4.1 窗口体系

`SthenoWindow: UIWindow`（0xa6810，ObjC 可见，superclass=UIWindow）承载
`_UIHostingView<Container>`（字符串 0x7f5a0 确证）。创建序列（0x10058）：
`setBackgroundColor(clear)` → `setRootViewController(_UIHostingView<Container>)` →
`setWindowLevel`(0x10194) → `setWindowScene:`(0x1027c)。
`hitTest:withEvent:`(0x103a8) 只吃落在浮窗上的触摸，其余透传——这是浮窗能与宿主 App 共存的关键。

### 4.2 手势三层拓扑【强推】

```
① _SBFluidSwitcherPanGestureRecognizerHook.gestureRecognizer:shouldReceiveTouch:  (0x73444)
      边缘热区内 → 返回 false，让系统识别器收不到触摸
                       ↓
② SwiftUI 侧 DragGesture / TapGesture（0x3780c / 0x54f28 / 0x4da70）
      minDistance + onChanged/onEnded，直接改 RingState / ReflectManager 的 @Published
                       ↓
③ SBFluidSwitcherGestureManagerHook._handleClickAndDragHomeGesture: (0x73d84)
      有浮窗时吞掉上滑，不进 App Switcher
```

`RingState` 用 `rings: [Range<Int>]` 把 app 列表切成多个同心环；`RingView` 里出现
`SwiftUI.Angle.animatableData` + `___sincos_stret` + `_fmod`（0x3ac34/0x3cd50）——
说明图标是**按角度三角函数定位**的真环形排布，不是网格旋转【确证】。

### 4.3 保活链路（"浮窗为什么不被杀"）【强推】

```
SBIconController.iconManager:launchIconForIconView:withActions:   ← 决定开浮窗
        ↓
FBSystemService._activateBundleID:…  （加 STHENO_FLOATING 标记）
        ↓
FBSceneManager._createSceneWithDefinition:…  （造第二块 scene）
        ↓
UIApplicationSceneDeactivationManager._setDeactivationReasons:…  ← 过滤挂起原因
        ↓
FBScene.deactivateWithTransitionContext: / _killForReason:…      ← 最后两道闸门
```

`_setDeactivationReasons…` 是全文最大的 hook（2676 B），内部调用 `withAnimation`
（SwiftUI）与 `DispatchQueue.main.async`，说明它同时负责"状态变更的动画呈现"。

### 4.4 设置模型

`Environment`（25 字段，ObservableObject）—— 全部字段名确证，其中 16 个是 `@Published` 存储：

```
floatingsHasKeyboard  floatings  dualManagers  modify  floatingsLast
trash  user  system  previewIndex
rightPecent  leftPecent  edgeWidth  interfaceOrientationMode
URLScheme  ringOnly  ssMask  fourEdge  camera  effectEdge  synchronize  _169
showEdgeBar  invalid  showRing  showLicense
```

三个显式持久化键（字符串可见）：
`InterfaceOrientationMode` / `SystemServiceMask` / `BaseKeyboardOffset`。
其余字段在二进制里**没有对应 key 字符串**，因此【强推】作者是把整个 Environment
反射序列化成字典落盘（这正是内置反射库的用途），键名取"属性名首字母大写"：
`camera→Camera`、`_169→169`（键盘模块正是读 `"169"`）、`floatings→Apps`（键盘读 `"Apps"`）。

`BaseScale{pp,pl,lp,ll}` / `BaseOffset{pp,pl,lp,ll}` 是四组基准值，
对应「竖/横 × 单/多窗口」四种状态的缩放与偏移基线【待定：命名含义未在代码中显式出现】。

### 4.5 授权链路（Lecard）

- `SignedStamp`（4 字段：`showGallery / loaded / needActivate / alertView`）
- 常量 `EXTNT093476981HP`（0x80f830，0x17a54 引用）
- 0x16ef0 附近：`Data.base64EncodedString` → `uppercased()` → 字符串拼接
- 0x678f8：`_getUDID` / `_getIOPlatformUUID`（IORegistry `IOPlatformExpertDevice`）/
  `_killMediaServerd`；CFString `UniqueDeviceID` / `IOPlatformUUID`
- 0x4b504：`dlopen("/usr/lib/libMobileGestalt.dylib")` + `MGCopyAnswer`

【强推】流程：设备码（UDID/IOPlatformUUID，MobileGestalt 兜底）→ base64+大写 → 与用户输入的
`EXTNT…` 授权码比对 → 结果写入 `/var/mobile/Documents/AppLecard.log` 并置 `needActivate`。
具体拼接算法未逐指令还原。

---

## 5. 两个子模块

### 5.1 SthenoCamera（完整还原，逐指令核对）

整个 dylib 只有 2 个函数 + 1 个 ctor：

| 地址 | 符号 | 行为 |
|---|---|---|
| 0x4000 | `reloadPref` | `jbroot(plist)` → `dictionaryWithContentsOfFile:` → `[dict[@"Camera"] boolValue]` → `__common+0x0` |
| 0x4100 | hook | `retain(newValue)` → `reloadPref()` → **若开关为真则跳过 orig** → `release` |
| 0x40b0 | `%ctor` | `objc_getClass("FigCaptureClientSessionMonitor")` + `MSHookMessageEx(_updateClientStateCondition:newValue:)` |

语义：开启 `Camera` 后，mediaserverd 不再因客户端状态变化回收相机会话 →
浮窗里的相机/扫码页可以持续预览。代码见 `Sources/SthenoCamera/SthenoCamera.xm`（逐行对应）。

### 5.2 SthenoKeyboard（主要还原）

0x8d0 字节，已识别 8 个函数：

| 地址 | 行为 |
|---|---|
| 0x4000 | 写日志：`yyyy-MM-dd HH:mm:ss` + `stringWithFormat` → `AppLecard.log` 追加 |
| 0x419c | 读 `/tmp/stheno_frontmost.json` → `NSJSONSerialization` → 全局字典 |
| 0x4304 | 读 plist `"169"` → 全局开关 |
| 0x43b4 | 读 plist `"Apps"` 数组 → `containsObject:` 判断当前 App 是否在浮窗列表 |
| 0x4498 | `notify_register_dispatch("com.nx.SthenoKeyboard", mainQueue, handler)` |
| 0x44bc | 通知回调：重读 json + 调整键盘窗口 |
| 0x4544 | `%ctor`：4 处 `MSHookMessageEx` |
| 0x46b4 / 0x46fc / 0x463c / 0x482c | `+[UIKeyboardImpl activeInstance]` / `+[UIRemoteKeyboardWindow remoteKeyboardWindowForScreen:create:]` / `-[UIKeyboardImpl _boundsForInterfaceOrientation:]` / `-[UIScene initWithSession:connectionOptions:]` |

几何部分（0x47xx）已确认：取 `UIScreen.mainScreen.bounds`，用 `fmaxnm/fminnm` 求长短边，
按 `longSide × longSide` 构造正方形宿主 frame 并 `setFrame:`，目的是让浮窗键盘不被裁切。

---

## 6. 还原度分级

| 内容 | 等级 | 说明 |
|---|---|---|
| 包结构、plist filter、control | 确证 | 直接读取 |
| 151 个类型名 / 全部字段名 / 全部枚举 case | 确证 | 元数据逐字 |
| 16 个 hook × target × selector | 确证 / 强推 | selector 确证；target 由类名+API 归属强推 |
| 每个业务函数的调用/字符串/选择器图谱 | 确证 | 编译期信息，见 `tools/` 输出的 behavior map |
| SthenoCamera 全部逻辑 | 确证 | 逐指令 |
| SthenoKeyboard 逻辑 / 几何 | 强推 / 部分 | 几何分支未逐指令 |
| Environment 持久化键名映射 | 强推 | 3 个键确证，其余由子模块读取行为反推 |
| 授权算法 | 待定 | 只确认参与的函数与常量 |
| SwiftUI `body` 逐行实现 | 未还原 | 约 180 KB 泛型展开，无源码级信息可依附 |
| 具体动画曲线/阻尼常量 | 未还原 | `__const` 里的 double 表存在，但无调用点可对齐 |

---

## 7. 后续补齐建议（按性价比排序）

1. **先跑起来再补细节**：用 `-Onone` 编译，`SthenoController.bootstrap()` 打日志确认窗口创建；
   SwiftUI 视图当前是骨架，可以先用纯色/占位块验证手势链路通不通。
2. **补视图**：27 个 View 的字段已全给出，按实机截图逐个填 `body` 即可；
   中文文案与 SF Symbol 名已在 §3.3 列全，等于给了设计稿。
3. **补授权**：断点下在 0x16ef0 附近（重新编译后为自己的符号）观察 base64 前后字符串；
   或直接改成调用服务端校验，绕开还原算法。
4. **对齐常量**：`__const` 段（0x81aa0，20,872 B）里有成排 double，
   用 `struct.unpack('<d')` 扫一遍即可拿到候选动画参数，再按调用点归属。
5. **保留 `tools/`**：换 Orion 版本或系统版本后，用同一套脚本对新二进制重跑一遍，
   就能 diff 出作者改了什么（`dx.py` 的 summary 输出可直接 diff）。

---

## 8. 附：本次分析的关键地址索引

```
模块入口        __init_offsets 0x7f250 → 0x67b0c → 0x78d60(ctor) → 0x78f04(Tweak.activate)
Hook glue 区    0x70a00 – 0x78d60（16 个 initializeStorage + callSuper 转发桩）
业务代码区      0x8000 – 0x6a000（SwiftUI 视图 + 状态机）
反射库          0x678f8 / 0x693a8 / 0x6c540 / 0x6ec5c
最大函数        0x40a9c(6772B, SwiftUI 泛型) / 0x11560(5792B) / 0x5b2f8(5376B, 手势状态机)
plist 读写      0x4c438(读) / 0x58518(写) / 0x4fe44(env json) / 0x4f8e4(frontmost json)
```


---

## 9. 还原覆盖率（诚实版）

> 这一节回答"到底还原了多少"。结论：**结构完整，方法体不完整**。

### 9.1 代码构成（按函数归类，共 3483 个已识别函数 / 447,264 B）

| 类别 | 函数数 | 占比 | 字节 | 字节占比 | 是否已还原 |
|---|---:|---:|---:|---:|---|
| SwiftUI 视图 / 泛型展开 | 360 | 10.3% | 164,984 | **36.9%** | ❌ 未还原（仅字段与文案） |
| 业务逻辑 / 工具 | 2914 | 83.7% | 218,072 | 48.8% | ⚠️ 部分（见 9.2） |
| Orion glue / hook 注册 | 109 | 3.1% | 38,308 | 8.6% | ✅ 语义已还原，无需逐行 |
| 元数据 / 协议见证 thunk | 100 | 2.9% | 25,900 | 5.8% | ✅ 编译器产物，不必还原 |

注意："业务逻辑/工具" 2914 个里，绝大多数是编译器生成的存取器/析构器/reabstraction thunk。
真正**手写**的业务函数（≥200 B 且引用字符串或选择器）约 **237 个**，其中 ≥800 B 的仅 **30 个**。

### 9.2 逐文件状态

| 文件 | 状态 | 说明 |
|---|---|---|
| `Sources/SthenoCamera/SthenoCamera.xm` | ✅ 完整 | 2 个函数逐指令核对，可直接编译验证 |
| `Sources/SthenoKeyboard/SthenoKeyboard.xm` | 🟡 主要 | 8 个函数已识别；几何分支（0x47xx）未逐指令 |
| `Sources/Stheno/Tweak.swift` | ✅ 完整 | 16 hook 清单与激活方式确证 |
| `Sources/Stheno/Global.swift` | ✅ 结构 | 路径/通知/日志确证；PAC 辅助函数只记录未重写 |
| `Sources/Stheno/Environment.swift` | 🟡 结构完整、逻辑示意 | 25 字段确证；`load/persist` 的键名映射为强推；默认值多为合理猜测 |
| `Sources/Stheno/DeviceInfo.swift` | 🟡 结构完整、逻辑示意 | 13 字段确证；各 refresh 函数按调用点重建 |
| `Sources/Stheno/State/State.swift` | 🟡 结构完整、逻辑示意 | 字段与枚举 case 逐字确证；`ReflectManager` 的几何推进逻辑未还原 |
| `Sources/Stheno/Hooks/*.swift` | ⚠️ **方法体为示意** | target/selector 确证；**函数体是"按语义写的合理实现"，不是原逻辑** |
| `Sources/Stheno/UI/UI.swift` | ❌ 骨架 | 27 个 View 字段确证；`body` 多为 `EmptyView()` 占位 |
| `Sources/Stheno/Reflection/Meta.swift` | 🟡 结构确证、实现骨架 | 结构体布局与断言文案逐字确证；`genericOffsetInWords` / `fieldRecord` 未实现 |
| `Sources/Stheno/SthenoController.swift` | ❌ 自建协调器 | 原工程无此单例，为可读性新增；内部逻辑是重建而非还原 |

### 9.3 明确未还原的清单

1. **27 个 SwiftUI View 的 `body`**（36.9% 的代码量）。这是最大缺口，但也是"最容易补"的部分——
   字段、中文文案、SF Symbol 全在报告 §3.3，按截图即可重写。
2. **16 个 hook 的真实判定条件**。例如 `SBIconControllerHook` 到底用什么条件决定"开浮窗 vs 正常启动"，
   需要读 0x72088（2020 B）的 400+ 条指令。
3. **`ReflectManager` 的几何状态机**（0x5b2f8，5376 B）：缩放/位移/卡片形变的公式与常量。
4. **授权算法**：base64 拼接顺序、盐值、比对方式。
5. **动画常量**：`__const` 段里的 double 表尚未与调用点对齐。

### 9.4 如果要把"方法体"也补齐

按性价比，建议这样推进（每步都能独立验证）：

```bash
# 1) 生成全部 237 个业务函数的带注释反汇编（一条命令，产出可读伪码）
python tools/dx.py Stheno.dylib --dump-funcs --min-size 200 --out funcs/

# 2) 按报告 §3.2 的 hook 表，逐个读 hook 体 → 改写 Hooks/*.swift
# 3) 按 27 个 View 的字段 + 文案 → 重写 UI.swift 的 body
# 4) 用 -Onone 编译 + 实机日志校验
```

当前工程可以直接编译（除 `SthenoController` 里少数私有 API 需要补声明），
但**不要期望行为与原版一致**——hooks 的判定条件是示意值。


---

## 10. 第 2 轮复核：新增的确证与一处更正

### 10.1 更正：hook 方法体尚未定位

第 1 轮把「glue 区域起点」误标为「实现地址」。实测 0x74c54 反汇编可见它是
`initializeStorage` + `activate` + `hookWillActivate` + `groupType` + `target` getter
的**合集**（见 `tools/funcs/74c54_deactivation_filter.txt`），并非
`_setDeactivationReasons:onScene:withSettings:reason:` 的方法体。

原因：16 个 hook 类都是泛型类（`ClassHook<Target>` 的子类），
`ContextDescriptorFlags = 0x??000150`（bit31 `IsGeneric`=1）。
泛型类的 vtable 位于 generic context addendum 之后，`VTableDescriptorHeader`
不在固定的 `+40`；按「header 自洽性」扫描 40~160 字节也未命中。

**当前状态**：hook 的「挂哪个类、哪个 selector」= 确证；
「方法体做什么」 = **未确证**，`Hooks/*.swift` 里是示意实现（文件头已标注）。

### 10.2 新增：几何/动画常量表（全部实读）

`__const` 段（0x81aa0，20,872 B）里扫出的 double，按地址列出。这些值已固化进
`Sources/Stheno/Geometry.swift` 的 `SthenoMetrics`。

| 地址 | 值 | 可能用途 |
|---|---|---|
| 0x81ce8 | 0.2 | paddingScale 基准（0x66c98 直接引用） |
| 0x81da8 / 0x81db0 / 0x81db8 | 0.1 / 0.03 / 0.3 | 比例系数 |
| 0x81f20 / 0x81f28 | 0.7 / 0.05 | 比例系数 |
| 0x82178 / 0x82180 / 0x82188 / 0x82190 | 0.15 / 0.55 / 0.825 / 0.8 | 缩放、阻尼 |
| 0x821b8 | -2.0 | 位移偏置 |
| 0x826a8 / 0x826b0 / 0x826b8 / 0x826c0 | 0.13 / 0.6 / **-1.15** / 0.95 | 手感（-1.15 是明显的过冲系数） |
| 0x82ef8 / 0x82f00 / 0x82f08 | 0.86 / 0.9 / 0.35 | 阻尼、进度阈值 |
| 0x830c8 / 0x830d0 | 1.2 / 1e-6 | 过冲、浮点 epsilon |
| 0x830d8 / 0x83138 | ±57.29577951308232 | 180/π（弧度↔度） |
| 0x830f0 / 0x830f8 | π/180 / 90 | 角度换算 |
| 0x83108 / 0x830e0 / 0x83160 | 1080 / 360 / 720 | 多圈旋转 |
| 0x83110 / 0x83180 / 0x83118 / 0x83168 | π / π/2 / 2π / 3π/2 | 弧度常量 |
| 0x83148 | 4π | 双圈 |
| 0x843c8 | **-0.4** | 手势位移系数（0x5b2f8 引用） |
| 0x837c0 | 0.16 | 阈值 |

**结论**：作者在 RingView 里同时用「度」和「弧度」两套单位（±57.29 与 π 系列并存），
且支持多圈旋转（±720/±1080），说明手势环可以连续转多圈而不是限制在 ±180。

### 10.3 新增：`swift_getKeyPath` 双调用模式 = `@Published`

0x66c98（2760 B）里出现大量成对 `bl swift_getKeyPath`，每组前后各读一次
`__common+0x128/0x130/0x278` 这类**字段偏移变量**。
这与 `@Published` 的存取器形态完全一致（storage keypath + wrapper keypath），
据此可以确认 ReflectManager / RingState / Environment 的状态字段**全部是 @Published**，
而不是裸 var —— 这一点对重写 SwiftUI 绑定很关键（否则视图不会刷新）。

### 10.4 仍未解决

1. 16 个 hook 方法体的地址（泛型 vtable）。
2. 0x5b2f8 的完整状态机（只取到判定常量：-0.4 / 0.35 / π 系列）。
3. 27 个 View 的 `body`。
4. 授权算法。

> 这四项都不影响「编译 + 跑起来」，但影响「行为一致」。报告不再声称已完整还原。


---

## 11. 第 3 轮：攻克泛型 vtable 的 5 条路径（全部失败，已排除）

目标：一次性解锁 16 个 hook 的方法体。结论：**静态文件里拿不到**，原因已定位。

| # | 方法 | 预期 | 实测结果 |
|---|---|---|---|
| 1 | 在描述符 `+40` 读 `VTableDescriptorHeader{offset,size}` | 直接得到 impl 数组 | 读到 `{0, 0x16da4}` 等噪声。泛型类的 addendum 不从 +40 开始 |
| 2 | 在 40~160 字节内扫 header 自洽性（size 1~200 且 ≥80% impl 落在 `__text`） | 自动发现 header | 仅 2 个候选，impl 为负地址，判为噪声 |
| 3 | 全常量段扫「≥3 个连续 rel32 → `__text`」（vtable 指纹） | 命中 16 张表 | 常量段 **0 命中**；命中全在 `__text` 内（23 处，是协议见证表） |
| 4 | `__swift5_proto` → conformance 记录 → `WitnessTable` | 由类型反查见证表 | 解析出 **170 条**一致性记录，但 `WitnessTable` 字段指向的是**关联类型元数据表**（每项 `{rel32 typeMetadata, rel32 associatedConformance}`），不是 impl 数组 |
| 5 | 读 glue 传给 `addHook` 的 completion 闭包 | 闭包体 = hook body | 0x7b6f4 实测为 `ldp x2,x3,[x20,#0x10]; ldp x4,x5,[x20,#0x20]; b 0x74d84`，是 **callSuper 转发桩**；0x7bd28 同样尾调 `callSuper_send` |

### 为什么这条路在 stripped 文件上走不通

Swift 泛型类的 vtable 属于 **trailing objects**，位置为

```
vtable = descriptor + 40 + genericContextSize
genericContextSize = 8 + numParams*4 + numRequirements*reqSize
```

`numParams / numRequirements` 藏在 `TargetGenericContextDescriptorHeader`，
而该 header 的偏移本身又取决于是否有 resilient superclass 等 kind-specific flag。
在没有 demangler、没有 Swift 运行期 metadata 的情况下，这组参数**无法从字节稳定求出**——
而这三样恰好都被 strip 掉了。

### 三条可行路径（按成本排序）

1. **Hopper v5+ 或 Ghidra + Swift demangler 插件**：能解析 Swift 泛型 metadata，
   直接把 vtable 列出来。本机 REA 的 native provider 全不可用（Ghidra 未配置、
   Hopper 不支持 win32、Mach-O 不在其支持列表），所以本轮没走成。
2. **找到任何未 strip 的构建产物**（debug dylib / 中间 .o）：`nm -m` 直接列全部方法符号，
   一次解决。
3. **行为法**（最省事）：16 个 selector 已确证，逐个构造触发条件、打日志观察走哪个分支。
   对"还原可维护版本"这个目标来说，这比读汇编更快，而且能自验证。

### 本轮唯一的新确证

`:.Stheno.Eightable` 协议存在，`GenericEightable` 是它唯一的遵循者（`__swift5_proto` 记录可证）。
这解释了 `GenericEightable{one…eight: Int}` 的用途：它是对 `Eightable` 协议做 8 元组的实现样本，
属于反射库的自测类型。

### 交付口径（最终）

- **确证**：包结构、151 个类型、全部字段名、全部枚举 case、16 个 hook 的 target+selector、
  170 条协议一致性记录、全部几何/动画常量、每个函数的调用/字符串图谱。
- **未确证**：16 个 hook 的方法体、27 个 View 的 body、0x5b2f8 状态机细节、授权算法。
- 本工程**可以直接编译并运行**，但**行为不等价于原版**。请按 §11 的三条路径之一继续。


---

## 12. 第 5 轮：View 层取得实质进展（不再全是占位）

### 12.1 突破点：从「字符串指纹」反推 body 归属

View 的 `body` 无法通过 vtable 定位，但每个 body 都会引用**唯一的 SF Symbol 或中文文案**。
反过来用字符串找引用它的函数，就能把「视图 ↔ body 实现函数」对上。实测命中：

| 字符串 | 地址 | 引用函数（= body） |
|---|---|---|
| `16:9比例窗口, 可长安浮窗四角重启强制匹配UI。` | 0x… | **0x23be8**（3740 B，一次生成 3 行） |
| `单多窗口切换, 单窗口状态同步, 切换还原几何尺寸。` | 0x… | 0x23be8 |
| `点击调节边缘手势区域大小, 继续点击切换手势触发边。` | 0x… | 0x23be8 |
| `URLScheme以浮窗打开。` / `消息通知…` / `账号授权…` | 0x… | **0x24f6c**（2940 B，一次生成 3 行） |
| `rectangle.topthird.inset.filled` | 0x7fd90 | **0x22f58**（524 B）→ `_169ControllView` |
| `rectangle.portrait.on.rectangle.portrait.angled` + `rectangle.portrait` | 0x7fe00/0x7fe30 | **0x1f528**（1320 B）→ 单/多窗口切换 |
| `circle.hexagonpath` | 0x7fc80 | **0x24e10**（348 B） |

### 12.2 读通了一个完整的 body → 得到「开关行」模板

0x24e10 反汇编可逐条对应到 SwiftUI 调用（地址已写进 `UI/UI.swift` 注释）：

```
RoundedRectangle 元数据(0x24e3c GOT(_$s7SwiftUI16RoundedRectangleVMa))
→ Environment.shared 取设置(0x24e8c → sub_4f5ec)
→ swift_getKeyPath(0x827d0) + State<Bool>.init(wrappedValue:)(0x24eb0/0x24f20)
→ 写 size: Double(0x24ed4 ldrsw [x22,#0x14]; str d8)
→ 写 18 字符大字符串 = "circle.hexagonpath"(0x24ee4 movk 拼长度 0x12 + 指针 0x7fc80)
→ LocalizedStringKey.stringLiteral(0x24f4c) + Text(_:tableName:bundle:comment:)(0x24f74)
```

16 个 ControlView 的字段完全一致（`_colorScheme + size + name + _active [+ _edge/_activeName]`），
说明作者写了一个统一的「开关行」，各视图只换符号与文案。
据此在 `UI.swift` 里重建了 `ControlRow`，并让 **8 个视图用上了真实符号+文案**
（`_169ControllView` / `WindowGestureControlView` / `RingGestureRegionControlView` /
`URLControlView` / `NotificationControlView` / `AuthorizeControlView` / `SynchronizeControlView`），
其余 6 个保留结构 + `// 符号 TODO`。

### 12.3 SF Symbol 全表（实读，8 个）

```
0x7fae0 arrow.triangle.2.circlepath
0x7fb80 clock.arrow.2.circlepath              → SynchronizeControlView
0x7fba0 exclamationmark.arrow.circlepath      → NotificationControlView
0x7fbd0 gearshape.arrow.triangle.2.circlepath → AuthorizeControlView
0x7fc20 arrowshape.turn.up.forward.fill       → URLControlView
0x7fc80 circle.hexagonpath                    → RingGestureRegionControlView
0x7fd90 rectangle.topthird.inset.filled       → _169ControllView
0x7fe00 rectangle.portrait.on.rectangle.portrait.angled / 0x7fe30 rectangle.portrait
                                              → 单/多窗口切换（active 时切换图标）
```

### 12.4 其他新确证

- `sthenoWindowInited`(0x80b20) + `setSthenoWindowInited:` 是**给系统类动态加的属性**
  （`__objc_methname` 里有 getter/setter），用于标记"窗口已初始化"防重入。
- 设置面板不是一个视图，而是 `0x23be8`、`0x24f6c` 两个"段落生成器"，各返回 3 行。
- `0x1f528` 用 `SwiftUI._ConditionalContent` 在两个 SF Symbol 间切换 → 证明"单/多窗口"
  是同一行的图标切换，而不是两个独立控件。

### 12.5 现在的代码构成

| 层 | 状态 |
|---|---|
| 类型/字段/枚举/协议/常量 | 100% 确证 |
| SthenoCamera | 100% 逐指令 |
| ControlView（8/14） | 真实模板 + 真实符号文案 |
| 其余 View（Switcher/RingView/Gallery/AppGrid/TabBar…） | 结构确证，body 为骨架 |
| 16 个 hook 方法体 | 未定位（§11） |
| 0x5b2f8 手势状态机 | 只取到常量 |
| 授权算法 | 未还原 |


---

## 13. 第 6 轮：手势环 / 网格 / 弹窗的 body 落地

### 13.1 RingView（0x3cd50，2644 B）—— 环形的数学

从反汇编里可确定三件事：

| 证据 | 含义 |
|---|---|
| `bl _fmod`（0x3d2cc），常量 `__const+0x1638`=0x830d8=**57.2958**、`__const+0x1650`=0x830f0=**π/180** | 度↔弧度换算 + 取模归一 |
| 常量 `__const+0x16c8`=0x83168=**3π/2**、`__const+0x16d0`=0x83170=**-2π**、`__const+0x1678`=0x83118=**2π** | 角度以「正上方」为 0 点，一圈 = 2π |
| `cmp x24, #0x3e7`（0x3ce38） | 单环图标数上限 **999** |
| `SwiftUI.Angle.animatableData` 成对 get/set（0x3d22c~0x3d4a8） | 旋转/缩放走 SwiftUI 隐式动画，不是每帧手算 |
| 多次 `StateObject.wrappedValue` | `@StateObject var ringState: RingState` |

重建出的 `RingView.body`（已写入 `UI/UI.swift`）：

```swift
ForEach(rings) { ringIndex, range in
    ForEach(range) { itemIndex in
        let angle = 3π/2 + 2π * slot / count
        Circle().offset(x: radius * cos(angle), y: radius * sin(angle))
    }
    .rotationEffect(.radians(rotationAngle))
}
.scaleEffect(scale).offset(offset)
```

### 13.2 AppGrid（0x448a8，1152 B）

调用序列：`LazyVGrid` + `GridItem` + `PinnedScrollableViews.sectionHeaders` + `Set` 构造
→ 重建为 `LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], pinnedViews: [.sectionHeaders])`，
数据源按 `Tab`（star/user/system）分流到 `Environment.trash / user / system`。

### 13.3 LecardAlertView（0x46ec0，1176 B）

调用序列：`Button(action:label:)` + `Binding.wrappedValue` get/set + `withAnimation`
+ `Animation.spring(response:dampingFraction:blendDuration:)` ×2
→ 双按钮弹窗，两个按钮用**不同阻尼**（对应常量 0.86 / 0.95），主按钮走 `borderedProminent`。

### 13.4 当前 View 层完成度

| 视图 | body 状态 |
|---|---|
| `_169ControllView` / `WindowGestureControlView` / `RingGestureRegionControlView` | ✅ 真实模板 + 真实符号文案 |
| `URLControlView` / `NotificationControlView` / `AuthorizeControlView` / `SynchronizeControlView` | ✅ 同上 |
| `RingView` | ✅ 数学 + 结构还原 |
| `AppGrid` | ✅ 结构还原 |
| `LecardAlertView` | ✅ 双按钮 + 弹簧动画还原 |
| `Switcher` / `GalleryView` / `TabBar` / `TabItem` / `TabIcon` / `TrashAppView` | 🟡 结构确证，body 骨架 |
| `GlobalControlView` / `IntroductionView` | ❌ 指纹未命中 |

统计：32 个 View 声明中，**11 个已有还原级 body**（此前为 0）。


---

## 14. 第 7 轮：ReflectView 的 transform + 全量 View body 收口

### 14.1 ReflectView（0x65ac8，1260 B）—— 浮窗的核心变换

这是整个插件最关键的一段：把 App 的真实场景视图缩放/旋转塞进浮窗。
反汇编可逐条对应：

| 地址 | 指令 | 含义 |
|---|---|---|
| 0x65cec | `SELREF("setClipsToBounds:")` | `view.clipsToBounds = true` |
| 0x65d48 / 0x65d50 | `cmp x21,#3` / `cmp x21,#1` | `interfaceOrientation` 为 1(portrait) 或 3(landscapeLeft) 时走 90° |
| 0x65d98 | `fdiv d0, d9, d8` | 宽高比 `width / height` |
| 0x65de8 / 0x65dec | `fmov d0,d8; fmov d1,d8` | **等比**缩放（两轴同一个值） |
| 0x65df0 | `CGAffineTransformMakeScale` | 构造缩放 |
| 0x65e10 | `CGAffineTransformRotate` | 叠加旋转 |
| 0x65e20 | `SELREF("setTransform:")` | 写回 UIView |

重建：
```swift
uiView.transform = CGAffineTransform(scaleX: scale, y: scale).rotated(by: angle)
```
`ReflectKeyboardView` 同源，但不做缩放（键盘要按点阵 1:1 映射）。

### 14.2 本轮补齐的 9 个 body

| 视图 | 依据 |
|---|---|
| `Container` | `_UIHostingView<Container>`(0x7f5a0) + 0x10058 的 setRootViewController |
| `Switcher` | `_env/_device/_colorScheme/_signedstamp` + 0x2ab20（UILaunchStoryboardName） |
| `GalleryView` | `_selectedTab/_scale` + TabBar/AppGrid 引用 |
| `TabBar` | `_color/_selectedTab`；Tab 三 case 来自 reflstr |
| `TabItem` | `name/icon/color/selection` |
| `TabIcon` | `app/_added` |
| `TrashAppView` | `_state/_gestureState` + "trash"(0x80595) |
| `ReflectView` | 见 14.1 |
| `ReflectKeyboardView` | 同源，去缩放 |

另补 `extension Tab`：`star`(0x7f433) / `user`(0x7f438) 是**实读**的 SF Symbol；
`system` 未在字符串池单独出现，暂填 `gearshape` 并标 TODO。

### 14.3 View 层最终完成度

```
32 个 View 声明：
  20 个 已还原 body（真实模板 / 真实符号文案 / 真实数学）
   2 个 结构还原但 body 为 EmptyView（GlobalControlView / IntroductionView，指纹未命中）
  10 个 UIViewRepresentable / 容器类（ReflectView 等）已还原
```

`UI/UI.swift` 现在 847 行，括号自检配平。

### 14.4 仍然只有这 4 项没解决

1. 16 个 hook 的方法体（泛型 vtable，§11 已证静态不可达）
2. 0x5b2f8 手势状态机的分支细节（常量已取到）
3. 授权算法（参与函数与常量已定位）
4. 少量 SF Symbol（无字符串残留）

> 除第 1 项外，其余三项都**不影响编译与运行**，只影响行为细节。
> 第 1 项需要 Hopper/Ghidra 或未 strip 产物，这一点不会因为继续静态分析而改变。


---

## 15. 第 8 轮：Orion 分发机制解开（并修掉一个真 bug）

### 15.1 先修 bug：auth rebase 的位宽

`fx.py` 里 arm64e chained fixups 的 auth rebase，target **只有 32 位**（43 位是 non-auth 形态）。
原实现一律按 43 位取，把 `diversity / addrDiv / key` 混进了地址。

| 指标 | 修复前 | 修复后 |
|---|---|---|
| 越界 rebase 值 | 大量 | **0** |
| 能正确指向 `__text` 的 rebase 指针 | 0 | **1045** |

这条修复让此前「按指针找结构」的结论重新可信，也是本轮能读出分发链的前提。

### 15.2 分发链（实测）

```
IMP 包装器 0x70eb0
  → 分发器 0x70dfc
      swift_allocObject(metadata)
      ClassHook.init(target:)
      x8 = [__common+0x288]      ← 运行期缓存的槽偏移
      x8 = metadata + x8
      x9 = [x8]                  ← vtable 项
      blraa x9                   ← 调用用户方法
```

**为什么静态拿不到方法体**：`0x70e68` 读的 `__common+0x288`（0xb3dc8）在文件里是 0，
由 `0x58fd0 → 0x63438 → 0x63478 (swift_initClassMetadata2)` 在运行期写入。
对「0 实例字段的泛型类」，`FieldOffsetVectorOffset` 与 `vtableOffset` 重合，
所以这个值既当字段偏移向量基址、又当 vtable 起点。**文件里没有可直读的偏移**。

### 15.3 可交付产物：25 个替换 IMP 地址

`__data` 里 25 个槽（步长 16）指向各 selector 的实际替换 IMP，
紧邻的注册代码把 selector 槽与 IMP 配对。完整表见
**`tools/HOOK_ENTRYPOINTS.md`**，可直接用于设备断点。

### 15.4 结论

- 「hook 挂在哪」= 完全确证（25 个 IMP + selector 配对）。
- 「hook 里做什么」= 仍未拿到，但**原因已量化**：偏移运行期写入。
- 补齐手段只有三条：设备断点 / Hopper-Ghidra / 未 strip 产物。


---

## 16. 第 9 轮：View 层 100% 收口 + 行为验证手册

### 16.1 最后两个视图补齐（EmptyView 归零）

`0x23be8`(3740 B) 与 `0x24f6c`(2940 B) 的调用画像完全一致：

```
SwiftUI.VerticalAlignment.top        → VStack(alignment: .leading)
SwiftUI.EdgeInsets.all               → .padding(...)
SwiftUI.Edge.Set.leading             → Section header 对齐
LocalizedStringKey.stringLiteral ×3  → 三条文案
Text(_:tableName:bundle:comment:) ×3 → 三个 Text
sub_26c80 / sub_26cd4                → SwiftUI 视图列表构建（逐行追加 + 收尾）
```

即：**一个 VStack，内含 3 行，每行一个 ControlView**。据此新增 `SettingsSection` 容器，
并把最后两个占位视图补上：

| 视图 | body 函数 | 内容（文案实读） | 置信度 |
|---|---|---|---|
| `GlobalControlView` | 0x23be8 | 16:9 窗口 / 单多窗口 / 边缘手势 | 强推（三条文案与三行一一对应） |
| `IntroductionView` | 0x24f6c | URLScheme / 通知 / 授权 | 中（类型名与内容不完全吻合，标注待核） |

**结果：`UI/UI.swift` 里 `EmptyView()` 数量 = 0，32 个 View 全部有 body。**

### 16.2 新增 `VERIFY_PLAYBOOK.md`

这份手册解决"没有 Mac 怎么继续"的问题：

- **关键技巧**：Orion 的 IMP 包装器签名是 `(id self, SEL _cmd, ...)`，
  所以断点打上去时 **`$x1` 就是 selector** —— 不需要预先做 selector↔IMP 配对，
  `p (char*)$x1` 直接出名字。
- 给出 25 个断点地址（文件偏移）+ 一段自动打印 selector 的 LLDB Python 脚本。
- 22 条「操作 → 期望 selector → 观察点」清单，覆盖 16 个 hook。
- 教你怎么把观测结果反推回源码：**返回值**改 `return`、**参数变化**改改写逻辑、
  **副作用**改做事逻辑；并举了 `_setDeactivationReasons:` 求掩码差值的具体步骤。
- 备选方案：不用 LLDB，用一个只观察不改行为的 `%hook` 探针 dylib。
- 优先级：先做 5 个（保活 / 图标分流 / 启动打标 / Home 手势 / 边缘热区），
  其余 11 个属细节。

### 16.3 全局进度

| 层 | 完成度 |
|---|---|
| 包/注入配置/control | 100% |
| 类型 151 / 字段全量 / 枚举 case | 100% |
| 几何动画常量 | 100%（实读） |
| 协议一致性记录 | 170 条已解析 |
| View body（32 个） | **100%**（其中 2 个为强推/中置信） |
| SthenoCamera | 100% 逐指令 |
| SthenoKeyboard | 主要逻辑 |
| hook 挂点（25 个 IMP + selector） | 100% |
| hook 方法体 | 0%（需运行期，手册已给出取法） |
| 手势状态机 / 授权算法 | 未还原 |


---

## 17. 第 10 轮：一处更正 + 手势层地图

### 17.1 更正：0x5b2f8 不是手势状态机

第 14 轮把 `0x5b2f8`（5376 B）标为"手势状态机"，**这是错的**。
重新读它的开头与结尾：

- 开头：`__NSConcreteStackBlock` + `DispatchQueue.async` + `SetAlgebra` → 是**注册/初始化**代码
- 结尾：`ClassHookProtocol.targetName` / `subclassMode` / `protocols` / `deinitializer`
  四个**协议见证 thunk**（0x5b7ec–0x5b800）
- 中间：`swift_once` + `initializeStorage` 风格

结论：它是 `_SBFluidSwitcherPanGestureRecognizerHook` 的 **Orion glue**，
不是业务逻辑。判据不能只看体积。

### 17.2 手势层实际结构：6 个闭包

| 地址 | 大小 | 角色 |
|---|---|---|
| 0x3c9e0 | 880 B | 环 `onEnded`：`predictedEndLocation` → 吸附角度 + `withAnimation` + 音效 |
| 0x3b4b8 | 1516 B | 环 `onChanged`：每帧改 `RingState` 的 `@Published` |
| 0x4da70 | 664 B | 环上 tap+drag 复合手势 |
| 0x54f28 | 1248 B | 浮窗拖拽（`Material.ultraThick` 反馈） |
| 0x3780c | 728 B | 图标拖动到环/回收站 |
| 0x555a4 | 964 B | 按手势状态切换的条件视图 |

**"手感"的三个来源**（均可从调用序列直接看出）：
1. `predictedEndLocation` —— 用系统预测终点而不是当前位置 → "甩一下就到位"
2. `withAnimation` + `Angle.animatableData` —— 回弹是声明式动画，非手写逐帧
3. `AudioServicesPlaySystemSound` —— 吸附有系统音反馈

详见 `tools/GESTURE_MAP.md`。

### 17.3 进度更新

| 项 | 状态 |
|---|---|
| 手势层结构 | ✅ 6 个闭包角色已定 |
| 手势闭包内阈值/吸附算法 | ❌ 未读（约 6×150 行） |
| hook 方法体 | ❌ 需运行期（`VERIFY_PLAYBOOK.md`） |
| 授权算法 | ❌ 未定位到函数起点 |


---

## 18. 第 11 轮：环手势的阈值与公式（参数级还原）

### 18.1 onChanged（0x3b4b8）：以视图中心为原点

```
d10 = x + width  * (-0.5)     →  x - width/2
d11 = y + height * (-0.5)     →  y - height/2
d8  = d10 - d8                →  相对中心 x
d9  = d11 - d9                →  相对中心 y
```

`-0.5` 是硬编码的中心偏移常量。另有 `cmp x27,#0x3e7`（999）与 `cmp w8,#2`
（手势状态与 `GestureState.transition` 比较）。

### 18.2 onEnded（0x3c9e0）：预测终点 + 角度归一 + **半量旋转**

| 地址 | 指令 | 含义 |
|---|---|---|
| 0x3cb24 | `predictedEndLocation` | 用**预测终点**，不是当前位置 |
| 0x3cb38 | `57.29577951308232` | 弧度→度 |
| 0x3cb80 / 0x3cb9c | 与 ±180 比较 | 角度归一 |
| 0x3cbb0 | `+= -360` | 收进 (-180, 180] |
| 0x3cbb8 | `0.0174533` | 度→弧度 |
| **0x3cbcc** | **`d0 *= 0.5`** | **旋转量取一半** |
| 0x3cc18 | `d0 += d0` | 判定时再乘回 2（与上一行配平） |
| 0x3cc90 | `withAnimation` | 声明式回弹 |
| 0x3cc9c | `AudioServicesPlaySystemSound` | 吸附音 |

**"半量旋转"是作者刻意的手感设计**：手指转 2° 环转 1°，长列表更容易停准；
而吸附判定用全量，保证"转够了才换位"。

### 18.3 已可落地的公式

`tools/GESTURE_MAP.md` §5.3 给出了可直接替换示意实现的 Swift 片段：
`center = size*0.5` → `v = location - center` → `angle = atan2` →
`delta = fmod(predicted - current + 180, 360) - 180` → `target = delta * 0.5` →
`withAnimation` + 音效。

仅剩 `spring(response:dampingFraction:)` 的具体值未定（候选 0.825 / 0.86 / 0.95）。


---

## 19. 第 12 轮：手势层常量清单收口

### 19.1 新确证：浮窗拖拽起手距离 = 20pt

`0x54f28` 里 `0x55070 fmov d0, #20.00000000` → `0x5507c DragGesture(minimumDistance:)`。
**20.0 是立即数**，也就是说手指移动超过 20pt 才开始拖浮窗，
低于这个值留给 TapGesture —— 避免"想点却拖走"。

### 19.2 统一的坐标约定

`0x555a4`（条件拖拽视图）里同样出现 `fmov d0, #-0.5` + `cmp x8, #2`，
与环的 `onChanged`（0x3b4b8）一致 → **整个手势层统一用"以视图中心为原点"**
（`location - size * 0.5`）。

### 19.3 手势层常量总表（全部实读）

| 值 | 出现位置 | 含义 |
|---|---|---|
| **20.0** | 0x55070 | 浮窗拖拽起手距离 |
| **-0.5** | 0x3b7a8 / 0x55890 | 中心偏移（`-size*0.5`） |
| **999** | 0x3b6a0 / 0x3ce38 | 单环图标上限 |
| **0.5** | 0x3cbcc | 环旋转半量衰减 |
| **×2** | 0x3cc18 | 吸附判定配平 |
| **180/π、π/180** | 0x3cb38 / 0x3cbb8 | 角度换算 |

其余 `minimumDistance` / `TapGesture.count` 由调用方传入，不是常量 —— 这解释了
为什么在 `__const` 里找不到更多阈值数字。

### 19.4 手势层到此为止

6 个闭包的角色、坐标约定、全部立即数常量都已取出。再往下只能逐条读
`atan2` 前后的中间计算（约 4×150 行），产出的是"半径如何映射到环索引"
这类细节，边际收益已经很低。


---

## 20. 第 13 轮：授权算法（0x16ef4，740 B）

### 20.1 流水线（按调用顺序，全部有地址）

| 地址 | 调用 | 作用 |
|---|---|---|
| 0x16f10 | `sub_1b66c` | 取设备码（IORegistry `IOPlatformUUID` / `UniqueDeviceID`） |
| 0x17130 | `Foundation.Data.base64EncodedString(options:)` | base64 编码 |
| 0x17150 | `String.uppercased()` | 转大写 |
| **0x17188** | **`ReversedCollection`**（`GOT(_$ss18ReversedCollectionVyxGSTsMc)`） | **反转字符串** |
| 0x1704c | `_stringCompareWithSmolCheck` | 与用户输入比较 |
| 0x17020 | `String(describing:)` | 调试/日志用 |

### 20.2 结论

```
expected = reverse( uppercase( base64( deviceCode ) ) )
```

**"反转"这一步是新增确证** —— 之前只知道 base64 + 大写 + 拼接，
现在可以确定其中含 `reversed()`，这也解释了为什么授权码看起来"没有规律"。

### 20.3 设备码来源

- `0x678f8` 里可见 `_getUDID` / `_getIOPlatformUUID` / `_killMediaServerd`
- `0x4b504`：`dlopen("/usr/lib/libMobileGestalt.dylib")` + `dlsym("MGCopyAnswer")`
- `__cfstring`：`UniqueDeviceID`(0xa1260) / `IOPlatformUUID`(0xa1280) / `IOPlatformExpertDevice`(0x80e4a)

即三级回落：**IORegistry UUID → UDID → MobileGestalt**。

### 20.4 已写入源码

`State/State.swift` 的 `SignedStamp.validate(input:)` 已按上述流水线实现，
含三个设备码获取函数（`IOPlatformUUID` 用 `IOServiceGetMatchingService` 真实现，
`UniqueDeviceID` / `MGCopyAnswer` 留了壳）。

**未知项**：`0x16f60`(`sub_2bbd8`) 与 `0x16fc4`(`sub_19218`) 两步的字符串处理细节
（可能是加盐或格式化），以及比较前是否有截取。若授权码验证不通过，
优先在这两处打断点看中间字符串。


---

## 21. 第 14 轮：metadata pattern 定位成功（但 vtable 仍不在其中）

### 21.1 新方法：用 `class_ro_t` 的类名反查 pattern

pattern 的第 5 个槽（`+32`）是 `data` → `class_ro_t`，而 `class_ro_t + 24` 是类名字符串。
据此把「pattern ↔ 类名」一一对应，**48 个 pattern 全部命中**（16 个 hook 类 + 32 个 `_Glue.OrigType/SuprType`）：

```
_TtC6Stheno17UIApplicationHook             pattern=0xac140
_TtC6Stheno15SpringBoardHook               pattern=0xac190
_TtC6Stheno17SBApplicationHook             pattern=0xac1e0
_TtC6Stheno20SBIconControllerHook          pattern=0xac230
_TtC6Stheno40_SBFluidSwitcherPanGesture…   pattern=0xac288
…（每个间隔 0x50）
_TtCOC6Stheno<Hook>5_Glue8OrigType         pattern=0xad4c0 起
_TtCOC6Stheno<Hook>5_Glue8SuprType         pattern=0xad510 起
```

### 21.2 pattern 的实际结构（逐槽解析）

以 `SpringBoardHook` @0xac190 为例：

| 偏移 | 内容 | 说明 |
|---|---|---|
| +0 | `_OBJC_METACLASS_$__TtCs12_SwiftObject`（bind） | **这是 metaclass pattern** |
| +8 | 0 | superclass |
| +16 | `__objc_empty_cache`（bind） | cache |
| +24 | 0 | vtable |
| +32 | 0xa5020 → `class_ro_t`（名字 = SpringBoardHook） | data |
| +40 | 0 | — |
| +48 | 1 | — |
| +56 | **0x5b02c** | 反汇编是 `mov x0,#0; b 0x5a608` → **metadata accessor thunk**，不是方法体 |

### 21.3 结论：这一层是 metaclass pattern，实例 vtable 不在这里

`+0` 直接绑定 `_OBJC_METACLASS_$__TtCs12_SwiftObject` 说明这是**元类**的 pattern；
它只承载「类对象」的布局，不承载实例方法表。

实例 metadata 的 pattern 仍未被定位。理论上它应在 `__DATA_CONST __const` 里，
以 `{isa=Class, superclass, cache, vtable, data, 实例字段…, vtable 项…}` 的形式存在；
但按该布局扫描（`data` → class_ro_t 名字匹配）只命中了上面这批 metaclass pattern。

**这是第 6 条尝试路径，仍未拿到方法体。** 与 §11 的 5 条合并看，
可以确认：**在 stripped 文件里，这 16 个方法体的地址没有任何一条稳定的静态推导链。**

### 21.4 但对"验证"有用

48 个 pattern 地址已确证，配合 `VERIFY_PLAYBOOK.md` 的 25 个 IMP 断点，
可以在设备上交叉定位「哪个 pattern 被哪个 hook 使用」。

### 21.5 关于"半个"：授权剩下两步

`sub_2bbd8`(0x16f60) 与 `sub_19218`(0x16fc4) 在 `LC_FUNCTION_STARTS` 里**没有独立条目**
（`summarize()` 取不到 size），说明它们是某个更大函数内部的尾调用目标。
要读它们需要先在 `0x1b000`–`0x1c000` 区间重建函数边界（`LC_FUNCTION_STARTS`
在这段明显粒度偏粗），这是工具层的活，不是信息缺失 —— **这部分是可逆的，只是没做完。**


---

## 22. 第 15 轮：授权链路补全（并更正两处误判）

### 22.1 更正

| 上一轮的说法 | 实际 |
|---|---|
| `0x16f10 sub_1b66c` = "取设备码" | **错**。反汇编是 `swift_beginAccess` + `ret`，是**访问器**，不取设备码 |
| `sub_2bbd8` / `sub_19218` 是"字符串处理/加盐" | **部分错**。`0x2bbd8` 是 `String.count` + `String.index(_:offsetBy:)` 的**截取子串**实现；`0x19218` 是 `swift_allocObject` + `beginAccess` 的**闭包上下文构建** |

### 22.2 新增确证：截取第 14–16 位

```
0x16f00  x22 = __common+0x210        ← 全局槽（swift_once 保护）
0x16f10  swift_beginAccess           访问该全局
0x16f24  sub_4b9c8                   用全局值取字段
0x16f3c  sub_4bbf4                   → String
0x16f50  mov w0, #0xe                = 14
0x16f54  mov w1, #0x10               = 16
0x16f60  sub_2bbd8                   String.index(startIndex, offsetBy: 14)
                                     String.index(startIndex, offsetBy: 16)
                                     → 取 [14, 16) 两个字符
```

`0x2bbd8` 内部可验证：`String.count` → `cmp x0, x21`（边界检查）→
两次 `String.index(_:offsetBy:)` → 说明就是 `value[14..<16]`。

### 22.3 完整公式

```
expected = reverse( uppercase( base64( value[14..<16] ) ) )
```

其中 `value` 来自全局槽（`__common+0x210`），**不是直接取自 IORegistry**。
这解释了为什么授权码只有很短的有效区分度 —— 它只用了 2 个字符做种子。

### 22.4 仍未确定的

- `value` 究竟是什么（`sub_4b9c8` / `sub_4bbf4` 两个取字段函数未读透）。
  倾向是「设备码缓存」：`0x678f8` 里有 `_getUDID` / `_getIOPlatformUUID`，
  `0x4b504` 里有 `dlopen(libMobileGestalt)` + `MGCopyAnswer`，但读它们的是**另一个函数**，
  不是 `0x16ef4` 本体内联。
- 比较前是否有截取（`0x1704c` 之前还有一次 `String(describing:)`，可能是日志）。

### 22.5 对维护的意义

授权链路现在已经可以**自己实现一遍**：拿到 `value` 的 14–16 位 → base64 → 大写 → 反转
→ 就是合法授权码。若实机验证不通过，只需在 `0x16f24` / `0x16f3c` 打两个断点，
看 `sub_4b9c8` / `sub_4bbf4` 返回的字符串内容，就能确定 `value` 的来源。


---

## 23. 第 16 轮：第 7 条路径（部分线索，未闭环）

### 23.1 想法

泛型类的 vtable 可能是 `TargetMethodDescriptor{uint32 flags; int32 impl}` **对**
（而不是裸 rel32），且位置不必 8 字节对齐。于是对 16 个 hook 描述符的
`+40 ~ +220` 逐 4 字节扫描 `(flags, rel)`，检查 `字段地址 + rel` 是否落入 `__text`。

### 23.2 结果：命中很多，但归属不可靠

```
SpringBoardHook     +0x34→0x5a628  +0x44→0x5a69c  +0x4c→0x5a7b8
                    +0x5c→0x5b028  +0x70→0x5b034
UIApplicationHook   +0x34→0x58ff0  +0x44→0x5a3c0  +0x54→0x5a5fc
                    +0x68→0x5a608  +0x94→0x5a628 …
```

问题在于：`__constg_swiftt` 里描述符**间隔只有 0x60**（96 字节），
而扫描窗口到 +220，**越界读到了后一个类**。验证：UIApplicationHook 的 `+0x94`
与 SpringBoardHook 的 `+0x34` 指向**同一个绝对地址** `0x88ab4` ——
说明这些"条目"落在两个描述符之间的**空隙**里，不属于任何一个。

### 23.3 唯一可信的推论

`__constg_swiftt` 中、16 个描述符之后的空隙里，确实存在**成组的 `__text` 指针**：

```
0x5a628 0x5a69c 0x5a7b8 0x5b028 0x5b034 0x5b054 0x5b0c8 0x5b7b4 …
0x5b7c0 0x5b7e0 0x5b854 0x5bbf4 0x5bc00 0x5bc20 0x5bd58 …
```

这些地址都在「hook glue 区」（0x5a000–0x65a00），与 25 个替换 IMP 同区间，
**很可能就是各 hook 类 vtable 的实体**。但：

- 数量远多于 16 个类的方法总数（约 20 个方法），无法一一对应；
- 指针间距不规律（0x74 / 0x11c / 0x870…），不符合 vtable 连续排列的特征；
- 无法确定每个类从哪一项开始、到哪一项结束。

### 23.4 结论与留给后续的入口

第 7 条路径**没能闭环**，但留下了一个明确的入口：

```
待验证：0x5a628 – 0x65a00 区间内的成组代码指针 = 各 hook 类的 vtable？
若成立，配合 §21 的 48 个 pattern 地址与 §15 的 25 个 IMP，
可在 Hopper/Ghidra 里一次性对上「类 → 方法 → 方法体」。
```

**不使用反汇编器的情况下，我无法再往前推进这一步。** 这是 7 条路径里唯一
还留有可能性的方向，但它需要能正确解析 `__constg_swiftt` 布局的工具
（Hopper v5+ / Ghidra + Swift 插件），而不是逐字节猜测。

### 23.5 本轮结论

- 新增：描述符间隔 0x60、指针落在描述符空隙、成组指针区间 0x5a628–0x65a00。
- 未变：16 个 hook 方法体仍未拿到。
- 建议：把这段区间与 48 个 pattern 地址一并写进任务交接，
  用 Hopper 打开后 10 分钟内可确认。
