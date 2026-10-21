import UIKit
import SwiftUI

private func require(_ condition: @autoclosure () -> Bool, _ name: String) {
    if !condition() { print("OVERLAY_SMOKE_FAIL \(name)"); fflush(stdout); exit(1) }
    print("OVERLAY_SMOKE_PASS \(name)"); fflush(stdout)
}

@main final class SmokeAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Smoke", sessionRole: session.role)
        configuration.delegateClass = SmokeSceneDelegate.self
        return configuration
    }
}

final class SmokeSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var tapped = false
    @objc private func buttonTap() { tapped = true }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { exit(1) }
        let base = UIWindow(windowScene: scene)
        base.rootViewController = UIViewController()
        base.rootViewController!.view.backgroundColor = .red
        base.makeKeyAndVisible()
        window = base
        DispatchQueue.main.async { self.run(scene: scene, base: base) }
    }

    private func run(scene: UIWindowScene, base: UIWindow) {
        // Execute the exact rejected window class extracted from f4deea8.
        // This demonstrates an idle touch-capture defect, NOT SpringBoard's crash.
        let old = BaselineSthenoWindow(frame: scene.coordinateSpace.bounds)
        old.windowScene = scene
        let oldRoot = UIViewController()
        oldRoot.view = UIView(frame: old.bounds)
        oldRoot.view.backgroundColor = .clear
        old.rootViewController = oldRoot
        old.isHidden = false
        let center = CGPoint(x: old.bounds.midX, y: old.bounds.midY)
        require(old.hitTest(center, with: nil) != nil, "baseline_reproduces_transparent_wrapper_capture")
        old.isHidden = true

        var availableScene: UIWindowScene?
        let presenter = SthenoOverlayPresenter(sceneProvider: { availableScene }, content: {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        })
        presenter.update(presented: false)
        require(presenter.window == nil, "idle_creates_no_window")
        presenter.update(presented: true)
        require(presenter.window == nil, "missing_scene_creates_no_window")
        availableScene = scene
        let region = CGRect(x: 40, y: 80, width: 100, height: 60)
        presenter.update(presented: true, inputRegions: [region])
        guard let overlay = presenter.window, let host = overlay.rootViewController else { exit(1) }
        host.view.frame = overlay.bounds
        host.view.layoutIfNeeded()
        require(!overlay.isHidden && overlay.windowScene === scene, "late_scene_recovers")
        require(!overlay.isKeyWindow && base.isKeyWindow, "does_not_steal_key_window")
        require(host.view.backgroundColor == .clear && !host.view.isOpaque && !overlay.isOpaque,
                "hosting_and_window_are_explicitly_transparent")
        let wrapper = UIView(frame: host.view.bounds)
        wrapper.backgroundColor = .clear
        host.view.addSubview(wrapper)
        let button = UIButton(frame: region)
        button.addTarget(self, action: #selector(buttonTap), for: .touchUpInside)
        wrapper.addSubview(button)
        for point in [CGPoint(x: 5, y: 5), CGPoint(x: overlay.bounds.midX, y: overlay.bounds.midY),
                      CGPoint(x: overlay.bounds.maxX - 5, y: overlay.bounds.maxY - 5)] {
            require(overlay.hitTest(point, with: nil) == nil, "outside_region_passes_through_fullscreen_wrapper")
        }
        let admitted = overlay.hitTest(CGPoint(x: region.midX, y: region.midY), with: nil)
        require(admitted === button, "real_control_inside_region_receives_hit")
        (admitted as? UIButton)?.sendActions(for: .touchUpInside)
        require(tapped, "admitted_control_delivers_action")
        presenter.update(presented: true, inputRegions: [region])
        require(presenter.window === overlay, "repeated_presentation_reuses_window")
        presenter.update(presented: false)
        require(overlay.isHidden && overlay.inputRegions.isEmpty && overlay.hitTest(center, with: nil) == nil,
                "idle_hides_and_releases_all_input")
        print("OVERLAY_SMOKE_ALL_PASS simulator-not-SpringBoard-device-proof")
        fflush(stdout)
        exit(0)
    }
}
