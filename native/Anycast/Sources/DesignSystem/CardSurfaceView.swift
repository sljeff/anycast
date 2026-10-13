import UIKit

/// The Anycast 2.0 card plate (09 §5 inbox card language): `surface` fill,
/// `sandAlpha3` hairline, soft 0/1/10 4% shadow, continuous corners. The
/// hairline is a CGColor, so it is re-resolved on appearance changes
/// (09 §9a), and the shadow path follows the bounds.
final class CardSurfaceView: UIView {

    private let radius: CGFloat

    init(radius: CGFloat = Radius.card) {
        self.radius = radius
        super.init(frame: .zero)
        backgroundColor = Theme.surface
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.borderWidth = Spacing.hairline
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.04
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 10
        updateStroke()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.updateStroke()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
    }

    private func updateStroke() {
        layer.borderColor = AnycastColor.sandAlpha3.resolvedColor(with: traitCollection).cgColor
    }
}
