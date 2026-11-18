import UIKit

@MainActor
struct ListActionItem {
    enum Content {
        case icon(UIImage)
        case title(String)
    }

    let id: String
    let content: Content
    let accessibilityLabel: String
    let handler: () -> Void
}

/// The button never scales. Only its disc does, keeping the full 56 pt target
/// available during a fill animation and leaving live overlays unclipped.
@MainActor
final class ListActionCircle: UIButton {
    let actionID: String
    let disc = UIView()
    /// Center live artwork here; disable its interaction so the button owns taps.
    let contentHost = UIView()
    var travellingHitOutset: CGFloat = 0
    private let glyph = UIImageView()
    private let label = UILabel()
    private var item: ListActionItem
    private var contentTint: UIColor = Theme.onSurface

    init(item: ListActionItem) {
        self.item = item
        actionID = item.id
        super.init(frame: .zero)
        backgroundColor = .clear
        disc.backgroundColor = AnycastColor.sandAlpha3
        disc.layer.cornerRadius = ListActionMetrics.circle / 2
        disc.isUserInteractionEnabled = false
        contentHost.isUserInteractionEnabled = false
        addSubview(disc)
        disc.addSubview(glyph)
        disc.addSubview(label)
        disc.addSubview(contentHost)
        glyph.contentMode = .scaleAspectFit
        glyph.tintColor = Theme.onSurface
        label.textColor = Theme.onSurface
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        isAccessibilityElement = true
        addTarget(self, action: #selector(invoke), for: .touchUpInside)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (circle: ListActionCircle, _) in
            circle.updateContent()
        }
        update(item)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ item: ListActionItem) {
        self.item = item
        accessibilityLabel = item.accessibilityLabel
        updateContent()
    }

    /// Live content can replace the stock symbol without losing its hit target.
    func setDefaultContentHidden(_ hidden: Bool) {
        glyph.isHidden = hidden
        label.isHidden = hidden
    }

    /// Live status replaces the glyph while retaining the current action.
    func setIcon(_ image: UIImage, tint: UIColor) {
        item = ListActionItem(
            id: item.id, content: .icon(image),
            accessibilityLabel: item.accessibilityLabel, handler: item.handler
        )
        contentTint = tint
        updateContent()
    }

    private func updateContent() {
        glyph.tintColor = contentTint
        glyph.preferredSymbolConfiguration = IconMetrics.stripSymbolConfiguration(compatibleWith: traitCollection)
        // TypographyV2 has no 12 pt semibold style.
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 12, weight: .semibold), compatibleWith: traitCollection
        )
        switch item.content {
        case let .icon(image):
            glyph.image = image.withRenderingMode(.alwaysTemplate)
            label.text = nil
        case let .title(title):
            glyph.image = nil
            label.text = title
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        disc.bounds = CGRect(origin: .zero, size: bounds.size)
        disc.center = CGPoint(x: bounds.midX, y: bounds.midY)
        contentHost.frame = disc.bounds
        glyph.sizeToFit()
        glyph.center = CGPoint(x: disc.bounds.midX, y: disc.bounds.midY)
        label.sizeToFit()
        label.center = glyph.center
    }

    @objc private func invoke() { item.handler() }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        var local = point
        if travellingHitOutset > 0, let group = superview, let presented = group.layer.presentation() {
            // At the top-clamp exception the whole group may still be moving.
            // UIControl tracking uses model coordinates even though routing
            // chose this button at its presentation position.
            local.x -= presented.frame.minX - group.frame.minX
            local.y -= presented.frame.minY - group.frame.minY
        }
        return bounds.insetBy(dx: 0, dy: -travellingHitOutset).contains(local)
    }
}

@MainActor
final class ListActionGroupView: UIView {
    private(set) var circles: [ListActionCircle] = []

