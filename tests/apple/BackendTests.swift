import Foundation
import ObjectiveC
import Orion

@objc(SthenoBackendTarget) class BackendTarget: NSObject {
    @objc func value(_ object: NSObject?) -> NSObject? { object }
    @objc func flag() -> Bool { true }
}
@objc(SthenoBackendReplacement) class BackendReplacement: NSObject {
    @objc func value(_ object: NSObject?) -> NSObject? { object }
    @objc func flag() -> NSObject? { nil }
}
final class Recorder: Backend {
    var received = 0
    func apply(descriptors: [HookDescriptor]) {
        received += descriptors.count
        for case let .method(cls, sel, _, completion) in descriptors {
            let method = class_getInstanceMethod(cls, sel)!
            completion(.success(unsafeBitCast(method_getImplementation(method), to: UnsafeMutableRawPointer.self)))
        }
    }
}

@main enum BackendTests {
    static func main() {
        let recorder = Recorder()
        let backend = SthenoValidatedBackend(upstream: recorder,
            replacements: [NSStringFromClass(BackendTarget.self): BackendReplacement.self])
        var successful = 0
        var rejected = 0
        let pointer = UnsafeMutableRawPointer(bitPattern: 1)!
        let descriptors = ["value:", "flag", "absent:"].map { name in
            HookDescriptor.method(cls: BackendTarget.self, sel: NSSelectorFromString(name), replacement: pointer) { result in
                switch result { case .success: successful += 1; case .failure: rejected += 1 }
            }
        }
        backend.apply(descriptors: descriptors)
        precondition(recorder.received == 1 && successful == 1 && rejected == 2,
                     "rejected descriptors reached the upstream or compatible method was lost")
        let orphan = SthenoValidatedBackend(upstream: recorder, replacements: [:])
        orphan.apply(descriptors: [descriptors[0]])
        precondition(recorder.received == 1 && rejected == 3, "unknown target must not install")
        print("PRODUCTION_BACKEND_PASS accepted=1 rejected=3 descriptor-shim-not-Orion-runtime")
    }
}
