import UIKit
import Testing
@testable import Anycast

/// ScrollEdgeFade (G-7): a non-interactive scrim whose gradient spans
/// exactly `fadeLength` at its inner edge and is solid beyond it.
@MainActor
struct ScrollEdgeFadeTests {

    private func gradient(of fade: ScrollEdgeFade, height: CGFloat) -> CAGradientLayer? {
        fade.frame = CGRect(x: 0, y: 0, width: 200, height: height)
        fade.layoutIfNeeded()
        return fade.layer.sublayers?.first as? CAGradientLayer
    }

    private func alpha(_ color: Any?) -> CGFloat? {
        guard let color else { return nil }
        // swiftlint:disable:next force_cast
        return (color as! CGColor).alpha
    }

    @Test("never intercepts touches")
    func notInteractive() {
        #expect(ScrollEdgeFade(edge: .top).isUserInteractionEnabled == false)
        #expect(ScrollEdgeFade(edge: .bottom).isUserInteractionEnabled == false)
    }

    @Test("top edge at fadeLength height is a pure opaque-to-clear gradient")
    func topPureGradient() throws {
        let fade = ScrollEdgeFade(edge: .top)
        let layer = try #require(gradient(of: fade, height: ScrollEdgeFade.fadeLength))
        let colors = try #require(layer.colors)
        #expect(alpha(colors.first) == 1)
        #expect(alpha(colors.last) == 0)
        #expect(layer.locations?.first?.doubleValue == 0)
    }

    @Test("bottom edge ramps over fadeLength then stays opaque")
    func bottomRamp() throws {
        let fade = ScrollEdgeFade(edge: .bottom)
        let layer = try #require(gradient(of: fade, height: 100))
        let colors = try #require(layer.colors)
        #expect(alpha(colors.first) == 0)
        #expect(alpha(colors.last) == 1)
        let opaqueAt = try #require(layer.locations?.last?.doubleValue)
        #expect(abs(opaqueAt - Double(ScrollEdgeFade.fadeLength) / 100) < 0.01)
    }
}
