import UIKit

/// Whether a mini-player drag should finish open. Upward translation is
/// negative. A fast upward flick opens from a short travel; dragging back
/// down (or releasing below a third of the screen) cancels.
nonisolated enum PlayerDragDecision {
    /// Fraction of the screen an unhurried drag must cover to open.
    static let openFraction: CGFloat = 0.33
    /// Upward points/second that opens even when the finger has not gone far.
    static let flickSpeed: CGFloat = 900
    /// Seconds of velocity added to the finger position at release.
    static let projection: CGFloat = 0.12

    static func shouldOpen(
        translationY: CGFloat,
        velocityY: CGFloat,
        travel: CGFloat,
        cancelled: Bool
    ) -> Bool {
        if cancelled || travel <= 1 { return false }
        let projected = -translationY + (-velocityY) * projection
        return velocityY < -flickSpeed || projected > travel * openFraction
    }
}

/// Interactive mini-player swipe-up. The player follows the finger; release
/// springs open or back. Reduce Motion keeps the player full-screen and
/// crossfades it with the drag instead of translating it. On commit the real
/// page sheet takes over, so the system grabber and dismiss still apply.
@MainActor
final class PlayerInteractiveOpen {

    static let shared = PlayerInteractiveOpen()

    private var session: Session?
    private var settling = false
    private var ignoredGesture = false

    private init() {}

    func handle(
        _ gesture: UIPanGestureRecognizer,
        from presenter: UIViewController,
        context: UIContext
    ) {
        let reference = gesture.view?.window ?? presenter.view
        let translation = gesture.translation(in: reference)
        let velocity = gesture.velocity(in: reference)
        switch gesture.state {
        case .began:
            // A spring already running keeps the finger from starting a second player.
            guard !settling else { return }
            ignoredGesture = false
        case .changed:
            track(translation: translation, presenter: presenter, context: context)
        case .ended:
            // A flick can arrive as a single ended event, already past the threshold.
            track(translation: translation, presenter: presenter, context: context)
            finish(translation: translation, velocity: velocity, cancelled: false)
        case .cancelled, .failed:
            finish(translation: translation, velocity: velocity, cancelled: true)
        default:
            break
        }
    }

    private func track(
        translation: CGPoint,
        presenter: UIViewController,
        context: UIContext
    ) {
        if ignoredGesture || settling { return }
        if session == nil {
            // A tiny pan must not open. Wait until the drag is clearly upward.
            guard translation.y < -Spacing.gap else {
                if translation.y > Spacing.gap || abs(translation.x) > Spacing.gap {
                    ignoredGesture = abs(translation.x) > abs(translation.y)
                }
                return
            }
            guard abs(translation.y) > abs(translation.x) else {
                ignoredGesture = true
                return
            }
            begin(from: presenter, context: context)
        }
        guard let session else { return }
        let travel = max(session.travel, 1)
        let upward = max(0, -translation.y)
        let progressed = min(upward / travel, 1)
        session.progress = progressed
        let reduce = Motion.reduceMotion
        if reduce {
            session.player.view.transform = .identity
            session.player.view.alpha = progressed
            session.dimming.alpha = progressed * Session.dimmingAlpha
            return
        }
        let offset: CGFloat
        if upward > travel {
            offset = travel + Motion.rubberBand(upward - travel)
        } else {
            offset = upward
        }
        session.player.view.alpha = 1
        session.player.view.transform = CGAffineTransform(translationX: 0, y: travel - offset)
        session.dimming.alpha = progressed * Session.dimmingAlpha
    }

