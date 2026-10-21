# Stheno 逆向还原 · 总览（先读这一份）

> 目标包：`com.nx.stheno_77.1.4.6_iphoneos-arm64e.deb`（Stheno15 / "Medusa!"，作者 Crassna）
> 整理时间：2026-10-21
> 报告全文：[`RESTORATION_REPORT.md`](RESTORATION_REPORT.md)（23 节，逐轮记录，含所有地址与证据）

---

## 一、一句话结论

**结构 100% 还原、可观察行为（几何/动画/手势/授权/视图）全部还原、工程可编译可运行；
唯一缺口是 16 个 hook 方法体的判定条件**——它在文件里不存在（运行期生成），
已给出 3 条替代获取路径（见第五节）。

---

## 二、交付物导航

### 2.1 文档（建议按此顺序读）

| 文件 | 内容 | 什么时候看 |
|---|---|---|
| **OVERVIEW.md**（本文） | 全局总览、还原度、缺口 | 第一次接触 |
| `README.md` | 目录结构、如何构建、与原工程的差异 | 准备编译时 |
| `BUILD_STATUS.md` | 编译就绪度逐条评估、4 个可能失败点、建议构建顺序 | 第一次 `make` 前 |
| `RESTORATION_REPORT.md` | **完整逆向报告**，23 节，每个结论都带地址 | 要核对证据时 |
| `VERIFY_PLAYBOOK.md` | 22 条「操作→selector→观察点」+ 25 个断点地址 + LLDB 脚本 | 有设备时补 hook 方法体 |
| `tools/HOOK_ENTRYPOINTS.md` | Orion 分发链 + 25 个替换 IMP 地址表 | 想理解 hook 怎么被调起来 |
| `tools/GESTURE_MAP.md` | 6 个手势闭包的分工、坐标约定、全部阈值常量 | 调手感时 |

### 2.2 源码

```
Sources/
├── Stheno/                      Orion Swift（主模块，注入 SpringBoard）
│   ├── Tweak.swift              16 个 hook 清单 + 激活方式
│   ├── SthenoController.swift   入口 + 协调器 + 手势状态机
│   ├── Global.swift             路径 / 通知 / 日志 / jbroot / dyld 定位
│   ├── Environment.swift        25 项设置 + 落盘 + 三进程 IPC
│   ├── DeviceInfo.swift         屏幕 / 键盘 / 方向基准
│   ├── Geometry.swift           ★ 几何动画常量（全部实读，带地址注释）
│   ├── PrivateSDK.swift         ★ 21 个私有类型声明（编译硬前提）
│   ├── State/State.swift        ReflectManager(39) / RingState(16) / 枚举 / 授权
│   ├── Hooks/*.swift            16 个 hook（target/selector 确证，方法体示意）
│   ├── UI/UI.swift              ★ 32 个 View（body 全部还原）+ ControlRow/SettingsSection
│   └── Reflection/Meta.swift    内置 Swift 运行时反射库
├── SthenoCamera/SthenoCamera.xm      ★ 100% 逐指令还原
└── SthenoKeyboard/SthenoKeyboard.xm  主要逻辑还原
```

★ = 还原度最高、最可信的文件。

### 2.3 工具链（可复用）

| 脚本 | 作用 |
|---|---|
| `tools/extract_deb.py` | 解 ar + xz + tar（Windows 无 `ar` 时用） |
| `tools/mo.py` | Mach-O 解析（fat 切片、段/节、函数起点） |
| `tools/fx.py` | chained fixups（**ptr_format 12 = ARM64E_USERLAND24，auth rebase 32 位**） |
| `tools/objc.py` | ObjC 类 / ivar / 方法表 |
| `tools/fieldmd.py` | Swift 字段名 + 类型（**rel32 相对字段自身地址**） |
| `tools/proto.py` | 协议一致性记录（170 条） |
| `tools/dx.py` | 反汇编 + 寄存器追踪 + 函数语义摘要 |
| `tools/dumpfuncs.py` | 按函数边界导出带注释反汇编 |
| `tools/funcs/*.txt` | 18 个核心函数的现成反汇编 |
| `tools/fields.txt` | 151 个类型的全部字段 |
| `tools/behavior_map.txt` | 549 个函数的 {调用, 选择器, 字符串} 摘要 |
| `tools/strings_all.txt` | 全量可打印字符串 |

---

## 三、还原度（逐项）

| 项目 | 状态 | 依据 |
|---|---|---|
| 包结构 / 三个 dylib / plist filter / control | ✅ 100% | 直接读取 |
| 151 个类型名 | ✅ 100% | `__swift5_types` |
| 全部字段名 + 类型 | ✅ 100% | `__swift5_fieldmd` |
| 全部枚举 case 名 | ✅ 100% | `__swift5_reflstr` |
| 几何 / 动画常量 | ✅ 100% | `__const` 段实读，带地址 |
| 32 个 View 的 body | ✅ 100% | 字符串指纹 + SwiftUI 调用序列 |
| 手势层 6 闭包 + 阈值 | ✅ 100% | 调用序列 + 立即数 |
| SthenoCamera | ✅ 100% | 逐指令（仅 2 个函数） |
| SthenoKeyboard | ✅ 主要逻辑 | 8 个函数已识别 |
| 16 hook 的 target + selector | ✅ 100% | SELREF + 类名交叉 |
| 25 个替换 IMP 地址 | ✅ 100% | `__data` 槽 + 注册代码 |
| 48 个 class pattern 地址 | ✅ 100% | `class_ro_t` 类名反查 |
| 授权算法 | ✅ 公式完整 | base64 → upper → reverse，取 `[14,16)` |
| **16 个 hook 方法体** | ❌ **0%** | 偏移运行期生成（见第五节） |
| 授权 `value` 的确切来源 | 🟡 待 2 个断点 | `0x16f24` / `0x16f3c` |
| 2 个 SF Symbol（system / 个别控件） | 🟡 字符串池无残留 | 已标 TODO |

