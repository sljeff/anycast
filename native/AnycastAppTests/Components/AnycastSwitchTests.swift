import UIKit
import Testing
@testable import Anycast

/// AnycastSwitch (DesignSystem/Switch.swift): the sand ON track and thumb,
/// the sandAlpha4 OFF track painted on the system's off-track view,
/// all dynamic against the switch's own traits.
@MainActor
struct AnycastSwitchTests {

    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    /// A trait environment needs a window: a detached view tree resolves
    /// no appearance or contrast overrides.
    private func hosted(_ toggle: AnycastSwitch) throws -> UIWindow {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(toggle)
        window.isHidden = false
        return window
    }

    @Test("ON track and thumb resolve to their tokens in light and dark")
    func onTrackAndThumb() throws {
        let toggle = AnycastSwitch()
        let onTint = try #require(toggle.onTintColor)
        let thumb = try #require(toggle.thumbTintColor)

        #expect(onTint.resolvedColor(with: light) == AnycastColor.sand12.resolvedColor(with: light))
        #expect(onTint.resolvedColor(with: dark) == AnycastColor.goldDark9.resolvedColor(with: dark))
        #expect(thumb.resolvedColor(with: light) == AnycastColor.sand1.resolvedColor(with: light))
        #expect(thumb.resolvedColor(with: dark) == AnycastColor.sandDark12.resolvedColor(with: dark))
    }

    @Test("OFF track is the stepper capsule fill in light and dark")
    func offTrack() throws {
        let toggle = AnycastSwitch()
        toggle.setOn(false, animated: false)
        toggle.layoutIfNeeded()
        let track = try #require(toggle.offTrackView, "system off-track view not found")
        let fill = try #require(track.backgroundColor)

        #expect(fill.resolvedColor(with: light) == AnycastColor.sandAlpha4.resolvedColor(with: light))
        #expect(fill.resolvedColor(with: dark) == AnycastColor.sandAlpha4.resolvedColor(with: dark))
        #expect(
            fill.resolvedColor(with: light) != fill.resolvedColor(with: dark),
            "the OFF fill must follow the appearance"
        )
    }

    @Test("The sand off track survives toggling on and off")
    func offTrackSurvivesToggle() throws {
        let toggle = AnycastSwitch()
        toggle.setOn(true, animated: false)
        toggle.layoutIfNeeded()
        toggle.setOn(false, animated: false)
        toggle.layoutIfNeeded()
        let fill = try #require(toggle.offTrackView?.backgroundColor)
        #expect(fill.resolvedColor(with: light) == AnycastColor.sandAlpha4.resolvedColor(with: light))
    }

    @Test("Increase Contrast adds a visible off-track edge; normal contrast has none")
    func highContrastEdge() throws {
        let toggle = AnycastSwitch()
        let window = try hosted(toggle)
        defer { window.isHidden = true }
        toggle.layoutIfNeeded()
        // UIKit may rebuild its internal views on a trait change, so the
        // track is looked up fresh each time.
        #expect(try #require(toggle.offTrackView).layer.borderWidth == 0)

        window.rootViewController?.traitOverrides.accessibilityContrast = .high
        window.layoutIfNeeded()
        toggle.layoutIfNeeded()
        let track = try #require(toggle.offTrackView)
        #expect(track.layer.borderWidth == 1)
        let edge = try #require(track.layer.borderColor.map(UIColor.init(cgColor:)))
        #expect(edge.cgColor.alpha > 0.3, "the edge must be a visible line")

        window.rootViewController?.traitOverrides.remove(UITraitAccessibilityContrast.self)
        window.layoutIfNeeded()
        toggle.layoutIfNeeded()
        #expect(try #require(toggle.offTrackView).layer.borderWidth == 0)
    }

    @Test("A forced-dark host resolves the dark pair without call-site code")
    func forcedDark() throws {
        let toggle = AnycastSwitch()
        let window = try hosted(toggle)
        defer { window.isHidden = true }
        window.rootViewController?.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        #expect(toggle.traitCollection.userInterfaceStyle == .dark)
        let onTint = try #require(toggle.onTintColor)
        #expect(
            onTint.resolvedColor(with: toggle.traitCollection)
                == AnycastColor.goldDark9.resolvedColor(with: dark)
        )
    }
}
