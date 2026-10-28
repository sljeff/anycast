import UIKit

/// The transcript page's one status slot (design board "Status capsule
/// states"): a 44 pt tall, centered capsule above the scrubber that shows
/// exactly one state at a time — following, back to now, the jump undo,
/// transcript generation states and the inline translation status. Player
/// colors only: the player is always dark, so nothing here adapts to the
/// appearance.
final class TranscriptStatusCapsuleView: UIView {

    struct Content {

        enum Leading {
            case none
            case dot
            case spinner
            case icon(UIImage?)
        }

        enum Style {
            /// Quiet 8% chip: optional leading glyph, Meta message and an
            /// optional plain text action.
            case chip
            /// Filled pill button with a leading chevron (Back to now).
            case filledButton
        }

        /// Identity of the shown state: re-showing the same id leaves the
        /// current capsule untouched (a spinner must not restart on every
        /// refresh).
        var id: String
        var style: Style = .chip
        var leading: Leading = .none
        var message: String
        var action: (title: String, handler: () -> Void)?
    }

    static let height: CGFloat = 44

    private(set) var currentID: String?
    private var pill: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        overrideUserInterfaceStyle = .dark
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows `content` (nil clears the slot). Different states cross-fade;
    /// the slot's size never changes.
    func show(_ content: Content?, animated: Bool = true) {
        guard content?.id != currentID else { return }
        currentID = content?.id
        let old = pill
        pill = nil

        var new: UIView?
        if let content {
            let built = makePill(content)
            built.translatesAutoresizingMaskIntoConstraints = false
            addSubview(built)
            NSLayoutConstraint.activate([
                built.centerXAnchor.constraint(equalTo: centerXAnchor),
                built.centerYAnchor.constraint(equalTo: centerYAnchor),
                built.heightAnchor.constraint(equalToConstant: Self.height),
                built.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
                built.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            ])
            new = built
            pill = built
        }

        guard animated, window != nil, !UIAccessibility.isReduceMotionEnabled else {
            old?.removeFromSuperview()
            return
        }
        new?.alpha = 0
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            new?.alpha = 1
            old?.alpha = 0
        } completion: { _ in
            old?.removeFromSuperview()
        }
    }

    // MARK: - Pills

    private func makePill(_ content: Content) -> UIView {
        switch content.style {
        case .filledButton: return makeFilledButton(content)
        case .chip: return makeChip(content)
        }
    }

    private func makeFilledButton(_ content: Content) -> UIView {
        var configuration = UIButton.Configuration.filled()
        configuration.title = content.message
        if case .icon(let image) = content.leading {
            configuration.image = image
            configuration.imagePadding = 8
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        }
        configuration.baseBackgroundColor = Theme.playerText
        configuration.baseForegroundColor = Theme.playerBackground
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18)
        configuration.titleTextAttributesTransformer = Self.emphasisTransformer
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = content.message
        if let action = content.action {
            button.addAction(UIAction { _ in action.handler() }, for: .touchUpInside)
        }
        button.addPressFeedback()
        return button
    }

    private func makeChip(_ content: Content) -> UIView {
        let chip = UIView()
        chip.backgroundColor = Theme.playerText.withAlphaComponent(0.08)
        chip.layer.cornerRadius = Self.height / 2
        chip.layer.cornerCurve = .continuous

        var elements: [UIView] = []
        switch content.leading {
        case .none:
            break
        case .dot:
            let dot = UIView()
            dot.backgroundColor = Theme.playerText
            dot.layer.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 8),
                dot.heightAnchor.constraint(equalToConstant: 8),
            ])
            elements.append(dot)
        case .spinner:
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.color = Theme.playerText
            spinner.startAnimating()
            elements.append(spinner)
        case .icon(let image):
            let glyph = UIImageView(image: image)
            glyph.tintColor = Theme.playerText
            glyph.contentMode = .center
            glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            elements.append(glyph)
        }

        let label = UILabel()
        label.text = content.message
        label.font = TypographyV2.meta.font()
        label.textColor = Theme.playerSecondary
        label.adjustsFontForContentSizeCategory = true
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        elements.append(label)

        if let action = content.action {
            var configuration = UIButton.Configuration.plain()
            configuration.title = action.title
            configuration.baseForegroundColor = Theme.playerText
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
            configuration.titleTextAttributesTransformer = Self.emphasisTransformer
            let button = UIButton(configuration: configuration)
            button.addAction(UIAction { _ in action.handler() }, for: .touchUpInside)
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.heightAnchor.constraint(equalToConstant: Self.height).isActive = true
            button.accessibilityLabel = action.title
            elements.append(button)
        }

        let row = UIStackView(arrangedSubviews: elements)
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        // The action's own insets provide the trailing padding (design: 4 pt
        // after the button, 16 pt after a plain message).
        row.setCustomSpacing(4, after: label)
        row.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: content.action == nil ? -16 : -4),
            row.topAnchor.constraint(equalTo: chip.topAnchor),
            row.bottomAnchor.constraint(equalTo: chip.bottomAnchor),
        ])

        // Without an action the chip is one status element for VoiceOver.
        if content.action == nil {
            chip.isAccessibilityElement = true
            chip.accessibilityLabel = content.message
            chip.accessibilityTraits = .staticText
        }
        return chip
    }

    private static let emphasisTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var outgoing = incoming
        outgoing.font = TypographyV2.emphasis.font()
        return outgoing
    }
}
