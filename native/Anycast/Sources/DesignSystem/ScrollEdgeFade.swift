import UIKit

/// A non-interactive scrim that keeps scrolled content from being hard-cut
/// at a fixed edge (G-7): a `fadeLength` gradient from the page background
/// to clear at its inner edge, solid page background everywhere beyond it.
/// `.top` sits under a fixed header (solid side up), `.bottom` above a
/// bottom bar (solid side down). Colors re-resolve on trait changes
/// (CGColor is frozen at assignment).
@MainActor
final class ScrollEdgeFade: UIView {

    enum Edge { case top, bottom }

    static let fadeLength: CGFloat = 16

    private let edge: Edge
    private let color: UIColor
    private let gradient = CAGradientLayer()

    init(edge: Edge, color: UIColor = Theme.background) {
        self.edge = edge
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        backgroundColor = .clear
        // Vertical gradient, y grows downward in the layer's unit space.
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradient)
        updateColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.updateColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        // The ramp spans exactly `fadeLength` at the inner edge; a view no
        // taller than that is a pure gradient.
        let height = bounds.height
        let fraction = height > Self.fadeLength ? Self.fadeLength / height : 1
        switch edge {
        case .top:
            // Opaque from the top down to the ramp, clear at the bottom.
            gradient.locations = [NSNumber(value: 1 - fraction), 1]
        case .bottom:
            // Clear at the top, opaque after the ramp to the bottom.
            gradient.locations = [0, NSNumber(value: fraction)]
        }
        CATransaction.commit()
    }

    private func updateColors() {
        let resolved = color.resolvedColor(with: traitCollection)
        let opaque = resolved.withAlphaComponent(1).cgColor
        let clear = resolved.withAlphaComponent(0).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = edge == .top ? [opaque, clear] : [clear, opaque]
        CATransaction.commit()
    }
}
