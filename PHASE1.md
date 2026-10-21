# Stheno phase-one build candidate

> The first package (`77.1.4.6-0.phase1.1`, f4deea8) was rejected on a handset:
> black screen after respring. Do not use it. The new `77.1.4.6-0.phase1.2`
> startup-safety candidate and its remaining limits are documented in
> [STARTUP_SAFETY.md](STARTUP_SAFETY.md). The notes below describe phase-one
> history, not successful runtime acceptance.

This is a buildability repair of the user-supplied reconstructed project, NOT
original Stheno source and NOT a completed functional restoration. Compilation,
linking and package verification do not establish device safety or compatibility.
Do not install this first-stage package on a daily-use phone.

## Input and scope

- Input: `Stheno-Restored-2026-10-21.zip` (59 files).
- Original archive SHA-256: `987852871029888a849e3930ef635083a2b9537f6d3cc8f36825cca6e7387108`.
- Package identity retained: `com.nx.stheno`, original author/maintainer retained.
- Candidate version: `77.1.4.6-0.phase1.1`; this is not a formal release.
- User authorized a separate repair copy, public upload to `Tsangbaby/Beat`,
  GitHub-hosted Mac builds, and a minimal visible RingView reconstruction.
- Hermes configuration and the original archive are untouched.

## Phase-one changes

- ARC-safe strong local ownership in the camera hook.
- Typed native `jbroot` bridge shared by all three compiled targets.
- Declaration-only private Objective-C interfaces instead of competing Swift
  classes registered with system class names. Signatures remain device-unverified.
- Orion `.x.swift` preprocessing, one entry and custom HookGroup activation.
- Explicit selectors for Swift names that otherwise change private selectors.
- Pan-only operations guarded by a real UIPanGestureRecognizer cast.
- IOKit types and ownership imported from C headers, not Swift silgen guesses.
- SwiftUI.Environment qualification to avoid the project's Environment class.
- RingView uses existing app snapshots, selection, rings, radius, rotation, scale
  and offset to show TabIcon components. This is NEW minimal display code, not
  a reconstruction of the missing original body. No Scene/launch/license code
  was invented. Misplaced UIKit methods were removed from this SwiftUI View;
  original UIViewRepresentable methods were not reinterpreted as recovered logic.
- RootHide scheme, root filter inputs, pinned Theos, cloud-only Apple build and
  independent package/Mach-O signature-code-page verification.

## Still incomplete / not addressed

- Demonstration hook bodies and uncertain private method signatures remain.
- Actual Scene creation, hosting and lifecycle behavior are not restored.
- `presentAsFloating` still returns false; suspendableReasonMask is still zero.
- Reflection operations still return nil/zero/empty as in the supplied project.
- The supplied license validation algorithm, key prefix, and acceptance conditions
  were NOT bypassed or replaced. Its correctness is not established.
- App enumeration, keyboard-host behavior, notification sequencing, memory use,
  hit testing, stability and iOS 15/16 behavior require separate device evidence.
- Original reports are historical reconstruction notes, not proof of current
  build or behavior. `tools/` is retained evidence, not production build input.

## Verification

Local gates: `python3 -m unittest discover -s tests -v`.
Cloud build: `.github/workflows/build-roothide.yml`, standard `macos-14`,
Xcode 15.4, RootHide only, pinned Theos and recursive submodule identities.
The actual SDK/compiler versions and build log are recorded in the artifact.
Workflow artifacts bind the original deb to SOURCE_COMMIT, SOURCE_REPOSITORY,
THEOS_COMMIT, XCODE_VERSION and SHA256SUMS. No Release or tag is published.

Evidence levels remain separate: source/frontend contracts; cloud compile/link;
package metadata/paths/signature code-page hashes; real-device acceptance.
There is no device acceptance claim for this phase.
