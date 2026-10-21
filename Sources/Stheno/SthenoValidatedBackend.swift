import Foundation
import ObjectiveC
import Orion

/// Runtime compatibility is checked per descriptor, before Substrate sees it.
/// Rejection leaves the system method untouched; it does not terminate its host.
struct SthenoValidatedBackend<Upstream: Backend>: Backend {
    let upstream: Upstream
    let replacements: [String: AnyClass]

    private struct RejectedHook: Error { }

    func apply(descriptors: [HookDescriptor]) {
        var accepted: [HookDescriptor] = []
        for descriptor in descriptors {
            switch descriptor {
            case let .method(cls, sel, _, completion):
                let className = NSStringFromClass(cls)
                let selectorName = NSStringFromSelector(sel)
                // Do not relocate these reconstructed hooks to guessed owners.
                let unproven = (className == "FBScene" && selectorName == "_killForReason:andReport:withDescription:completion:")
                    || (className == "SBGrabberTongue" && selectorName.hasPrefix("touches"))
                    || selectorName == "_handleClick"
                guard !unproven,
                      let hookClass = replacements[className],
                      let original = class_getInstanceMethod(cls, sel),
                      let replacement = class_getInstanceMethod(hookClass, sel) else {
                    completion(.failure(RejectedHook()))
                    continue
                }
                // These exact argument slots are forwarded as opaque nullable
                // objects. No block invoke signature, wrapper or result is made up.
                let opaqueBlockSlot: Int
                if className == "FBSceneManager" && selectorName == "_createSceneWithDefinition:settings:initialClientSettings:transitionContext:fromRemnant:usingClientProvider:completion:" {
                    opaqueBlockSlot = 8
                } else if className == "FBSystemService" && selectorName == "_activateBundleID:requestID:isTrusted:options:source:originalSource:withResult:" {
                    opaqueBlockSlot = 8
                } else {
                    opaqueBlockSlot = -1
                }
                guard SthenoMethodsHaveSameABI(original, replacement, opaqueBlockSlot) else {
                    completion(.failure(RejectedHook()))
                    continue
                }
                accepted.append(descriptor)
            case let .function(_, _, completion):
                // This project declares no function hooks or verified function ABI.
                completion(.failure(RejectedHook()))
            }
        }
        upstream.apply(descriptors: accepted)
    }
}
