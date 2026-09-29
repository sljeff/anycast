import UIKit

/// Supplies the fly-in endpoint — the playlist tab icon's center in the
/// current layout. The shell task derives it from the system tab bar's
/// subview frames (07 §3 widget #11: collapsed/expanded tab bar states each
/// measured, falling back to the visible tab bar's area center). The default
/// here degrades to the window's center-bottom when no tab bar geometry is
/// available (A1-accepted adaptation).
@MainActor
protocol PlaylistFlyInEndpointProvider: AnyObject {
    func playlistFlyInEndpoint(in window: UIWindow) -> CGPoint
}

@MainActor
final class WindowCenterBottomEndpointProvider: PlaylistFlyInEndpointProvider {
    func playlistFlyInEndpoint(in window: UIWindow) -> CGPoint {
        CGPoint(
            x: window.bounds.midX,
            y: window.bounds.height - window.safeAreaInsets.bottom - 48
        )
    }
}

/// The "add to playlist" fly-in animation (lib/widgets/animation.dart:3-88,
/// 03 §4): a black rounded rect with a play icon flies from the tapped
/// button to the playlist tab icon over 600 ms (easeInOut), shrinking
/// 200×48 → 24×24 while its background fades 0.8 → 0. Triggered from four
/// call sites (Inbox / Channel / ChannelSearch / SearchPage).
@MainActor
final class PlaylistFlyInAnimator {

    private let endpointProvider: PlaylistFlyInEndpointProvider

    init(endpointProvider: PlaylistFlyInEndpointProvider = WindowCenterBottomEndpointProvider()) {
        self.endpointProvider = endpointProvider
    }

    /// Runs the animation in `window`, from `startPoint` (the plus button's
    /// center in window coordinates). `completion` fires when the overlay is
    /// removed (the Dart onAnimationComplete — the actual list insertion
    /// happens there at the call sites).
    func fly(from startPoint: CGPoint, in window: UIWindow, completion: (() -> Void)? = nil) {
        let endpoint = endpointProvider.playlistFlyInEndpoint(in: window)

        let startSize = CGSize(width: 200, height: 48)
        let endSize = CGSize(width: 24, height: 24)

        let overlay = UIView()
        overlay.frame = CGRect(
            x: startPoint.x - startSize.width / 2,
            y: startPoint.y - startSize.height / 2,
            width: startSize.width,
            height: startSize.height
        )

        let backdrop = UIView()
        backdrop.backgroundColor = .black
        backdrop.alpha = 0.8
        // Corner radius 24 covers the start capsule; the end size makes it a
        // circle, matching the Dart BorderRadius.circular(24).
        backdrop.layer.cornerRadius = 24
        backdrop.frame = overlay.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.addSubview(backdrop)

        let icon = UIImageView(image: AppIcons.play)
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
        ])

        window.addSubview(overlay)

        UIView.animate(
            withDuration: 0.6,
            delay: 0,
            options: [.curveEaseInOut],
            animations: {
                overlay.frame = CGRect(
                    x: endpoint.x - endSize.width / 2,
                    y: endpoint.y - endSize.height / 2,
                    width: endSize.width,
                    height: endSize.height
                )
                backdrop.alpha = 0
            },
            completion: { _ in
                overlay.removeFromSuperview()
                completion?()
            }
        )
    }
}