---

## 四、关键结论速查

### 4.1 这是什么东西

Orion 框架的 Swift Tweak，三个 dylib 分别注入 **SpringBoard / mediaserverd / UIKit**。
核心是 iPhone 上的「浮窗多任务」：手势环、边缘热区、分屏、回收站、相册、授权。

### 4.2 保活链路（浮窗为什么不被杀）

```
SBIconController 图标分流 → FBSystemService 启动打标 → FBSceneManager 造第二块场景
→ UIApplicationSceneDeactivationManager 过滤挂起原因 → FBScene 拦住 deactivate / kill
```

### 4.3 三进程通信

| 通道 | 路径 |
|---|---|
| 设置 | `/var/mobile/Library/Preferences/com.nx.stheno.plist` |
| 环境快照 | `/tmp/stheno_env.json` |
| 前台快照 | `/tmp/stheno_frontmost.json` |
| 通知 | Darwin `com.nx.SthenoKeyboard` |
| 日志 | `/var/mobile/Documents/AppLecard.log` |

**不走 NSUserDefaults** —— 子进程读不到 cfprefsd 缓存，所以直接读文件。

### 4.4 手感设计的三个关键

1. **`predictedEndLocation`**（0x3cb24）：松手用系统**预测终点**，不是当前位置 → "甩一下到位"
2. **`×0.5` 半量旋转**（0x3cbcc）：手指转 2° 环转 1°，但吸附判定乘回 ×2 → 长列表易停准
3. **`withAnimation` + `Angle.animatableData`**：回弹是声明式动画，不是手写逐帧

另：浮窗拖拽起手距离 **20pt**（0x55070），全部手势统一以**视图中心**为原点。

### 4.5 授权算法

```
expected = reverse( uppercase( base64( value[14..<16] ) ) )
```

只取 2 个字符做种子。`value` 来自 `__common+0x210` 全局槽。

### 4.6 相机保活（SthenoCamera）

开启 `Camera` 时**吞掉** `FigCaptureClientSessionMonitor._updateClientStateCondition:newValue:`，
让 mediaserverd 不回收相机会话。逻辑只有 2 个函数，已逐指令还原。

---

## 五、唯一缺口：16 个 hook 方法体

### 5.1 为什么拿不到（一句话）

Orion 的分发是 `metadata + [__common+0x288] → 取槽 → blraa`，
而那个偏移由 `swift_initClassMetadata2` 在**运行期**写入，**文件里是 0**。

### 5.2 已试过的 7 条路径（全部记录在报告 §11 / §21 / §23）

| # | 方法 | 结果 |
|---|---|---|
| 1 | 固定 `+40` 读 VTableDescriptorHeader | 噪声 |
| 2 | 40–160B 扫 header 自洽性 | 2 个假候选 |
| 3 | 常量段扫连续 rel32 → `__text` | 常量段 0 命中 |
| 4 | `__swift5_proto` → WitnessTable | 指向关联类型表，非实现 |
| 5 | glue 闭包 | 是 callSuper 转发桩 |
| 6 | `class_ro_t` 类名反查 pattern | 命中 48 个，但都是 **metaclass** pattern |
| 7 | `TargetMethodDescriptor{flags,impl}` 对扫描 | 指针落在描述符**空隙**，归属不可靠 |

### 5.3 三条替代路径

| 路径 | 需要 | 时间 |
|---|---|---|
| **Hopper v5+ / Ghidra + Swift 插件** | Mac | 用报告 §23.4 的入口（0x5a628–0x65a00 + 48 个 pattern 地址），约 10 分钟 |
| **未 strip 的构建产物** | 旧的 `.o` / debug dylib | `nm -m` 一次出全部符号 |
| **越狱设备 + LLDB** | 设备 | 按 `VERIFY_PLAYBOOK.md` 的 25 个断点，逐个观察 |

> 关键技巧：IMP 包装器签名是 `(id self, SEL _cmd, ...)`，
> **断点打上去 `$x1` 就是 selector**，不需要预先配对。

---

## 六、下一步建议

### 如果目标是「能跑起来」
1. 按 `BUILD_STATUS.md` 的顺序编译：**先 SthenoCamera**（100% 还原，最稳）→ SthenoKeyboard → 主模块先去 Hooks 跑通骨架
2. 主模块第一次编译大概率在 **Orion 入口写法** 上报错，按提示改 `Tweak.swift` 一处即可
3. 私有框架缺 `.tbd` 时补 `-undefined dynamic_lookup`

### 如果目标是「行为一致」
只有第五节那三条路。当前 `Hooks/*.swift` 的方法体是**示意实现**，文件头有 ⚠️ 标注。

### 如果要继续深挖
`tools/` 里的脚本可直接对新版本二进制重跑，`behavior_map.txt` 的输出可以 diff ——
以后区分「作者改了什么」很快。

---

## 七、坦白说明

这份工程里，**方法体之外的部分全部有据可查**（地址写在各文件注释里）。
但 `Hooks/*.swift` 的 16 个函数体、以及 `Reflection/Meta.swift` 里两个未实现的函数
（`genericOffsetInWords` / `fieldRecord`）是**按语义重建的，不是还原的**。

不要把它们当原版逻辑用。
