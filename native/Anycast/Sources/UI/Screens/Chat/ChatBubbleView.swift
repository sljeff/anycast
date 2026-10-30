import UIKit
import ChatLayout

/// Plain-text message on the player's always-dark palette: the listener's
/// messages sit in a quiet filled bubble, the assistant's replies read as
/// plain text on the sheet, with a "▶ 12:40" button under it for each moment
/// the reply cites (tap to play from there). A message that failed to send
/// is dimmed and carries an inline "Not sent · Tap to resend" button under it.
final class ChatBubbleView: UIView {

    private enum Metrics {
        static let bubbleRadius = Radius.md
        static let bubbleHorizontalPadding: CGFloat = 16
        static let bubbleVerticalPadding: CGFloat = 10
        static let resendGap: CGFloat = 2
        static let resendHeight: CGFloat = 44
        static let failedAlpha: CGFloat = 0.6
        /// Cap on the bubble width as a fraction of the list width
        /// (ChatLayout example's Constants.maxWidth role).
        static let maxBubbleWidthFraction: CGFloat = 0.75
        /// At most this many jump buttons under one reply.
        static let maxJumps = 3
        static let jumpHeight: CGFloat = 36
        static let jumpSpacing: CGFloat = 8
        static let jumpTopGap: CGFloat = 8
    }

    /// Fill of the listener's bubble (playerText at ~12%).
    static let humanFill = Theme.playerText.withAlphaComponent(0.12)

    /// Called when the failed-message button is tapped.
    var onResend: (() -> Void)?
    /// Called with the cited moment (milliseconds) when a jump button is tapped.
    var onJump: ((Int) -> Void)?

    /// The filled rounded bubble (clear for assistant replies).
    let bubble = UIView()
    private let textLabel = UILabel()
    private let resendButton = UIButton(type: .system)
    private let jumpRow = UIStackView()
    private let stack = UIStackView()
    private var bubbleWidthConstraint: NSLayoutConstraint?
    private var viewportWidth: CGFloat = 320
    /// The listener's bubble is capped; the assistant's flush text spans the
    /// full content width.
    private var isHuman = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setUpSubviews() {
        bubble.insetsLayoutMarginsFromSafeArea = false
        bubble.layer.cornerRadius = Metrics.bubbleRadius
        bubble.layer.cornerCurve = .continuous

        textLabel.numberOfLines = 0
        // Word wrapping still breaks a token wider than the line (AI replies
        // quote URLs) per character, so the width cap always wins and the
        // bubble never overflows the list.
        textLabel.lineBreakMode = .byWordWrapping
        textLabel.textColor = Theme.playerText
        textLabel.font = TypographyV2.body.font()
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.setContentHuggingPriority(.required, for: .horizontal)
        textLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(textLabel)
        bubble.isAccessibilityElement = true
        bubble.accessibilityTraits = .staticText

        var buttonConfig = UIButton.Configuration.plain()
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        buttonConfig.baseForegroundColor = Theme.playerSecondary
        buttonConfig.attributedTitle = AttributedString(
            "Not sent · Tap to resend",
            attributes: AttributeContainer([.font: TypographyV2.meta.font()])
        )
        resendButton.configuration = buttonConfig
        resendButton.titleLabel?.adjustsFontForContentSizeCategory = true
        resendButton.isHidden = true
        resendButton.addAction(UIAction { [weak self] _ in self?.onResend?() }, for: .touchUpInside)

        stack.axis = .vertical
        stack.spacing = Metrics.resendGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        jumpRow.axis = .horizontal
        jumpRow.spacing = Metrics.jumpSpacing
        jumpRow.isHidden = true

        stack.addArrangedSubview(bubble)
        stack.addArrangedSubview(jumpRow)
        stack.setCustomSpacing(Metrics.jumpTopGap, after: bubble)
        stack.addArrangedSubview(resendButton)
        addSubview(stack)

        bubbleWidthConstraint = bubble.widthAnchor.constraint(lessThanOrEqualToConstant: viewportWidth)
        bubbleWidthConstraint?.isActive = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            resendButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.resendHeight),
            textLabel.leadingAnchor.constraint(equalTo: bubble.layoutMarginsGuide.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: bubble.layoutMarginsGuide.trailingAnchor),
            textLabel.topAnchor.constraint(equalTo: bubble.layoutMarginsGuide.topAnchor),
            textLabel.bottomAnchor.constraint(equalTo: bubble.layoutMarginsGuide.bottomAnchor),
        ])
    }

    private func updateWidthCap() {
        bubbleWidthConstraint?.constant = isHuman
            ? viewportWidth * Metrics.maxBubbleWidthFraction
            : viewportWidth
        // A multi-line label sizes itself from its current bounds, so a cell
        // reconfigured from "..." to a long reply stayed one character wide.
        // Pin the wrap width explicitly (padding is known per author, since
        // the live layout margins may not be set yet).
        let padding = isHuman ? Metrics.bubbleHorizontalPadding * 2 : 0
        textLabel.preferredMaxLayoutWidth = max((bubbleWidthConstraint?.constant ?? 0) - padding, 0)
    }

    func configure(with message: ChatMessage) {
        let isHuman = message.author == .human
        self.isHuman = isHuman
        updateWidthCap()
        let isFailed = message.deliveryState == .failed
        bubble.backgroundColor = isHuman ? Self.humanFill : .clear
        // The assistant's text sits flush with the sheet inset: no bubble,
        // no padding.
        bubble.layoutMargins = isHuman
            ? UIEdgeInsets(
                top: Metrics.bubbleVerticalPadding, left: Metrics.bubbleHorizontalPadding,
                bottom: Metrics.bubbleVerticalPadding, right: Metrics.bubbleHorizontalPadding
            )
            : .zero
        stack.alignment = isHuman ? .trailing : .leading
        bubble.alpha = isFailed ? Metrics.failedAlpha : 1
        resendButton.isHidden = !isFailed
        textLabel.text = message.text
        configureJumps(isHuman ? [] : Array(EpisodeChapters.timestamps(in: message.text).prefix(Metrics.maxJumps)))
        bubble.accessibilityLabel = "\(ChatConversation.displayName(for: message.author)): \(message.text)"
    }

    private func configureJumps(_ targets: [Int]) {
        jumpRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        jumpRow.isHidden = targets.isEmpty
        for target in targets {
            let time = PlayerProgressClock.positionText(Int64(target))
            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = Self.humanFill
            config.baseForegroundColor = Theme.primary
            config.cornerStyle = .capsule
            config.image = UIImage(systemName: "play.fill")
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                font: TypographyV2.meta.font(), scale: .small
            )
            config.imagePadding = 6
            config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
            config.attributedTitle = AttributedString(
                time, attributes: AttributeContainer([.font: TypographyV2.meta.font().monospacedDigits()])
            )
            let button = UIButton(configuration: config)
            button.accessibilityLabel = "Play from \(time)"
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.jumpHeight).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.onJump?(target) }, for: .touchUpInside)
            jumpRow.addArrangedSubview(button)
        }
    }
}

extension ChatBubbleView: ContainerCollectionViewCellDelegate {

    func prepareForReuse() {
        onResend = nil
        onJump = nil
    }

    func apply(_ layoutAttributes: ChatLayoutAttributes) {
        viewportWidth = layoutAttributes.layoutFrame.width
        updateWidthCap()
    }
}