    init(items: [ListActionItem] = []) {
        super.init(frame: .zero)
        configure(items)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Retain hosts for unchanged action IDs so playback/Lottie overlays survive
    /// a fill. Handlers are always replaced with the new selected identity.
    func configure(_ items: [ListActionItem]) {
        if circles.map(\.actionID) == items.map(\.id) {
            for (circle, item) in zip(circles, items) { circle.update(item) }
        } else {
            circles.forEach { $0.removeFromSuperview() }
            circles = items.map(ListActionCircle.init)
            circles.forEach(addSubview)
        }
        setNeedsLayout()
    }

    func button(for id: String) -> ListActionCircle? {
        circles.first { $0.actionID == id }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !circles.isEmpty else { return }
        // CSS space-around: one half-share at either edge, a whole share inside.
        let share = (bounds.width - CGFloat(circles.count) * ListActionMetrics.circle) / CGFloat(circles.count)
        for (index, circle) in circles.enumerated() {
            circle.frame = CGRect(
                x: bounds.minX + share / 2 + CGFloat(index) * (ListActionMetrics.circle + share),
                y: bounds.midY - ListActionMetrics.circle / 2,
                width: ListActionMetrics.circle, height: ListActionMetrics.circle
            )
        }
    }

    /// Empty space between buttons should still belong to the list.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        circles.contains { $0.frame.contains(point) }
    }

    func grow(from scale: CGFloat, reduceMotion: Bool = ListActionMotion.reduceMotion) {
        animateDiscs(growing: true, from: scale, reduceMotion: reduceMotion, completion: nil)
    }

    func shrink(reduceMotion: Bool = ListActionMotion.reduceMotion, completion: @escaping () -> Void) {
        animateDiscs(growing: false, from: 1, reduceMotion: reduceMotion, completion: completion)
    }

    /// Capture each disc separately so a ghost, including live artwork, shrinks
    /// around each button's own center instead of shrinking the entire row.
    func makeGhost() -> ListActionGroupView {
        layoutIfNeeded()
        let ghost = ListActionGroupView(items: circles.map {
            ListActionItem(id: $0.actionID, content: .title(""), accessibilityLabel: "", handler: {})
        })
        ghost.frame = frame
        ghost.layoutIfNeeded()
        ghost.isUserInteractionEnabled = false
        ghost.accessibilityElementsHidden = true
        for (source, target) in zip(circles, ghost.circles) {
            guard let snapshot = source.disc.snapshotView(afterScreenUpdates: false) else { continue }
            target.disc.backgroundColor = .clear
            snapshot.frame = target.disc.bounds
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            target.contentHost.addSubview(snapshot)
        }
        return ghost
    }

    private func animateDiscs(
        growing: Bool, from scale: CGFloat, reduceMotion: Bool, completion: (() -> Void)?
    ) {
        guard !circles.isEmpty else { completion?(); return }
        let center = CGFloat(circles.count - 1) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The transaction waits for ALL staggered animations, including the
        // center disc which finishes last when shrinking.
        CATransaction.setCompletionBlock(completion)
        let start = CACurrentMediaTime()
        for (index, circle) in circles.enumerated() {
            let layer = circle.disc.layer
            layer.removeAnimation(forKey: "list-action-disc")
            let distance = abs(CGFloat(index) - center)
            let delay = reduceMotion ? 0 : Double(growing ? distance : center - distance) * (growing ? 0.02 : 0.015)
            let duration = reduceMotion
                ? (growing ? ListActionMotion.fadeIn : ListActionMotion.fadeOut)
                : (growing ? ListActionMotion.duration : ListActionMotion.shrinkDuration)
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = growing ? (reduceMotion || scale < 0.5 ? 0 : 0.7) : 1
            opacity.toValue = growing ? 1 : 0
            var animations: [CAAnimation] = [opacity]
            if !reduceMotion {
                let size = CABasicAnimation(keyPath: "transform.scale")
                size.fromValue = growing ? scale : 1
                size.toValue = growing ? 1 : 0.2
                animations.append(size)
            }
            animations.forEach { $0.duration = duration }
            layer.opacity = growing ? 1 : 0
            layer.transform = CATransform3DIdentity
            let animation = CAAnimationGroup()
            animation.animations = animations
            animation.duration = duration
            animation.beginTime = layer.convertTime(start, from: nil) + delay
            animation.timingFunction = ListActionMotion.timingFunction
            animation.fillMode = .backwards
            layer.add(animation, forKey: "list-action-disc")
        }
        CATransaction.commit()
    }
}
