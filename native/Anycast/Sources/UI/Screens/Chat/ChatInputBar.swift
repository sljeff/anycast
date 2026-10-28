import UIKit

/// Hand-written plain-text input bar (07 §2.6: InputBarAccessoryView is
/// deliberately NOT used) on the player's always-dark palette: ONE glass pill
/// (the same surface as the search field) holding the text view and, at its
/// trailing end, a round send button that only appears once there is
/// something to send. 48 pt for a single line, multi-line up to 3 lines
/// then it scrolls; the button hides while a request is in flight.
final class ChatInputBar: UIView {

    private enum Metrics {
        static let secondary = Theme.playerSecondary
        static let pillRadius: CGFloat = 24
        /// Single-line height, shared with the search field.
        static let pillHeight: CGFloat = 48
        static let sendSide: CGFloat = 32
        /// Send button inset from the pill's trailing and bottom edges
        /// (centred for one line: (48 - 32) / 2).
        static let sendInset: CGFloat = 8
        static let barPadding: CGFloat = 8
        /// Sheet content inset: the pill sits 28 pt from the sides; the
        /// owner positions the bar's bottom edge.
        static let sideInset: CGFloat = 28
        static let minVerticalPadding: CGFloat = 8
        static let fieldHorizontalPadding: CGFloat = 20
        /// Text always stops short of the send button's slot, so the text
        /// does not reflow when the button appears.
        static let textTrailingPadding: CGFloat = sendSide + 2 * sendInset
        static let hiddenSendScale: CGFloat = 0.6
    }

    var onSend: ((String) -> Void)?