    private func begin(from presenter: UIViewController, context: UIContext) {
        guard session == nil, !settling else { return }
        guard presenter.presentedViewController == nil, let window = presenter.view.window else { return }
        let player = PlayerPageContainer(context: context)
        player.loadViewIfNeeded()
        let travel = window.bounds.height
        player.view.frame = window.bounds
        player.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        player.view.layer.cornerRadius = Radius.largeCard
        player.view.layer.cornerCurve = .continuous
        player.view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        player.view.clipsToBounds = true

        let dimming = UIView(frame: window.bounds)
        dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimming.backgroundColor = .black
        dimming.alpha = 0

        let grabber = UIView()
        grabber.translatesAutoresizingMaskIntoConstraints = false
        grabber.backgroundColor = Theme.playerText.withAlphaComponent(0.55)
        grabber.layer.cornerRadius = 2.5
        grabber.isUserInteractionEnabled = false
        player.view.addSubview(grabber)
        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: player.view.topAnchor, constant: Spacing.sm),
            grabber.centerXAnchor.constraint(equalTo: player.view.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),
        ])

        presenter.addChild(player)
        window.addSubview(dimming)
        window.addSubview(player.view)
        player.didMove(toParent: presenter)
        if Motion.reduceMotion {
            player.view.transform = .identity
            player.view.alpha = 0
        } else {
            player.view.alpha = 1
            player.view.transform = CGAffineTransform(translationX: 0, y: travel)
        }
        session = Session(
            presenter: presenter,
            player: player,
            dimming: dimming,
            grabber: grabber,
            window: window,
            travel: travel
        )
    }

    private func finish(translation: CGPoint, velocity: CGPoint, cancelled: Bool) {
        guard let session, !settling else {
            ignoredGesture = false
            return
        }
        settling = true
        let travel = max(session.window.bounds.height, session.travel)
        let open = PlayerDragDecision.shouldOpen(
            translationY: translation.y,
            velocityY: velocity.y,
            travel: travel,
            cancelled: cancelled
        )
        let reduce = Motion.reduceMotion
        let currentY = session.player.view.transform.ty
        let targetY: CGFloat = open ? 0 : travel
        let distance = targetY - currentY
        let unit = abs(distance) > 1 ? max(-8, min(8, velocity.y / distance)) : 0
        UIView.animate(
            withDuration: reduce ? Motion.quick : Motion.emphasized,
            delay: 0,
            usingSpringWithDamping: reduce ? 1 : 0.86,
            initialSpringVelocity: reduce ? 0 : unit,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            if reduce {
                session.player.view.transform = .identity
                session.player.view.alpha = open ? 1 : 0
            } else {
                session.player.view.alpha = 1
                session.player.view.transform = CGAffineTransform(translationX: 0, y: targetY)
            }
            session.dimming.alpha = open ? Session.dimmingAlpha : 0
        } completion: { [weak self] _ in
            guard let self else { return }
            if open {
                self.handOff(session)
            } else {
                self.tearDown(session)
            }
            if self.session === session { self.session = nil }
            self.settling = false
            self.ignoredGesture = false
        }
    }

    private func handOff(_ session: Session) {
        let player = session.player
        let presenter = session.presenter
        let snapshot = player.view.snapshotView(afterScreenUpdates: false)
        if let snapshot {
            snapshot.frame = player.view.frame
            snapshot.transform = player.view.transform
            session.window.addSubview(snapshot)
        }
        session.dimming.removeFromSuperview()
        session.grabber.removeFromSuperview()
        player.willMove(toParent: nil)
        player.view.removeFromSuperview()
        player.removeFromParent()
        player.view.transform = .identity
        player.view.alpha = 1
        player.view.clipsToBounds = false
        player.view.layer.cornerRadius = 0
        player.view.layer.maskedCorners = [
            .layerMinXMinYCorner, .layerMaxXMinYCorner,
            .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
        ]
        player.adoptSystemSheet()
        presenter.present(player, animated: false)
        snapshot?.removeFromSuperview()
    }

    private func tearDown(_ session: Session) {
        session.dimming.removeFromSuperview()
        session.grabber.removeFromSuperview()
        session.player.willMove(toParent: nil)
        session.player.view.removeFromSuperview()
        session.player.removeFromParent()
    }

    private final class Session {
        static let dimmingAlpha: CGFloat = 0.4
        let presenter: UIViewController
        let player: PlayerPageContainer
        let dimming: UIView
        let grabber: UIView
        let window: UIWindow
        let travel: CGFloat
        var progress: CGFloat = 0

        init(
            presenter: UIViewController,
            player: PlayerPageContainer,
            dimming: UIView,
            grabber: UIView,
            window: UIWindow,
            travel: CGFloat
        ) {
            self.presenter = presenter
            self.player = player
            self.dimming = dimming
            self.grabber = grabber
            self.window = window
            self.travel = travel
        }
    }
}
