import UIKit

/// Hosts a bare view in a visible scene window so trait overrides propagate
/// the way they do on device (Dynamic Type label rescaling, appearance-driven
/// layer colors). Detached views never receive those trait updates.
@MainActor
enum TraitHostWindow {
    static func attach(_ view: UIView) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.isHidden = false
        window.addSubview(view)
        return window
    }

    static func detach(_ window: UIWindow) {
        window.subviews.forEach { $0.removeFromSuperview() }
        window.isHidden = true
    }
}
