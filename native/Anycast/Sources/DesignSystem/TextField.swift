import UIKit

extension UITextField {
    /// The single Anycast 2.0 input style (search fields, URL and email
    /// forms): surfaceContainer fill, md radius, outlineVariant hairline
    /// that turns primary while editing, bodyLarge text, an optional
    /// leading glyph (otherwise a 16 pt inset). Height stays with the
    /// caller (48 pt standard).
    @MainActor
    func applyAnycastStyle(placeholder: String, icon: UIImage? = nil) {
        borderStyle = .none
        font = TypographyV2.bodyLarge.font()
        adjustsFontForContentSizeCategory = true
        textColor = Theme.onSurface
        tintColor = Theme.primary
        self.placeholder = placeholder
        attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: Theme.onSurfaceVariant]
        )
        backgroundColor = Theme.surfaceContainer
        layer.cornerRadius = Radius.md
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5

        if let icon {
            let iconView = UIImageView(image: icon)
            iconView.tintColor = Theme.onSurfaceVariant
            iconView.contentMode = .center
            iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)

            // Wrap the glyph in a frame-laid-out container with controlled
            // spacers: ~14 pt of visual gap on each side of the glyph. A
            // bare leftView leaves the inset from the field border and the
            // gap to the text to whatever the centered glyph happens to
            // spare inside its box. The 28 pt box is a close fit for the
            // body-size symbol (center content mode never clips — the
            // glyph draws at its natural size even if Dynamic Type grows
            // it past the box).
            let inset: CGFloat = 12
            let box: CGFloat = 28
            let container = UIView(frame: CGRect(x: 0, y: 0, width: inset + box + inset, height: box))
            iconView.frame = CGRect(x: inset, y: 0, width: box, height: box)
            container.addSubview(iconView)
            leftView = container
        } else {
            leftView = UIView(frame: CGRect(x: 0, y: 0, width: Spacing.pageH, height: 1))
        }
        leftViewMode = .always
        if clearButtonMode == .never {
            rightView = UIView(frame: CGRect(x: 0, y: 0, width: Spacing.pageH, height: 1))
            rightViewMode = .always
        }

        updateAnycastBorder()
        addAction(UIAction { [weak self] _ in self?.updateAnycastBorder() }, for: .editingDidBegin)
        addAction(UIAction { [weak self] _ in self?.updateAnycastBorder() }, for: .editingDidEnd)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (field: UITextField, _) in
            field.updateAnycastBorder()
        }
    }

    /// The hairline is a CGColor (frozen at assignment, 09 §9a).
    @MainActor
    private func updateAnycastBorder() {
        let color = isEditing ? Theme.primary : Theme.outlineVariant
        layer.borderColor = color.resolvedColor(with: traitCollection).cgColor
    }
}
