import UIKit
import ChatLayout

/// Plain-text message in the Anycast 2.0 UI kit chat language
/// (reading-first): the listener's messages sit in a quiet sand bubble, the
/// assistant's replies read as plain text on the page; layout and
/// timestamps are unchanged.
final class ChatBubbleView: UIView {

    private enum Metrics {
        static let bubbleRadius = Radius.md
        static let bubbleHorizontalPadding: CGFloat = 16
        static let bubbleVerticalPadding: CGFloat = 10
        static let timeGap: CGFloat = 2
        /// Cap on the bubble width as a fraction of the list width
        /// (ChatLayout example's Constants.maxWidth role).
        static let maxBubbleWidthFraction: CGFloat = 0.75
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private let textLabel = UILabel()
    private let timeLabel = UILabel()
    private var bubbleWidthConstraint: NSLayoutConstraint?
    private var viewportWidth: CGFloat = 320

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setUpSubviews() {
        insetsLayoutMarginsFromSafeArea = false
        layoutMargins = UIEdgeInsets(
            top: Metrics.bubbleVerticalPadding,
            left: Metrics.bubbleHorizontalPadding,
            bottom: Metrics.bubbleVerticalPadding,
            right: Metrics.bubbleHorizontalPadding
        )
        layer.cornerRadius = Metrics.bubbleRadius
        layer.cornerCurve = .continuous

        textLabel.numberOfLines = 0
        // A long unbreakable token (AI replies quote URLs) is wider than the
        // 0.75×viewport cap; with a required compression resistance the cap
        // is what breaks and the bubble overflows the list. Let the cap win
        // and wrap the token per character instead.
        textLabel.lineBreakMode = .byCharWrapping
        textLabel.textColor = Theme.onSurface
        textLabel.font = TypographyV2.bodyLarge.font()
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.setContentHuggingPriority(.required, for: .horizontal)
        textLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        timeLabel.textColor = Theme.onSurfaceVariant
        timeLabel.font = TypographyV2.labelSmall.font()
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)
        addSubview(timeLabel)
        bubbleWidthConstraint = widthAnchor.constraint(lessThanOrEqualToConstant: viewportWidth)
        bubbleWidthConstraint?.isActive = true
        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            textLabel.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            timeLabel.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: Metrics.timeGap),
            timeLabel.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])
    }

    func configure(with message: ChatMessage) {
        backgroundColor = message.author == .human ? AnycastColor.sandAlpha3 : .clear
        textLabel.textColor = Theme.onSurface
        timeLabel.textColor = Theme.onSurfaceVariant
        textLabel.text = message.text
        timeLabel.text = Self.timeFormatter.string(from: message.createdAt)
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = "\(ChatConversation.displayName(for: message.author)): \(message.text)"
    }
}

extension ChatBubbleView: ContainerCollectionViewCellDelegate {

    func prepareForReuse() {
        // Keep the view; ChatLayout recycles via the generic container.
    }

    func apply(_ layoutAttributes: ChatLayoutAttributes) {
        viewportWidth = layoutAttributes.layoutFrame.width
        bubbleWidthConstraint?.constant = viewportWidth * Metrics.maxBubbleWidthFraction
    }
}
