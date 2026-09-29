import UIKit

/// The single Liquid-Glass abstraction (docs/migration/07 §4). Every custom
/// floating surface (lyrics overlay, player capsule, custom search field)
/// goes through this view — no other file branches on `#available(iOS 26,*)`
/// for glass.
///
/// - iOS 26+: `UIGlassEffect(style:)`; grouped surfaces use
///   `UIGlassContainerEffect` on the OUTER view and nest plain glass effect
///   views inside `contentView` (the released iOS 26 container API — children
///   register through the container's contentView, not an initializer
///   parameter); the corner radius goes through the view's
///   `cornerConfiguration` (`uniformCorners(radius: .fixed(…))`), the iOS 26
///   structure that lives on UIView, NOT on UIGlassEffect (07 §4).
/// - iOS 18 fallback: `UIBlurEffect(.systemChromeMaterial)` + `cornerRadius`.
final class GlassContainerView: UIView {

    enum Mode {
        /// A single glass surface.
        case plain
        /// A glass CONTAINER — nest `.plain` GlassContainerViews (or glass
        /// buttons) inside this view's `contentView` to have them rendered
        /// as one fused group (lyrics overlay use case, 07 §2.5).
        case container
    }

    private let mode: Mode
    private let cornerRadius: CGFloat
    private var effectView: UIVisualEffectView?

    /// The view glass children should be added to — the effect view's
    /// contentView on iOS 26 (required for container fusion), a plain
    /// overlay otherwise.
    var glassContentView: UIView { effectView?.contentView ?? self }

    /// - Parameters:
    ///   - mode: plain surface vs. grouped container.
    ///   - cornerRadius: corner radius in points (applies to both paths).
    init(mode: Mode = .plain, cornerRadius: CGFloat) {
        self.mode = mode
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)

        backgroundColor = .clear

        let effectView = UIVisualEffectView()
        effectView.frame = bounds
        effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        super.addSubview(effectView)
        self.effectView = effectView
        applyEffect(to: effectView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Content added here must stay ABOVE the glass; the effect view is
    /// always kept at the bottom of the z-stack. Every entry point that
    /// can reorder subviews re-asserts the ordering — plain adds, indexed
    /// inserts, and hierarchy moves (`willMove(toWindow:)` fires on window
    /// attach/detach, covering the reorderings UIKit performs around
    /// removal paths).
    override func addSubview(_ view: UIView) {
        super.addSubview(view)
        keepEffectAtBack()
    }

    override func insertSubview(_ view: UIView, at index: Int) {
        super.insertSubview(view, at: index)
        keepEffectAtBack()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        keepEffectAtBack()
    }

    private func keepEffectAtBack() {
        guard let effectView, subviews.first !== effectView else { return }
        sendSubviewToBack(effectView)
    }

    private func applyEffect(to effectView: UIVisualEffectView) {
        if #available(iOS 26.0, *) {
            let effect: UIVisualEffect = mode == .container
                ? UIGlassContainerEffect()
                : UIGlassEffect(style: .regular)
            effectView.effect = effect
            effectView.cornerConfiguration = UICornerConfiguration.uniformCorners(
                radius: .fixed(cornerRadius)
            )
            return
        }
        // iOS 18 fallback: chrome-material blur + plain corner radius.
        effectView.effect = UIBlurEffect(style: .systemChromeMaterial)
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true
        layer.cornerCurve = .continuous
    }
}
