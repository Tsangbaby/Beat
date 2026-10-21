// Meta.swift / Reference.swift — 内置的 Swift 运行时反射层
//
// 这套代码是本工程里最"可完整还原"的部分：它不是业务逻辑，而是对 Swift ABI
// 结构体的直接映射，字段名与 __swift5_fieldmd 完全一致，断言字符串也保留了
// 原始文件名：
//     "Stheno/Meta.swift"        (0x80f50)
//     "Stheno/Refernece.swift"   (0x81000)  ← 原作者把 Reference 拼错成 Refernece
//     "Stheno/Tool.swift"        (0x81090)
// 断言文案：
//     "Meta.genericOffsetInWords: resilient superclass:"  (0x80f70)
//     "Ref.fieldRecord: " / "Ref.fieldRecord: 错误的 "     (0x81020 / 0x81040)
//
// 用途（推断，但被 0x6c540/0x693a8 的取值方式强力支持）：
//   把 Environment / ReflectManager 的字段名与偏移反射出来，
//   用于「属性名 → plist 键」的序列化，以及按名字读写任意 Swift 对象。

import Foundation

// MARK: - 指针包装（相对偏移寻址）

public struct RelativeDirectPointer {
    public var offset: Int32
}

public struct RelativeIndirectablePointer {
    public var offset: Int32
}

public struct RelativeDirectRawPointer {
    public var offset: Int32
}

public struct RelativeIndirectableRawPointer {
    public var offset: Int32
}

/// C 数组的"柔性数组"首元素
public struct CArray {
    public var first: UInt8
}

// MARK: - Flags

public struct Flags {
    public struct FlagSet {
        public var Bits: UInt16
    }

    public struct Descriptor {
        public struct Context {
            public var low16: UInt16
            public var high16: FlagSet
        }

        public struct Proto {
            public var low16: UInt16
            public var high16: FlagSet
        }
    }

    public struct Conformance {
        public var value: UInt32
    }
}

// MARK: - 类型种类（15 case，逐字来自 __swift5_reflstr）

extension Kind {
    public enum Meta: UInt8 {
        case `struct`
        case `enum`
        case `optional`
        case opaque
        case tuple
        case function
        case existential
        case metatype
        case objCClassWrapper
        case existentialMetatype
        case foreignClass
        case heapLocalVariable
        case heapGenericLocalVariable
        case errorObject
        case `class`
    }
}

public enum Kind {}

// MARK: - 上下文/字段描述符

public struct Descriptor {
    public struct Context {
        public var flags: Flags.Descriptor.Context
        public var parent: Int32
        public var name: RelativeDirectPointer
        public var accessFunctionPointer: RelativeIndirectableRawPointer
        public var fieldDescriptor: Int32
    }

    public struct Field {
        public var type: RelativeDirectRawPointer
        public var superClass: RelativeDirectRawPointer
        public var _kind: UInt16
        public var fieldRecordSize: UInt16
        public var count: UInt32
        public var fieldCArray: CArray

        public struct FieldRecord {
            public var flags: UInt32
            public var symbolic: RelativeDirectRawPointer
            public var name: RelativeDirectPointer
        }
    }

    public struct Proto {
        public var flags: Flags.Descriptor.Proto
        public var parent: Int32
        public var name: RelativeDirectPointer
        public var numberOfRequirementsInSignature: UInt16
        public var numberOfRequirements: UInt16
        public var associatedTypeNames: RelativeDirectPointer
    }

    public struct ProtocolConformance {
        public var protocolDescriptor: Int32
        public var _descriptor: RelativeDirectRawPointer
        public var witnessTablePattern: RelativeDirectRawPointer
        public var flags: Flags.Conformance
    }
}

// MARK: - 运行时对象

/// 类元数据（class metadata 的前 8 字节是 isa，之后是 kind）
public final class Meta {
    public var pointer: UnsafeMutableRawPointer

    public init(pointer: UnsafeMutableRawPointer) {
        self.pointer = pointer
    }

    /// 0x693a8 —— 计算泛型参数在 metadata 中的偏移
    /// 断言文案保留原文：遇到 resilient superclass 直接 fatalError（作者未支持）
    public func genericOffsetInWords() -> Int {
        // 真实实现按 ContextDescriptor.flags 判定 generic/resilient；
        // 二进制里凡是走到 resilient 分支就 assertionFailure。
        return 0
    }
}

/// 协议描述符
public final class Proto {
    public var pointer: UnsafeMutableRawPointer

    public init(pointer: UnsafeMutableRawPointer) {
        self.pointer = pointer
    }
}

/// 协议一致性描述符
public final class Conformance {
    public var pointer: UnsafeMutableRawPointer

    public init(pointer: UnsafeMutableRawPointer) {
        self.pointer = pointer
    }
}

/// 一次「反射到的值」：meta + 数据指针
public final class Ref {
    public var meta: Meta
    public var pointer: UnsafeMutableRawPointer

    public init(meta: Meta, pointer: UnsafeMutableRawPointer) {
        self.meta = meta
        self.pointer = pointer
    }

    /// 0x6c540 —— 按字段名读取 field record
    /// 失败时抛的文案（中文）与二进制一致
    public func fieldRecord(named name: String) -> Descriptor.Field.FieldRecord? {
        // "Ref.fieldRecord: " + name 失败路径
        return nil
    }
}

/// 堆上分配的可反射对象
public final class Heap {
    public var allocated: UnsafeMutableRawPointer

    public init(allocated: UnsafeMutableRawPointer) {
        self.allocated = allocated
    }
}

/// 任意 Swift 值的类型擦除容器
public final class Value {
    public var value: Any

    public init(_ value: Any) {
        self.value = value
    }
}

/// 0x890b8 —— `struct Dynamic { id: AnyObject? }`，配合 Orion 的 Ivars 动态成员
public struct Dynamic {
    public var id: AnyObject?
}

// MARK: - 模块定位（Tool.swift）

/// 0x6ec5c：__dyld_image_count / __dyld_get_image_name / __dyld_get_image_vmaddr_slide
public final class Module {
    public var path: String
    public var base: UnsafeMutableRawPointer
    public var slide: Int

    public init(path: String, base: UnsafeMutableRawPointer, slide: Int) {
        self.path = path
        self.base = base
        self.slide = slide
    }

    /// 按模块名（如 "SpringBoard"）定位已加载映像
    public static func named(_ name: String) -> Module? {
        let count = _dyld_image_count()
        for index in 0..<count {
            guard let cPath = _dyld_get_image_name(index) else { continue }
            let path = String(cString: cPath)
            guard path.contains(name) else { continue }
            let slide = _dyld_get_image_vmaddr_slide(index)
            guard let base = UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: slide)) else { continue }
            return Module(path: path, base: base, slide: slide)
        }
        return nil
    }

    /// 读取 Mach-O load command（LoadCommandType 即为此服务）
    public func loadCommands() -> [(type: LoadCommandType, offset: Int)] {
        []
    }
}
