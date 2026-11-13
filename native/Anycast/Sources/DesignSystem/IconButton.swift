import UIKit

/// The single circular icon button (Anycast 2.0 UI kit `AnycastIconButton`):
/// fixed diameter, continuous capsule, shared press feedback.
///
/// - glass: floating chrome over content (Liquid Glass on iOS 26, a
///   shadowed surface disc on iOS 18).
/// - tonal: on-page secondary actions (sandAlpha4 disc).
/// - inverse: the emphasized action in a row (onSurface disc).
/// - plain: bare glyph (player transport, inline affordances).
///
/// Glyph point size and diameter track Dynamic Type from their design
/// sizes (TypographyV2 metrics, floor 44). The design size is what you
/// see at the default content size. Icon-only buttons show a Large
/// Content Viewer titled with the accessibility label.
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

    private let style: Style
    private let designDiameter: CGFloat
    private let designGlyphSize: CGFloat
    private let glyphWeight: UIImage.SymbolWeight
    private let metricsStyle: TypographyV2.Style
    private var baseImage: UIImage?
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    init(
        style: Style,
        icon: UIImage?,
        accessibilityLabel: String?,
        diameter: CGFloat = AnycastIconButton.standardDiameter,
        glyphSize: CGFloat = 17,
        glyphWeight: UIImage.SymbolWeight = .medium,
        metrics: TypographyV2.Style = TypographyV2.body
    ) {
        self.style = style
        self.designDiameter = diameter
        self.designGlyphSize = glyphSize
        self.glyphWeight = glyphWeight
        self.metricsStyle = metrics
        self.baseImage = icon
        super.init(frame: .zero)
        var configuration = Self.baseConfiguration(style)
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
        let width = widthAnchor.constraint(equalToConstant: diameter)
        let height = heightAnchor.constraint(equalToConstant: diameter)
        widthConstraint = width
        heightConstraint = height
        NSLayoutConstraint.activate([width, height])
        // The measured login Close disc sat inside a 44 pt control that a
        // parent could still squeeze. The bounds are the hit target.
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        applyMetrics()
        enableIconLargeContentViewer(image: icon)
        addPressFeedback()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (button: AnycastIconButton, _) in
            button.applyMetrics()
        }
    }

    /// Set by the detail sheet so ••• matches Play instead of the shared
    /// Dynamic Type diameter. `applyMetrics` keeps this size.
    private var explicitDiameter: CGFloat?
    private var explicitGlyphPointSize: CGFloat?

    /// Resizes the circle. The detail sheet uses this so ••• matches Play
    /// as the capsule grows, and stays a circle of that height.
    func setDiameter(_ diameter: CGFloat, glyphPointSize: CGFloat) {
        explicitDiameter = diameter
        explicitGlyphPointSize = glyphPointSize
        applyMetrics()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var accessibilityLabel: String? {
        didSet { largeContentTitle = accessibilityLabel }
    }

    func setIcon(_ icon: UIImage?) {
        baseImage = icon
        applyMetrics()
    }

    private func applyMetrics() {
        let glyph = explicitGlyphPointSize ?? IconMetrics.scaledUp(
            designGlyphSize,
            style: metricsStyle,
            compatibleWith: traitCollection
        )
        let symbol = UIImage.SymbolConfiguration(pointSize: glyph, weight: glyphWeight)
        let image = baseImage?
            .withIconMetrics(pointSize: glyph, weight: glyphWeight, compatibleWith: traitCollection)
            .withRenderingMode(.alwaysTemplate)
        if var configuration = configuration {
            configuration.preferredSymbolConfigurationForImage = symbol
            configuration.image = image
            self.configuration = configuration
        }
        let side = explicitDiameter ?? IconMetrics.diameter(
            designDiameter,
            style: metricsStyle,
            compatibleWith: traitCollection
        )
        widthConstraint?.constant = side
        heightConstraint?.constant = side
        largeContentImage = image
        largeContentTitle = accessibilityLabel
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
