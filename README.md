# Stheno15 — 源码还原工程

> **Phase-one buildability candidate, not a completed restoration.** See [PHASE1.md](PHASE1.md) for authorized changes, unresolved behavior and verification boundaries. Historical claims below are not current build/device proof.

原插件：`com.nx.stheno` 77.1.4.6（Name: Stheno15 / "Medusa!"，作者 Crassna）
本目录是**从 arm64e 二进制反推出来的工程骨架**，用于源码丢失后的长期维护。

> 先读 [`RESTORATION_REPORT.md`](RESTORATION_REPORT.md)：
> 里面写清了哪些是确证、哪些是推断、哪些还没还原。

---

## 目录

```
Stheno-Restored/
├── Makefile                       Theos 构建（3 个 dylib）
├── control                        Debian 包元数据（与原包一致）
├── layout/Library/MobileSubstrate/DynamicLibraries/
│   ├── Stheno.plist               Bundles: com.apple.springboard
│   ├── SthenoCamera.plist         Executables: mediaserverd
│   └── SthenoKeyboard.plist       Bundles: com.apple.UIKit
├── Sources/
│   ├── Stheno/                    Orion Swift（注入 SpringBoard）
│   │   ├── Tweak.swift            HookGroup 声明 + 16 个 hook 清单
│   │   ├── SthenoController.swift Tweak 入口 + 全局协调器 + 手势状态机
│   │   ├── Global.swift           路径/通知/日志/jbroot/dyld 模块定位
│   │   ├── Environment.swift      25 项设置与运行时状态 + 落盘 + IPC
│   │   ├── DeviceInfo.swift       屏幕/键盘/方向基准
│   │   ├── State/State.swift      ReflectManager(39) / RingState(16) / 枚举
│   │   ├── Hooks/
│   │   │   ├── SpringBoard.swift  4 个 hook
│   │   │   ├── Switcher.swift     3 个手势 hook
│   │   │   └── Scene.swift        9 个场景/生命周期 hook
│   │   ├── UI/UI.swift            SthenoWindow + 27 个 SwiftUI 视图骨架
│   │   └── Reflection/Meta.swift  内置 Swift 运行时反射库
│   ├── SthenoCamera/SthenoCamera.xm      完整还原（逐指令）
│   └── SthenoKeyboard/SthenoKeyboard.xm  主要逻辑还原
└── tools/                         本次逆向用的脚本（可复用）
```

## 构建

```bash
export THEOS=/opt/theos
make package                     # 产出 com.nx.stheno_77.1.4.6_iphoneos-arm64e.deb
```

依赖：Theos + Orion（`dev.theos.orion >= 1.0.0`）+ iOS 15+ SDK。
主模块建议先用 `-Onone -g` 编译（Makefile 已设），方便对照报告里的地址。

> ⚠️ **先读 [`BUILD_STATUS.md`](BUILD_STATUS.md)**：这里列出了"能编译吗、还差什么"的逐条评估。
> 要点：本工程在 Windows 上**未经编译验证**；`Sources/Stheno/PrivateSDK.swift` 是编译硬前提
> （21 个私有类型声明）；Orion 入口写法与 `orig` 成员名可能需按你的 Orion 版本微调。
> 建议构建顺序：先 SthenoCamera（100% 还原）→ SthenoKeyboard → 主模块先去掉 Hooks 跑通骨架。

## 与原始工程的差异（重要）

1. **原始源码的方法名已被 strip**。本工程的 Swift 方法名是按调用点语义命名的，
   每个都在注释里标了二进制地址，便于核对。
2. **SwiftUI 的 `body` 未还原**（约 180 KB 泛型展开代码，无源码级信息）。
   27 个 View 的字段、文案、SF Symbol 名都已给出，按实机截图补 `body` 即可。
3. **16 个 hook 的方法体尚未定位**（第 2/3 轮复核的重要更正）。
   `Hooks/*.swift` 里的 target/selector 是确证的，但**函数体是示意实现**，
   文件头有 ⚠️ 标注。原因与 5 条已排除的路径见 `RESTORATION_REPORT.md` §11：
   hook 类是泛型类，vtable 在 generic addendum 之后；静态文件里只留 pattern，
   需要 Hopper/Ghidra 的 Swift 泛型支持，或一份未 strip 的构建产物。
4. **新增了一个协调器** `SthenoController.shared`。原工程里这些职责分散在
   `SthenoController`（Orion Tweak）与各 `ReflectManager` 上，为可读性做了集中。
5. **Orion 入口写法**：二进制中可见的实际行为是
   `DefaultTweak.activate(backend: .Substrate, hooks: [16 项])`。
   本工程用 `class SthenoController: Tweak` 表达；若你的 Orion 版本用
   `@main struct … : Tweak`，改这一处即可。
6. `Sources/Stheno/UI/UI.swift` 里的 ControlView 目前 `body` 是 `EmptyView()`，
   属于**占位**，不是原始实现。

## 已确证的量化信息

- `Sources/Stheno/Geometry.swift` 里的 `SthenoMetrics`：**每个常量都是从 `__const` 段实读的**，
  注释里标了地址。含 ±57.2958（180/π）、π 系列、±360/720/1080、0.825/0.95/-1.15 等。
- `tools/funcs/*.txt`：14 个核心业务函数的**带注释反汇编**（已按函数边界截断、
  只保留有语义的指令）。要还原 hook 方法体时，从这里读最快。
- `tools/fields.txt`：151 个类型的全部字段与类型。
- `tools/behavior_map.txt`：549 个函数的 {调用, 选择器, 字符串} 摘要。


## 如何继续还原

`tools/` 里的脚本是为"再分析一次"准备的：

```bash
PY=C:\Users\<you>\.workbuddy\binaries\python\envs\default\Scripts\python.exe
$PY tools/mo.py  path/to/Stheno.dylib          # 段/节/load command
$PY tools/objc.py path/to/Stheno.dylib         # ObjC 类/ivar/方法
$PY tools/dx.py  path/to/Stheno.dylib          # stub 表 + 函数摘要
```

想定位某个 selector 的实现体：用 `dx.summarize()` 得到 `函数 → {calls, sels, strs}`，
筛出引用该 selector 且体积最大的函数即为 hook 体（报告 §3.2 的表就是这么来的）。

## 免责

本工程仅用于**恢复自有项目的可维护性**。请自行确认在目标设备/系统上使用时的合规性。
