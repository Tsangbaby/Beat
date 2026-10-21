# Startup-safety repair candidate (not a completed restoration)

## Frozen failure and limits

- Rejected source: `f4deea8babfa367326a06e6c41c9c27e1e153b3a`.
- Rejected original RootHide deb SHA-256:
  `1111566ff389a4259ef132c52d05485744c30e90019d5fc32901ed9b9e97deeb`.
- User reported black screen after installation/respring on iOS 15.4.1 and has
  recovered the desktop. No further installation/reproduction was requested
  during this investigation. Personal reports are NOT uploaded to this repo.
- Available reports are a ResetCounter and a simulated amsengagementd fault.
  The latter calls SyncedDefaults logging through `os_fault_with_payload`;
  neither supplies a SpringBoard crash stack. The particular handset cause
  is **not proven**.
- Main remains frozen. Repair is isolated on `fix/ios15-startup-safety`.

## Evidence-backed defects and repairs

1. The pinned Orion runtime defaults recoverable hooking errors to a fatal
   handler. A per-tweak returning handler now leaves the system alive; the
   global unrecoverable Orion handler is not replaced. A per-descriptor backend
   checks actual method existence, full argument count, return encoding, and
   every argument encoding against the **compiled replacement method** before
   forwarding it to Substrate. Unknown function hooks are rejected.
2. Versioned iOS 15.0 dumps contradict the reconstructed object/void Scene
   update and creation returns, object-valued banner options, integer-valued
   activation sources, and Bool icon-launch return. Those declarations are
   corrected. Launch arguments are forwarded as nullable opaque objects, not
   forcibly bridged to Foundation Notification. A successful runtime ABI check
   is still required on the handset; 15.0 headers are not labelled 15.4 proof.
3. Completion invoke signatures are unproven. They remain nullable opaque
   ObjC pointers, never invoked or wrapped. Only the two explicitly named
   Scene-creation/activation callback slots may admit an original `@?` as an
   opaque replacement `@`. No other slot, and no return value, has that exception.
4. The unsupported FBScene kill method, SBGrabberTongue touches methods and
   unproven `_handleClick` getter are not installed or relocated to guessed
   owners. Other compatible descriptors remain eligible. The recognizer uses
   the versioned class name without a guessed leading underscore, with a
   runtime-checked UIPanGestureRecognizer target. SBGrabberTongue is declared
   as NSObject, matching the inspected dump.
5. Native keyboard hooks validate full ABI before installation. The bounds
   forwarding method now preserves CGRect on the verified UIScene owner;
   a missing keyboard-window original cannot be called by the notification.
   The camera condition is a raw void pointer, not an ARC-retained ObjC object,
   and the camera method is ABI-checked before installation.
6. Startup no longer publishes a full-screen alert-level window just because
   display preferences default true. The window is lazy, hidden while idle,
   explicitly clears its hosting view, does not become key, admits only declared
   input regions and recovers when a foreground UIWindowScene becomes available.
   Production observes actual presentation state and Scene activation, without
   guessed delays, repeated startup timers or an irreversible missing-scene latch.
7. The incomplete Scene-hosting path must not swallow ordinary icon launches.
   Until a real existing host has both a Scene and views, the original system
   launch is called once. This is deliberate native fail-open behavior, not a
   claim that new floating-Scene creation has been restored.

## Verification levels

- Linux: source/frontend regression contracts plus the actual compiled C type
  comparator; no iOS runtime claim.
- Cloud Mac: actual native Objective-C Method metadata comparison, actual
  production Swift backend with a test-only ABI-matched Orion descriptor shim,
  and actual production UIKit window/presenter in an installed iOS 17 simulator
  smoke app. The rejected window's normalized body is frozen in a fixture and
  executes alongside the repaired implementation to reproduce its transparent
  wrapper touch-capture defect. This is NOT an iOS 15 SpringBoard reproduction.
- Cloud device build: normal pinned RootHide Theos, Xcode 15.4, arm64 + arm64e,
  all three original module targets; generated Orion glue, compile/link/sign and
  independent original-deb verification are required after executed smoke gates.
- Handset: **pending**. A passing build/test/signature does not prove black-screen
  repair or safe daily use. No Release/tag/main promotion is performed.

## Unrestored / deliberately deferred

The original archive, licensing State.swift, geometry and reflection are retained.
Scene creation/hosting, opaque callback behavior, full keep-alive semantics,
notification routing and gesture/UI fidelity remain incomplete. No diagnostic
collector, telemetry, widened injection filter or new process is added. Existing
keyboard preference/snapshot semantics are not repaired as part of this startup
candidate. If no compatible foreground Scene is available, the overlay stays
absent rather than guessing a private Scene/window owner.

## Primary references

- Pinned Orion [Tweak](https://github.com/theos/orion/blob/762159dc214d5aafa2edfc7554c659fc3c658b5b/Sources/Orion/Tweak.swift),
  [Substrate backend](https://github.com/theos/orion/blob/762159dc214d5aafa2edfc7554c659fc3c658b5b/Sources/OrionBackend_Substrate/SubstrateBackend.swift).
- Versioned ktool [iOS 15.0 runtime headers](https://github.com/donato-fiore/iOS-Runtime-Headers/tree/031ec3a8b25d1751646143551d2ea630bbb04cf9/15.0/PrivateFrameworks):
  SpringBoard/SpringBoard, SBIconController, SBMainDisplaySceneManager,
  SBGrabberTongue; FrontBoard/FBSceneManager, FBSystemService, FBScene, FBProcess;
  BannerKit/BNContentViewController; UIKitCore/UIScene, UIRemoteKeyboardWindow;
  CMCapture/FigCaptureClientSessionMonitor.
- Apple [UIView hitTest](https://developer.apple.com/documentation/uikit/uiview/hittest(_:with:)):
  content transparency alone does not establish input pass-through.
