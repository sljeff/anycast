import UIKit

/// ExpandableText (lib/widgets/expandable_text.dart): renders up to
/// `maxLines` (default 2); when the text is truncated the whole block becomes
/// a tappable surface (warm translucent background, 8pt radius, blank-line
/// collapse) that presents the full text in an alert (A6 adaptation: the Dart
/// Get.dialog AlertDialog maps to UIAlertController) with a close action.
final class ExpandableText: UIView {

    var maxLines: Int {
        didSet { label.numberOfLines = maxLines; refresh() }
    }

    var text: String {
        didSet { refresh() }
    }

    var style: Typography.Style {
        didSet { refresh() }
    }

    /// Overrides alert presentation (tests / special containers).
    var presentFullText: ((String, UIViewController?) -> Void)?

    private let label = UILabel()

    init(text: String, style: Typography.Style = .defaultText, maxLines: Int = 2) {
        self.text = text
        self.style = style
        self.maxLines = maxLines
        super.init(frame: .zero)

        label.numberOfLines = maxLines
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        // 8pt padding inside the truncated surface (Dart EdgeInsets.all(8)).
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            label.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])
        layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// True when the text does not fit `maxLines` at the current width —
    /// the Dart `tp.didExceedMaxLines` equivalent, measured with the real
    /// UILabel stack (exact rendering parity, no line-height arithmetic).
    var isTruncated: Bool {
        guard bounds.width > 0 else { return false }
        let width = bounds.width - layoutMargins.left - layoutMargins.right
        label.numberOfLines = 0
        let full = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        label.numberOfLines = maxLines
        let limited = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return full.height > limited.height + 0.5
    }

    override var intrinsicContentSize: CGSize {
        label.intrinsicContentSize
    }

    /// Width changes can flip truncation on or off.
    override func layoutSubviews() {
        super.layoutSubviews()
        refresh()
    }

    /// Internal (not private) so the truncation tests can drive it directly.
    @objc func handleTap() {
        guard isTruncated else { return }   // non-truncated text is not tappable
        if let presentFullText {
            presentFullText(text, parentViewController)
            return
        }
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .default))
        parentViewController?.present(alert, animated: true)
    }

    private func refresh() {
        label.font = style.font()
        label.textColor = style.color

        if isTruncated {
            // Dart truncated surface: goldAlpha3 dark — warm translucent.
            backgroundColor = UIColor(red: 248 / 255, green: 236 / 255, blue: 187 / 255, alpha: 0.14)
            layer.cornerRadius = 8
            layer.cornerCurve = .continuous
            // Collapse blank lines in the truncated copy only (Dart
            // replaceAll('\n\n', '\n')).
            label.text = text.replacingOccurrences(of: "\n\n", with: "\n")
            isAccessibilityElement = true
            accessibilityTraits = [.button]
            accessibilityLabel = "Show full text"
        } else {
            backgroundColor = .clear
            layer.cornerRadius = 0
            label.text = text
            isAccessibilityElement = false
        }
        invalidateIntrinsicContentSize()
    }

    private var parentViewController: UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}
