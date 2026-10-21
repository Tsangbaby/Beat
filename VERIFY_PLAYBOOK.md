# 行为验证手册（VERIFY_PLAYBOOK）

> 用途：在没有 Mac、没有未 strip 产物的前提下，**在设备上把 16 个 hook 的真实行为确认出来**，
> 反过来补齐 `Sources/Stheno/Hooks/*.swift` 里那些示意实现。
>
> 依据：`tools/HOOK_ENTRYPOINTS.md`（分发链已解开）+ 本手册。

---

## 0. 为什么这条路可行

Orion 的分发链是：

```
系统调用 selector
  → IMP 包装器（本文列出的地址）
      → 分发器：allocObject + ClassHook.init(target:) + vtable 槽 → blraa
```

**关键点**：包装器是标准 ObjC IMP，签名 `(id self, SEL _cmd, ...)`。
所以断在包装器入口时：

- `$x0` = 被 hook 的系统对象（`self`）
- `$x1` = **selector 本身** ← 直接告诉我们"这是哪个 hook"
- `$x2/$x3/...` = 原方法参数

也就是说：**不需要我预先做 selector↔IMP 配对，断点打上去，`p (char*)$x1` 就出名字。**

---

## 1. 环境准备

```bash
# 设备上（越狱，iOS 15+，已安装 Stheno）
# 1) 找到 SpringBoard 进程
ps -A | grep SpringBoard

# 2) 附加
debugserver *:1234 -a SpringBoard      # 或直接用 LLDB 附加
```

```bash
# Mac / 有 lldb 的机器
lldb
(lldb) process attach --name SpringBoard --waitfor
```

### 计算运行时地址（ASLR）

二进制里的地址是**文件偏移**。运行时地址 = `模块基址 + 文件偏移`。

```lldb
(lldb) image list -o -f | grep -i stheno
# 输出示例： [  0] 0x0000000104a00000 /Library/MobileSubstrate/DynamicLibraries/Stheno.dylib
#            基址 = 0x104a00000，slide = 基址 - 0
```

因为 `Stheno.dylib` 的 `__TEXT` 从 vmaddr 0 开始，所以：

```
运行时地址 = 模块基址 + 文件偏移
```

在本手册里我给出的都是**文件偏移**，用的时候自己加基址。

---

## 2. 一次性断点脚本

把下面存成 `stheno.lldb`，`command source stheno.lldb` 执行：

```lldb
# ---- 25 个替换 IMP（文件偏移）----
target modules load --file Stheno.dylib --slide 0x0     # 先让 lldb 认识文件偏移
br s -a 0x70eb0
br s -a 0x715e0
br s -a 0x71714
br s -a 0x71c14
br s -a 0x722a0
br s -a 0x72c40
br s -a 0x72d28
br s -a 0x72ec4
br s -a 0x72fac
br s -a 0x73550
br s -a 0x73e64
br s -a 0x73fb8
br s -a 0x740ec
br s -a 0x74220
br s -a 0x749a4
br s -a 0x7507c
br s -a 0x75a34
br s -a 0x75bbc
br s -a 0x76278
br s -a 0x76854
br s -a 0x76d9c
br s -a 0x775d4
br s -a 0x77ef0
br s -a 0x78938
br s -a 0x78a94

# ---- 命中时自动打印 selector ----
br command add -s python -F
def stop_handler(frame, bp_loc, internal_dict):
    sel = frame.EvaluateExpression("(char*)$x1").GetSummary()
    self_addr = frame.EvaluateExpression("(void*)$x0").GetSummary()
    print(f"[Stheno] {sel}  self={self_addr}  pc={frame.GetPC():#x}")
    return False          # False = 不停下，继续跑
```

> 如果你只想看某一个 hook，删掉其余断点即可。

---

## 3. 16 个 hook 的触发清单

按"操作 → 期望命中的 selector"组织。**这是我根据 selector 语义列的验证假设**，
你实测后把结果填进最后一列，就能确定真实行为。

### 3.1 SpringBoard / 应用层

| # | 触发操作 | 期望 selector | 观察点 | 实测结果 |
|---|---|---|---|---|
| 1 | 冷启动 SpringBoard（`killall SpringBoard`） | `applicationDidFinishLaunching:` | `$x0` 是 SpringBoard；此后 `Environment.shared` 应已初始化、`SthenoWindow` 已创建 | |
| 2 | 旋转设备 / 触发方向变化 | `noteActiveInterfaceOrientationWillChangeToOrientation:` | `$x2` = 新方向（1 竖 / 3 左横 / 4 右横）；观察浮窗 frame 是否跟随 | |
| 3 | 前台应用切换（回到桌面再进 App） | `frontDisplayDidChange:` | `$x2` = display；随后 `/tmp/stheno_frontmost.json` 应被刷新 | |
| 4 | 在桌面单击一个 App 图标 | `iconManager:launchIconForIconView:withActions:` | **重点**：返回值决定"开浮窗 or 正常启动"；`$x0`=SBIconController, `$x2`=iconView, `$x3`=actions(NSSet) | |
| 5 | 长按图标（进入抖动） | 同上 | 对比单击/长按时哪个参数不同 → 找出"长按判定"依据 | |
| 6 | 点击浮窗外部（宿主 App 内） | `sendAction:to:from:forEvent:` | 是否先 `resignFirstResponder`（键盘收起） | |
| 7 | 从浮窗里退出一个 App | `_didExitWithContext:` | `$x0.bundleIdentifier`；浮窗是否只关窗不杀进程 | |

### 3.2 手势层

