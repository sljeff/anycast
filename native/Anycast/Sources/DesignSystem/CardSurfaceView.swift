import UIKit

/// The Anycast 2.0 card plate (09 §5 inbox card language): `surface` fill,
/// `sandAlpha3` hairline, continuous corners. Content is flat (one floating
/// layer, adopted 2026-10-21), so the plate casts no shadow. The hairline is
/// a CGColor, so it is re-resolved on appearance changes (09 §9a).
final class CardSurfaceView: UIView {

    init(radius: CGFloat = Radius.largeCard) {
        super.init(frame: .zero)
        backgroundColor = Theme.surface
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.borderWidth = Spacing.hairline
        updateStroke()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.updateStroke()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateStroke() {
        layer.borderColor = AnycastColor.sandAlpha3.resolvedColor(with: traitCollection).cgColor
    }
}
