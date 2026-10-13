import UIKit

/// Symbol size and weight per role (Anycast 2.0 UI kit
/// `AnycastIcon.Semantic`). Screens pick a role instead of typing point
/// sizes, so a glyph means the same thing on every surface.
nonisolated struct IconStyle: Sendable {
    let pointSize: CGFloat
    let weight: UIImage.SymbolWeight

    var configuration: UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    }

    /// − / + inside a stepper capsule.
    static let stepperControl = IconStyle(pointSize: 16, weight: .light)
    /// Secondary actions in a button group (player pager, toolbars).
    static let groupAction = IconStyle(pointSize: 20, weight: .regular)
    /// Player skip back / forward.
    static let playerTransport = IconStyle(pointSize: 36, weight: .regular)
    /// Player play / pause.
    static let playerPrimary = IconStyle(pointSize: 56, weight: .regular)
}
