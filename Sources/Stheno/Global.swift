// Global.swift — 全局常量、路径与通用工具
//
// 证据来源：__cstring 常量池 + 引用它们的函数
//   0x804f0  "/var/mobile/Library/Preferences/com.nx.stheno.plist"  ← 0x4c438（读取）
//   0x806c0  "/tmp/stheno_env.json"                                  ← 0x4fe44（写出）
//   0x806e0  "/tmp/stheno_frontmost.json"                            ← 0x4f8e4（写出）
//   0x80290  "/var/mobile/Documents/AppLecard.log"                   ← 0x479f8（日志）
//   0x804d0  "com.nx.SthenoKeyboard"                                 ← 0x4d7e8（Darwin 通知）
//   0x80270  "yyyy-MM-dd HH:mm:ss"                                   ← 0x47970/0x491ec
//   0x80e3d  "mediaserverd" / 0x80e61 "UniqueDeviceID" / 0x80e70 "IOPlatformUUID"
//   0x80d60  "interfaceOrientation"（KVC 键）
//
// 另外：`Stheno/Global.swift` 这个字符串出现在 0x68790 的断言里
// （"Bundle.main.executablePath获取失败" + file="Stheno/Global.swift"），
// 说明该文件确实叫 Global.swift。

import Foundation
import UIKit

// MARK: - 路径

enum SthenoPath {
    /// 主设置 plist；三个模块都直接读它（mediaserverd / UIKit 进程不共享内存）
    static let preferences = "/var/mobile/Library/Preferences/com.nx.stheno.plist"
    /// SpringBoard → 子进程的环境快照（JSON）
    static let environmentDump = "/tmp/stheno_env.json"
    /// SpringBoard → 子进程的前台应用快照（JSON）
    static let frontmostDump = "/tmp/stheno_frontmost.json"
    /// 授权/日志文件（"Lecard" = License Card）
    static let lecardLog = "/var/mobile/Documents/AppLecard.log"
}

// MARK: - Darwin 通知

enum SthenoNotification {
    /// 主模块 → SthenoKeyboard.dylib
    static let keyboard = "com.nx.SthenoKeyboard"
}

// MARK: - 设备

enum SthenoDevice {
    /// 与 SthenoCamera / SthenoKeyboard 的 filter 对应
    static let mediaServer = "mediaserverd"
}

// MARK: - 工具

enum SthenoLog {
    /// 0x479f8：以 "yyyy-MM-dd HH:mm:ss" 追加写 /var/mobile/Documents/AppLecard.log
    /// 二进制里通过 NSFileHandle + seekToEndOfFile 实现（见 0x47b10）
    static func write(_ message: String, file: String = #file, line: Int = #line) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let stamp = formatter.string(from: Date())
        let text = "[\(stamp)] \(message)\n"

        let path = jbroot(SthenoPath.lecardLog)
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil, attributes: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        handle.seekToEndOfFile()
        handle.write(Data(text.utf8))
        handle.closeFile()
    }
}

/// Typed Objective-C bridge: never bind a Swift String function to a C++ symbol.
func jbroot(_ path: String) -> String {
    SthenoJBRootPath(path)
}

/// 0x6ec5c（Stheno/Tool.swift）：通过 dyld 映像表定位模块基址
///   __dyld_image_count / __dyld_get_image_name / __dyld_get_image_vmaddr_slide
enum SthenoImage {
    struct Module {
        let path: String
        let base: UnsafeMutableRawPointer
        let slide: Int
    }

    static func find(named name: String) -> Module? {
        let count = _dyld_image_count()
        for index in 0..<count {
            guard let cName = _dyld_get_image_name(index) else { continue }
            let path = String(cString: cName)
            guard path.contains(name) else { continue }
            let slide = _dyld_get_image_vmaddr_slide(index)
            let header = UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: slide))
            return Module(path: path, base: header ?? .init(bitPattern: 0)!, slide: slide)
        }
        return nil
    }
}

/// 二进制里保留了若干 PAC 辅助函数（_pac_asia/_pac_asib/_pac_asda/_pac_asdb/_pac_pc/_pac_strip），
/// 以及手写的 `_msg_send`／`_msg_send_float`／`_msg_send_double` 转发桩。
/// 它们来自作者内置的一份 objc 消息转发工具（应为第三方/自研 util），
/// 在 Swift 侧不需要重写；此处仅记录其存在，便于对照符号表。
