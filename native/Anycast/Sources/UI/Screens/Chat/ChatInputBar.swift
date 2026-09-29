import UIKit

/// Hand-written plain-text input bar (07 §2.6: InputBarAccessoryView is
/// deliberately NOT used). Mirrors the flutter_chat_ui composer defaults
/// the shipped page kept: surfaceContainerLow bar background, a rounded
/// (24) filled field (surfaceContainerHigh @ 80%) with "Type a message"
/// placeholder, and a send glyph at onSurface 50%; multi-line up to 3
/// lines; the button disables while a request is in flight.
final class ChatInputBar: UIView {

    private enum Metrics {
        static let barBackground = UIColor(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, alpha: 1)
        static let fieldFill = UIColor(red: 0x24 / 255, green: 0x24 / 255, blue: 0x24 / 255, alpha: 0.8)
        static let onSurface50 = UIColor.white.withAlphaComponent(0.5)
        static let fieldRadius: CGFloat = 24
        static let barPadding: CGFloat = 8
        static let fieldVerticalPadding: CGFloat = 9
        static let fieldHorizontalPadding: CGFloat = 12
    }

    var onSend: ((String) -> Void)?

    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .custom)
    private var fieldHeightLimit: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setUpSubviews() {
        backgroundColor = Metrics.barBackground
        insetsLayoutMarginsFromSafeArea = false

        let fieldFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 14, weight: .regular)
        )
        textView.font = fieldFont
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .white
        textView.backgroundColor = Metrics.fieldFill
        textView.layer.cornerRadius = Metrics.fieldRadius
        textView.layer.cornerCurve = .continuous
        textView.textContainerInset = UIEdgeInsets(
            top: Metrics.fieldVerticalPadding,
            left: Metrics.fieldHorizontalPadding,
            bottom: Metrics.fieldVerticalPadding,
            right: Metrics.fieldHorizontalPadding
        )
        textView.keyboardAppearance = .dark
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.isAccessibilityElement = true
        textView.accessibilityLabel = "Message"
        textView.accessibilityHint = "Message the AI about this episode"

        placeholderLabel.text = "Type a message"
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = Metrics.onSurface50
        placeholderLabel.isUserInteractionEnabled = false

        sendButton.setImage(UIImage(systemName: "paperplane.fill"), for: .normal)
        sendButton.tintColor = Metrics.onSurface50
        sendButton.isEnabled = false
        sendButton.isAccessibilityElement = true
        sendButton.accessibilityLabel = "Send message"
        sendButton.addAction(
            UIAction { [weak self] _ in self?.submit() },
            for: .touchUpInside
        )

        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        addSubview(placeholderLabel)
        addSubview(sendButton)
        NSLayoutConstraint.activate([
            layoutMarginsGuide.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.barPadding),
            layoutMarginsGuide.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.barPadding),
            layoutMarginsGuide.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.barPadding),
            layoutMarginsGuide.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.barPadding),

            textView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            textView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),

            placeholderLabel.leadingAnchor.constraint(
                equalTo: textView.leadingAnchor, constant: Metrics.fieldHorizontalPadding
            ),
            placeholderLabel.topAnchor.constraint(
                equalTo: textView.topAnchor, constant: Metrics.fieldVerticalPadding
            ),

            sendButton.leadingAnchor.constraint(equalTo: textView.trailingAnchor, constant: Metrics.barPadding),
            sendButton.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            sendButton.centerYAnchor.constraint(equalTo: textView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 32),
            sendButton.heightAnchor.constraint(equalToConstant: 32),
        ])
        // Cap growth at 3 text lines; beyond that the field scrolls. The
        // cap is recomputed on Dynamic Type changes — a limit sized once
        // at the launch category drifts as the body font scales.
        fieldHeightLimit = textView.heightAnchor.constraint(lessThanOrEqualToConstant: 0)
        fieldHeightLimit?.isActive = true
        refreshFieldHeightCap()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (view: ChatInputBar, _: UITraitCollection) in
            view.refreshFieldHeightCap()
        }
        refreshSendState()
    }

    /// Recomputes the 3-line height cap from the CURRENT body font.
    private func refreshFieldHeightCap() {
        let font = textView.font ?? UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 14, weight: .regular)
        )
        fieldHeightLimit?.constant = 3 * font.lineHeight + 2 * Metrics.fieldVerticalPadding
    }

    private var isSending = false

    /// isLoading gating (states/chat.dart onMessageSend): no sending while
    /// a request is in flight.
    func setSending(_ sending: Bool) {
        isSending = sending
        refreshSendState()
    }

    /// Dart Composer InputClearMode.always: the field clears whenever a
    /// send is submitted.
    func clearText() {
        textView.text = String()
        textView.isScrollEnabled = false
        refreshSendState()
    }

    private var hasText: Bool {
        textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func submit() {
        guard hasText else { return }
        onSend?(textView.text)
    }

    private func refreshSendState() {
        sendButton.isEnabled = hasText && !isSending
        placeholderLabel.isHidden = !textView.text.isEmpty
    }
}

extension ChatInputBar: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        let limit = fieldHeightLimit?.constant ?? .greatestFiniteMagnitude
        textView.isScrollEnabled = textView.contentSize.height > limit
        refreshSendState()
    }
}
