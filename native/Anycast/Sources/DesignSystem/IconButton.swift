import UIKit

/// The single circular icon button (Anycast 2.0 UI kit `AnycastIconButton`):
/// fixed diameter, continuous capsule, shared press feedback.
///
/// - glass: floating chrome over content (Liquid Glass on iOS 26, a
///   shadowed surface disc on iOS 18).
/// - tonal: on-page secondary actions (sandAlpha4 disc).
/// - inverse: the emphasized action in a row (onSurface disc).
/// - plain: bare glyph (player transport, inline affordances).
final class AnycastIconButton: UIButton {

    enum Style {
        case glass
        case tonal
        case inverse
        case plain
    }

    /// The HIG minimum hit target; the default size.
    static let standardDiameter: CGFloat = 44
    static let largeDiameter: CGFloat = 48

    init(
        style: Style,
        icon: UIImage?,
        accessibilityLabel: String?,
        diameter: CGFloat = AnycastIconButton.standardDiameter,
        glyphSize: CGFloat = 17
    ) {
        super.init(frame: .zero)
        var configuration = Self.baseConfiguration(style)
        configuration.image = icon?.withRenderingMode(.alwaysTemplate)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: glyphSize, weight: .medium)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        self.configuration = configuration
        if style == .glass, #unavailable(iOS 26.0) {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.08
            layer.shadowOffset = CGSize(width: 0, height: 2)
            layer.shadowRadius = 8
        }
        self.accessibilityLabel = accessibilityLabel
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
        ])
        addPressFeedback()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setIcon(_ icon: UIImage?) {
        configuration?.image = icon?.withRenderingMode(.alwaysTemplate)
    }

    private static func baseConfiguration(_ style: Style) -> UIButton.Configuration {
        switch style {
        case .glass:
            if #available(iOS 26.0, *) {
                var configuration = UIButton.Configuration.glass()
                configuration.baseForegroundColor = Theme.onSurface
                return configuration
            }
            var configuration = UIButton.Configuration.filled()
            configuration.baseBackgroundColor = Theme.surface
            configuration.baseForegroundColor = Theme.onSurface
            return configuration
        case .tonal:
            var configuration = UIButton.Configuration.filled()
            configuration.baseBackgroundColor = AnycastColor.sandAlpha4
            configuration.baseForegroundColor = Theme.onSurface
            return configuration
        case .inverse:
            var configuration = UIButton.Configuration.filled()
            configuration.baseBackgroundColor = Theme.onSurface
            configuration.baseForegroundColor = Theme.surface
            return configuration
        case .plain:
            var configuration = UIButton.Configuration.plain()
            configuration.baseForegroundColor = Theme.onSurface
            return configuration
        }
    }
}
