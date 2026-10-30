import UIKit

extension UITextField {
    /// The single Anycast 2.0 input style (search fields, URL and email
    /// forms): surfaceContainer fill, md radius, outlineVariant hairline
    /// that turns primary while editing, body text, an optional
    /// leading glyph (otherwise a 16 pt inset). Height stays with the
    /// caller (48 pt standard).
    @MainActor
    func applyAnycastStyle(placeholder: String, icon: UIImage? = nil) {
        borderStyle = .none
        font = TypographyV2.body.font()
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

        // iOS 26+ sizes leftView/rightView with Auto Layout, so frame-only
        // widths collapse: every accessory carries explicit constraints
        // (frames stay for iOS 18).
        if let icon {
            let diameter = AnycastIconButton.standardDiameter
            let container = UIView(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
            let iconView = UIImageView(image: icon)
            iconView.tintColor = Theme.onSurfaceVariant
            iconView.contentMode = .center
            iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
            iconView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(iconView)
            NSLayoutConstraint.activate([
                container.widthAnchor.constraint(equalToConstant: diameter),
                container.heightAnchor.constraint(equalToConstant: diameter),
                iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            leftView = container
        } else {
            leftView = Self.makeSpacer()
        }
        leftViewMode = .always
        if clearButtonMode == .never {
            rightView = Self.makeSpacer()
            rightViewMode = .always
        }

        updateAnycastBorder()
        addAction(UIAction { [weak self] _ in self?.updateAnycastBorder() }, for: .editingDidBegin)
        addAction(UIAction { [weak self] _ in self?.updateAnycastBorder() }, for: .editingDidEnd)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (field: UITextField, _) in
            field.updateAnycastBorder()
        }
    }

    /// A `Spacing.pageH`-wide inset view for the no-icon left and the right accessory.
    @MainActor
    private static func makeSpacer() -> UIView {
        let spacer = UIView(frame: CGRect(x: 0, y: 0, width: Spacing.pageH, height: 1))
        spacer.widthAnchor.constraint(equalToConstant: Spacing.pageH).isActive = true
        return spacer
    }

    /// The hairline is a CGColor (frozen at assignment, 09 §9a).
    @MainActor
    private func updateAnycastBorder() {
        let color = isEditing ? Theme.primary : Theme.outlineVariant
        layer.borderColor = color.resolvedColor(with: traitCollection).cgColor
    }
}
