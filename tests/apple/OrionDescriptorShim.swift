// Test-only, ABI-matched descriptor surface from pinned Orion 762159dc.
// NOT an Orion runtime replacement and never part of the installed package.
import Foundation
public enum Function { case address(UnsafeMutableRawPointer) }
public enum HookDescriptor {
    public typealias Completion = (Result<UnsafeMutableRawPointer, Error>) -> Void
    case method(cls: AnyClass, sel: Selector, replacement: UnsafeMutableRawPointer, completion: Completion)
    case function(function: Function, replacement: UnsafeMutableRawPointer, completion: Completion)
}
public protocol Backend {
    func apply(descriptors: [HookDescriptor])
}
