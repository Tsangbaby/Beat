import UIKit
import SwiftUI

/// Explicit touch admission; transparent hosting wrappers are not pass-through.
public final class SthenoWindow: UIWindow {
    public var inputRegions: [CGRect] = []

    public override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    public override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        configure()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        windowLevel = UIWindow.Level.alert + 1
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, inputRegions.contains(where: { $0.contains(point) }) else { return nil }
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// UIKit-only ownership seam used by production and the simulator smoke test.
/// A user preference such as showRing is NOT a presentation request.
final class SthenoOverlayPresenter<Content: View> {
    private(set) var window: SthenoWindow?
    private let content: () -> Content
    private let sceneProvider: () -> UIWindowScene?

    init(sceneProvider: @escaping () -> UIWindowScene? = {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive && $0.screen === UIScreen.main }
    }, content: @escaping () -> Content) {
        self.sceneProvider = sceneProvider
        self.content = content
    }

    func update(presented: Bool, inputRegions: [CGRect]? = nil) {
        guard Thread.isMainThread else { return }
        guard presented, let scene = sceneProvider() else {
            window?.inputRegions = []
            window?.isHidden = true
            return
        }
        if window == nil {
            let candidate = SthenoWindow(windowScene: scene)
            let hosting = UIHostingController(rootView: content())
            hosting.loadViewIfNeeded()
            hosting.view.backgroundColor = .clear
            hosting.view.isOpaque = false
            candidate.rootViewController = hosting
            // Retain the window before publishing it. Never make it the key window.
            window = candidate
        }
        guard let window else { return }
        if window.windowScene !== scene {
            window.isHidden = true
            window.windowScene = scene
        }
        window.frame = scene.coordinateSpace.bounds
        // The current reconstructed Switcher is a full-screen panel. Only its
        // explicit presented state gets full-screen input; idle always gets none.
        window.inputRegions = inputRegions ?? [window.bounds]
        window.isHidden = false
    }
}
