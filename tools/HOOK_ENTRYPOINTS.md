# Hook 分发机制（第 8 轮核心发现）

> 这份文档回答一个问题：**Orion 是怎么把「系统方法被调用」变成「用户的 Swift 方法被执行」的**。
> 想补齐 16 个 hook 的方法体，必须先看懂这条链。

## 一、调用链（实测，非推测）

以 `SpringBoardHook.noteActiveInterfaceOrientationWillChangeToOrientation:` 为例：

```
系统调用 selector
   ↓  IMP 已被替换
0x70eb0   包装器：retain(self) → 转调 0x70dfc → release(self)
   ↓
0x70dfc   分发器（每个 selector 一个）：
          0x70e18  x0 = 0; bl 0x58fd0        ; 取 hook 类的 metadata
          0x70e20  w1 = [metadata+0x30]       ; 实例大小
          0x70e24  w2 = [metadata+0x34]       ; 对齐
          0x70e28  swift_allocObject          ; 分配 hook 实例
          0x70e3c  ClassHook.init(target:)    ; 把系统对象塞进去
          0x70e68  x8 = [__common+0x288]      ; ★ 运行期缓存的槽偏移
          0x70e74  x8 = metadata + x8         ; 定位到槽
          0x70e78  x9 = [x8]                  ; 取 vtable 项
          0x70e88  blraa x9, x17              ; ★ 调用用户方法
```

## 二、为什么静态分析拿不到方法体

关键在 `0x70e68`：**槽偏移是运行期算出来存在 `__common+0x288`（0xb3dc8）里的**。

- 初始化路径：`0x58fd0 → 0x63438 → 0x63478`，其中
  `0x63478` 是 `swift_initClassMetadata2` 的包装；
  `ldr x8,[x3]; add x4, x0, x8` 说明 `[0xb3dc8]` 是「相对 metadata 的偏移」。
- 对 hook 类这种 **0 实例字段的泛型类**，`FieldOffsetVectorOffset` 与 `vtableOffset` 恰好重合，
  所以同一个缓存值既用于字段偏移向量、也用于 vtable 定位。
- 这个值在**文件里是 0**（`__common` 属于 bss），只有运行时才被写入。

**结论**：vtable 的起始位置依赖运行期 `swift_initClassMetadata2` 的结果，
静态文件里只保留 metadata pattern，没有可直接读的偏移。这就是 §11 五条路径全部失败的根因。

## 三、但这条链给了一个可用产物：25 个替换 IMP

`__data` 里有一组槽（步长 16 字节），每个槽指向一个「包装器」= 某个 selector 的实际替换 IMP。
在设备上断点这些地址，就能观察每个 hook 被调用的时机与参数：

| 槽 | 替换 IMP | 槽 | 替换 IMP |
|---|---|---|---|
| 0xad2a8 | 0x70eb0 | 0xad368 | 0x740ec |
| 0xad2b8 | 0x715e0 | 0xad378 | 0x74220 |
| 0xad2c8 | 0x71714 | 0xad388 | 0x749a4 |
| 0xad2d8 | 0x71c14 | 0xad398 | 0x7507c |
| 0xad2e8 | 0x722a0 | 0xad3a8 | 0x75a34 |
| 0xad2f8 | 0x72c40 | 0xad3b8 | 0x75bbc |
| 0xad308 | 0x72d28 | 0xad3c8 | 0x76278 |
| 0xad318 | 0x72ec4 | 0xad3d8 | 0x76854 |
| 0xad328 | 0x72fac | 0xad3e8 | 0x76d9c |
| 0xad338 | 0x73550 | 0xad3f8 | 0x775d4 |
| 0xad348 | 0x73e64 | 0xad408 | 0x77ef0 |
| 0xad358 | 0x73fb8 | 0xad418 | 0x78938 |
| | | 0xad428 | 0x78a94 |

每个包装器紧邻的「注册代码」（形如 `0x70f04`）里有：
`ldr x19,[__data+0x4d70]`（selector 槽）+ `ldr x8,[__data+0x2a8]`（上面这个 IMP）+ `bl 0x7bbbc`（注册）。
所以 **selector ↔ IMP 的配对是确定的**，只是方法体在运行期才定位。

## 四、这对"补齐方法体"意味着什么

| 手段 | 可行性 |
|---|---|
| 静态读 vtable | ❌ 偏移运行期才写入 |
| 读 metadata pattern | ⚠️ 需要 `swift_initClassMetadata2` 的确切行为，且 pattern 位置未定位 |
| **设备上断点 IMP**（本文第三节） | ✅ 直接可行，且能看到参数与返回值 |
| Hopper/Ghidra | ✅ 能解析泛型 metadata，一次列出 |
| 未 strip 产物 | ✅ `nm` 直接出符号 |

**推荐**：用第三节的 25 个地址在设备上断点，配合日志确认每个 hook 的触发条件与分支。
这是没有 Mac、没有未 strip 产物时唯一能自己推进的路。

## 五、顺带修的一个真 bug（影响此前所有结论）

`fx.py` 的 arm64e chained fixups 解析里，**auth rebase 的 target 只有 32 位**
（43 位是 non-auth 形态）。原实现一律按 43 位取，导致所有带 PAC 的指针被
混入 diversity/key 位，解出垃圾地址。

修复后：
- 越界 rebase：**2501 → 0**
- 能正确指向 `__text` 的 rebase 指针：**0 → 1045**

这条修复让「按指针找结构」的所有方法重新变得可信，也是本轮能读出分发链的前提。
