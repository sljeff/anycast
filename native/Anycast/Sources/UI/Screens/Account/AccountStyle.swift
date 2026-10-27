import UIKit

/// Shared look of the account surfaces (Settings identity row, Membership
/// page): the gold plate fill and fill-only press feedback.
@MainActor
enum AccountStyle {

    /// Gold plate fill: goldAlpha3 in light, goldAlpha2 in dark.
    static let goldPlate = UIColor { traits in
        let token = traits.userInterfaceStyle == .dark ? AnycastColor.goldAlpha2 : AnycastColor.goldAlpha3
        return token.resolvedColor(with: traits)
    }

    /// Row and plate padding on the gold plate.
    static let goldPadding: CGFloat = 24

    /// `sandAlpha5` laid over `base`, resolved per appearance — the pressed
    /// fill. Works for translucent bases (the gold plate) too.
    static func pressed(_ base: UIColor) -> UIColor {
        UIColor { traits in
            let overlay = AnycastColor.sandAlpha5.resolvedColor(with: traits)
            let under = base.resolvedColor(with: traits)
            var (or, og, ob, oa): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            var (ur, ug, ub, ua): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            guard overlay.getRed(&or, green: &og, blue: &ob, alpha: &oa),
                  under.getRed(&ur, green: &ug, blue: &ub, alpha: &ua) else { return overlay }
            let alpha = oa + ua * (1 - oa)
            guard alpha > 0 else { return .clear }
            return UIColor(
                red: (or * oa + ur * ua * (1 - oa)) / alpha,
                green: (og * oa + ug * ua * (1 - oa)) / alpha,
                blue: (ob * oa + ub * ua * (1 - oa)) / alpha,
                alpha: alpha
            )
        }
    }
}
