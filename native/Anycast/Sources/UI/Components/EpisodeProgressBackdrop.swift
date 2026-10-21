import UIKit

/// The position-driven progress-bar backdrop used by playlist cards and the
/// mini player (03 §2.11 / §2.9): a backdrop whose FILLED width equals
/// `fraction × own bounds`. The caller sizes the view (the card's 36 × 4
/// inline meter, or the mini player's full-height backdrop) — this
/// view fills whatever bounds it gets, driven purely by fraction, never by
/// screen width (iOS 27 resizable-window rule, 07 §4), and updated through
/// layers so per-tick updates never trigger a layout pass (08 §11.2).
final class EpisodeProgressBackdrop: UIView {

    /// Optional unfilled-track surface behind the fill (nil → transparent;
    /// the card's own background shows through, as in the Dart card).
    var trackColor: UIColor? {
        didSet { applyColors() }
    }

    /// Fill color: white 20% on the mini player (03 §2.9); cards use the
    /// same translucent white by default.
    var fillColor: UIColor = UIColor.white.withAlphaComponent(0.2) {
        didSet { applyColors() }
    }

    /// Smallest visible fill while any progress exists, so a just-started
    /// episode still reads as started (the card meter uses 3 pt).
    var minimumFillWidth: CGFloat = 0

    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private var fraction: Double = 0

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.addSublayer(trackLayer)
        layer.addSublayer(fillLayer)
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.applyColors()
        }
    }

    /// Layer colors are CGColors, frozen at assignment (09 §9a); resolve
    /// them against the current traits and again on appearance changes.
    private func applyColors() {
        trackLayer.backgroundColor = trackColor?.resolvedColor(with: traitCollection).cgColor
        fillLayer.backgroundColor = fillColor.resolvedColor(with: traitCollection).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Progress 0…1; clamped, and a non-finite value counts as 0 (min/max
    /// do not filter NaN). Updates the fill width against CURRENT bounds.
    func setFraction(_ value: Double) {
        fraction = min(max(value.isFinite ? value : 0, 0), 1)
        applyFraction()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyFraction()
    }

    private func applyFraction() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        let width = fraction > 0 ? max(bounds.width * CGFloat(fraction), minimumFillWidth) : 0
        fillLayer.frame = CGRect(x: 0, y: 0, width: min(width, bounds.width), height: bounds.height)
        CATransaction.commit()
    }
}
