import UIKit

/// Anycast 2.0 button language (09 §5 Buttons Inventory): Primary is a solid
/// sand12 capsule (prominent glass tints its label to low contrast, so the
/// primary stays opaque), Secondary a clear glass capsule on iOS 26 and a
/// container-filled capsule on iOS 18.
@MainActor
enum AnycastButton {

    enum Kind {
        case primary
        case secondary
    }

    static func make(_ kind: Kind, title: String, image: UIImage? = nil) -> UIButton {
        var configuration = baseConfiguration(kind)
        configuration.title = title
        configuration.image = image
        configuration.imagePadding = Spacing.md
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .body)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: Spacing.gap, leading: Spacing.cardInner, bottom: Spacing.gap, trailing: Spacing.cardInner
        )
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.labelLarge.font()
            return outgoing
        }
        let button = UIButton(configuration: configuration)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        return button
    }

    private static func baseConfiguration(_ kind: Kind) -> UIButton.Configuration {
        if #available(iOS 26.0, *), kind == .secondary {
            var configuration = UIButton.Configuration.glass()
            configuration.baseForegroundColor = Theme.onSurface
            return configuration
        }
        switch kind {
        case .primary:
            var configuration = UIButton.Configuration.filled()
            configuration.baseBackgroundColor = Theme.onSurface
            configuration.baseForegroundColor = Theme.surface
            return configuration
        case .secondary:
            var configuration = UIButton.Configuration.filled()
            configuration.baseBackgroundColor = Theme.surfaceContainer
            configuration.baseForegroundColor = Theme.onSurface
            return configuration
        }
    }
}