    private let glass = GlassContainerView(cornerRadius: Metrics.pillRadius)
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .custom)
    private var fieldHeightLimit: NSLayoutConstraint?
    /// Pins the field at the cap while it scrolls (a scrolling text view has
    /// no intrinsic height to grow with).
    private var fieldScrollHeight: NSLayoutConstraint?
    private var placeholderTop: NSLayoutConstraint?
    /// Top/bottom text inset: makes one body line exactly `pillHeight`.
    private var verticalPadding = Metrics.minVerticalPadding

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setUpSubviews() {
        backgroundColor = .clear
        insetsLayoutMarginsFromSafeArea = false
        directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.barPadding, leading: Metrics.sideInset, bottom: 0, trailing: Metrics.sideInset
        )

        textView.font = TypographyV2.body.font()
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = Theme.playerText
        textView.backgroundColor = .clear
        textView.textContainer.lineFragmentPadding = 0
        textView.keyboardAppearance = .dark
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.isAccessibilityElement = true
        textView.accessibilityLabel = "Message"
        textView.accessibilityHint = "Message the AI about this episode"

        placeholderLabel.text = "Ask about this episode"
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = Metrics.secondary
        placeholderLabel.isUserInteractionEnabled = false

        sendButton.setImage(UIImage(systemName: "arrow.up"), for: .normal)
        sendButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .bold), forImageIn: .normal
        )
        sendButton.tintColor = Theme.playerBackground
        sendButton.backgroundColor = Theme.playerText
        sendButton.layer.cornerRadius = Metrics.sendSide / 2
        sendButton.isEnabled = false
        sendButton.isAccessibilityElement = true
        sendButton.accessibilityLabel = "Send message"
        sendButton.addAction(
            UIAction { [weak self] _ in self?.submit() },
            for: .touchUpInside
        )
        applySendVisibility(false)

        glass.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        glass.addSubview(textView)
        glass.addSubview(placeholderLabel)
        glass.addSubview(sendButton)
        let placeholderTop = placeholderLabel.topAnchor.constraint(equalTo: glass.topAnchor)
        self.placeholderTop = placeholderTop
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            glass.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            glass.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            glass.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.pillHeight),

            textView.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            textView.topAnchor.constraint(equalTo: glass.topAnchor),
            textView.bottomAnchor.constraint(equalTo: glass.bottomAnchor),

            placeholderLabel.leadingAnchor.constraint(
                equalTo: glass.leadingAnchor, constant: Metrics.fieldHorizontalPadding
            ),
            placeholderTop,

            sendButton.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -Metrics.sendInset),
            sendButton.bottomAnchor.constraint(equalTo: glass.bottomAnchor, constant: -Metrics.sendInset),
            sendButton.widthAnchor.constraint(equalToConstant: Metrics.sendSide),
            sendButton.heightAnchor.constraint(equalToConstant: Metrics.sendSide),
        ])
        // Cap growth at 3 text lines; beyond that the field scrolls. The
        // cap is recomputed on Dynamic Type changes — a limit sized once
        // at the launch category drifts as the body font scales.
        fieldHeightLimit = textView.heightAnchor.constraint(lessThanOrEqualToConstant: 0)
        fieldHeightLimit?.isActive = true
        fieldScrollHeight = textView.heightAnchor.constraint(equalToConstant: 0)
        refreshFieldHeightCap()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (view: ChatInputBar, _: UITraitCollection) in
            view.refreshFieldHeightCap()
        }
        refreshSendState()
    }

    /// Recomputes the text insets and the 3-line height cap from the
    /// CURRENT body font.
    private func refreshFieldHeightCap() {
        let font = textView.font ?? TypographyV2.body.font()
        verticalPadding = max(Metrics.minVerticalPadding, ((Metrics.pillHeight - font.lineHeight) / 2).rounded(.down))
        textView.textContainerInset = UIEdgeInsets(
            top: verticalPadding,
            left: Metrics.fieldHorizontalPadding,
            bottom: verticalPadding,
            right: Metrics.textTrailingPadding
        )
        placeholderTop?.constant = verticalPadding
        fieldHeightLimit?.constant = 3 * font.lineHeight + 2 * verticalPadding
        fieldScrollHeight?.constant = fieldHeightLimit?.constant ?? 0
    }

    private var isSending = false

    /// Current composer text.
    var text: String { textView.text }

    /// The empty-field prompt ("Ask about this episode" / "Ask a follow-up").
    var placeholder: String? {
        get { placeholderLabel.text }
        set { placeholderLabel.text = newValue }
    }

    /// Pre-fills the composer without sending.
    func setText(_ text: String) {
        textView.text = text
        textViewDidChange(textView)
    }

    func focus() {
        textView.becomeFirstResponder()
    }

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
        setScrolling(false)
        refreshSendState()
    }

    private var hasText: Bool {
        textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func submit() {
        guard hasText else { return }
        onSend?(textView.text)
    }

    private func setScrolling(_ scrolling: Bool) {
        textView.isScrollEnabled = scrolling
        fieldScrollHeight?.isActive = scrolling
    }

    private func refreshSendState() {
        let canSend = hasText && !isSending
        let changed = sendButton.isEnabled != canSend
        sendButton.isEnabled = canSend
        placeholderLabel.isHidden = !textView.text.isEmpty
        guard changed else { return }
        guard window != nil else {
            applySendVisibility(canSend)
            return
        }
        UIView.animate(withDuration: Motion.quick) {
            self.applySendVisibility(canSend)
        }
    }

    /// Fade/scale only: the button's slot is always reserved, so showing it
    /// never moves layout.
    private func applySendVisibility(_ visible: Bool) {
        sendButton.alpha = visible ? 1 : 0
        let scale = visible ? 1 : Metrics.hiddenSendScale
        sendButton.transform = CGAffineTransform(scaleX: scale, y: scale)
    }
}

extension ChatInputBar: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        let limit = fieldHeightLimit?.constant ?? .greatestFiniteMagnitude
        // sizeThatFits, not contentSize: the latter is stale right after a
        // programmatic text change (draft pre-fill) until the next layout.
        let width = textView.bounds.width
        let needed = width > 0
            ? textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            : textView.contentSize.height
        setScrolling(needed > limit)
        refreshSendState()
    }
}