| # | 触发操作 | 期望 selector | 观察点 | 实测结果 |
|---|---|---|---|---|
| 8 | 从屏幕左/右边缘向内滑 | `gestureRecognizer:shouldReceiveTouch:` | **返回值**是关键：`false` 表示"我们接管"；配合 `touch.locationInView` 判断热区 | |
| 9 | 底部 Home 条上滑 | `_handleClickAndDragHomeGesture:` | 有浮窗时应"收浮窗"而非进 Switcher；`$x2` 是手势对象，可读 `translationInView:` | |
| 10 | 卡片堆拖拽 | `_handleDeckSwitcherPanGesture:` | 同上，比对 translation/velocity | |
| 11 | 触摸 Home 条（轻点/长按） | `touchesBegan:withEvent:` / `touchesMoved` / `touchesEnded` / `touchesCancelled` | 四个方法都会命中，观察调用顺序与 `$x2`(NSSet<UITouch>) | |
| 12 | 浮窗层级变化 | `zStackParticipantDidChange:` | `$x2` = SBFZStackParticipant，读 `ownsHomeGesture` | |

### 3.3 场景 / 保活层（最关键）

| # | 触发操作 | 期望 selector | 观察点 | 实测结果 |
|---|---|---|---|---|
| 13 | App 退到后台（按下 Home） | `_setDeactivationReasons:onScene:withSettings:reason:` | **`$x2` = reasons（位掩码）**，钩子会把它过滤后再传给 orig → 在这里读出"哪些 reason 被清掉"，就知道保活策略 | |
| 14 | 同上 | `_scene:interceptUpdateWithNewSettings:` | `$x3` = 新 settings；看是否被改写 | |
| 15 | 关闭浮窗 | `deactivateWithTransitionContext:` | 对比"正常关闭"与"被系统回收"时的路径差异 | |
| 16 | 系统尝试杀浮窗进程（内存压力 / 手动） | `_killForReason:andReport:withDescription:completion:` | `$x2`=reason，`$x3`=description 字符串；看是否被吞 | |
| 17 | 系统中创建新场景 | `_createSceneWithDefinition:settings:initialClientSettings:transitionContext:fromRemnant:usingClientProvider:completion:` | 参数共 7 个，观察"分屏时的第二块 scene"从哪来 | |
| 18 | 从浮窗内启动另一个 App | `_activateBundleID:requestID:isTrusted:options:source:originalSource:withResult:` | `$x3`=options 字典；看是否被塞入标记键 | |
| 19 | 打开浮窗里的 App 页面 | `viewDidLoad` | `$x0` = SBDeviceApplicationSceneViewController；看 `view` 何时被挂到容器 | |
| 20 | 收到横幅/通知 | `presentPresentable:withOptions:userInfo:` | 开关打开时是否转成浮窗 | |
| 21 | 卸载浮窗里的 App | `uninstallApplication:` | 回收站是否清理 | |
| 22 | 状态栏出现/隐藏 | `initWithFrame:` | `$x2` = frame；`windowLevel` 是否被抬高 | |

---

## 4. 怎么把观测结果变回源码

每个 hook 观测到三类信息，对应源码的三部分：

| 观测 | 写回源码的哪一处 |
|---|---|
| **返回值**（`finish` 里的 `$x0`） | `func xxx(...) -> Bool` 的 return（决定"吞掉"还是"透传"） |
| **参数变化**（传给 `orig` 的值 vs 收到的值） | 函数体里的"改写参数"逻辑 |
| **副作用**（调用后 `Environment.shared` / `/tmp/*.json` / 视图层级 变化） | 函数体里的"做事"逻辑 |

具体做法（以 #13 保活为例）：

```lldb
# 断在 _setDeactivationReasons:...
# 1) 读入参
(lldb) p/d $x2                      # reasons 原始值
# 2) 单步到 bl <orig 调用>，读传进去的值
(lldb) p/d $x2                      # 过滤后的值
# 3) 两次相减 = 被清掉的位
```

差异位就是 `SthenoController.suspendableReasonMask` 的真实值——
目前源码里我写的是 `0`，你实测后改成真实掩码即可。

同理：

- #4 返回值 `true` → `SBIconControllerHook.iconManager(...)` 返回 `true`（吞掉启动）
- #8 返回 `false` → `gestureRecognizer(_:shouldReceive:)` 返回 `false`
- #16 看 `completion` 是否被调用、传了 `true` 还是 `false`

---

## 5. 备选：不打 LLDB 的做法

如果设备上没有 debugserver，用一个"探针 dylib"也能拿到同样信息：

```objc
// Probe.xm —— 只观察，不改行为
%hook SBApplication
- (void)_didExitWithContext:(id)ctx {
    NSLog(@"[Stheno-Probe] _didExitWithContext: %@ bundeID=%@", ctx, self.bundleIdentifier);
    %orig;
}
%end
```

把 16 个 selector 逐个写成 `%hook` + `%orig`，装上去看 Console 日志即可。
优点：不需要 Mac；缺点：拿不到返回值/参数改写的细节。

---

## 6. 优先级建议

按"对功能影响"排序，先做这 5 个：

1. **#13 `_setDeactivationReasons:`** —— 保活核心，直接决定浮窗会不会被挂起
2. **#4 `iconManager:launchIconForIconView:withActions:`** —— 决定"点击图标是开浮窗还是正常启动"
3. **#18 `_activateBundleID:`** —— 决定启动链路是否被打标
4. **#9 `_handleClickAndDragHomeGesture:`** —— 决定手势手感
5. **#8 `gestureRecognizer:shouldReceiveTouch:`** —— 决定边缘热区

这 5 个确认完，插件的骨架行为就与原版对齐了；其余 11 个属于细节。
