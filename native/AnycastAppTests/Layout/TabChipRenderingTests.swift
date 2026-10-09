import UIKit
import Testing
@testable import Anycast

/// Rendering-level regression tests for the pill tab bar's chip geometry.
///
/// Pins the selected chip silhouette and adaptive glass backing.
@MainActor
struct TabChipRenderingTests {

    private func makeBar() -> BottomTabBarView {
        let bar = BottomTabBarView(items: [
            .init(title: "Podcast", icon: AppIcons.inbox),
            .init(title: "Playlist", icon: AppIcons.playlist),
            .init(title: "Discover", icon: AppIcons.discover),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 440, height: 160)
        bar.layoutIfNeeded()
        return bar
    }

    /// Renders a view offscreen at 1x into RGBA bytes.
    private func rgbaBytes(of view: UIView) -> (pixels: [UInt8], width: Int, height: Int)? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: CGRect(origin: .zero, size: size), format: format)
        let image = renderer.image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (pixels, width, height)
    }

    /// RGBA at a point in top-left coordinates.
    private func pixel(
        _ x: Int, _ y: Int, _ pixels: [UInt8], _ width: Int, _ height: Int
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let idx = ((height - 1 - y) * width + x) * 4
        guard idx + 3 < pixels.count else { return (0, 0, 0, 0) }
        return (pixels[idx], pixels[idx + 1], pixels[idx + 2], pixels[idx + 3])
    }

    @Test("Chip capsule geometry: opaque fill rounds the corners")
    func chipHighlightIsCapsule() throws {
        let bar = makeBar()
        guard let button = bar.pillButtons.first,
              let chip = button.superview else {
            Issue.record("chip hierarchy not found")
            return
        }
        #expect(abs(chip.layer.cornerRadius - 32) < 0.5, "layer radius \(chip.layer.cornerRadius)")
        #expect(abs(chip.bounds.height - 64) < 0.5, "chip height \(chip.bounds.height)")

        // Inject an OPAQUE fill so the silhouette is measurable.
        let original = chip.backgroundColor
        chip.backgroundColor = .systemRed
        defer { chip.backgroundColor = original }
        chip.layer.borderColor = nil
        chip.layer.borderWidth = 0

        guard let (pixels, width, height) = rgbaBytes(of: chip) else {
            Issue.record("chip render failed")
            return
        }
        // Corner must be empty (capsule), center must be the opaque fill.
        let corner = pixel(2, 2, pixels, width, height)
        let center = pixel(width / 2, height / 2, pixels, width, height)
        #expect(corner.a < 20, "chip corner alpha \(corner.a) — fill reaches the corner (rectangle)")
        #expect(center.a > 200, "chip center alpha \(center.a) — opaque fill missing")

        // Quarter-height rows are narrower than the mid row (curvature).
        let rowWidth: (Int) -> Int = { y in
            var count = 0
            for x in 0..<width where pixel(x, y, pixels, width, height).a > 100 { count += 1 }
            return count
        }
        let mid = rowWidth(height / 2)
        let nearTop = rowWidth(6)
        print("[chipdiag] width=\(width) height=\(height) mid=\(mid) nearTop=\(nearTop)")
        #expect(nearTop < mid - 20, "near-top row width \(nearTop) vs mid \(mid) — no capsule curvature")
    }

    @Test("Button layer paints no rectangular surface behind the content")
    func buttonDrawsNoRectangle() throws {
        let bar = makeBar()
        guard let button = bar.pillButtons.first else { return }
        guard let (pixels, width, height) = rgbaBytes(of: button) else {
            Issue.record("button render failed")
            return
        }
        let corners = [
            pixel(2, 2, pixels, width, height),
            pixel(width - 3, 2, pixels, width, height),
            pixel(2, height - 3, pixels, width, height),
            pixel(width - 3, height - 3, pixels, width, height),
        ]
        for (i, c) in corners.enumerated() {
            #expect(c.a < 30, "button corner \(i) alpha \(c.a) — a surface is being painted")
        }
    }

    @Test("Pill uses the glass component with an iOS 18 material fallback")
    func pillGlassSurface() throws {
        let bar = makeBar()
        guard let chip = bar.pillButtons.first?.superview,
              let content = chip.superview,
              let pill = content.superview as? GlassContainerView else {
            Issue.record("pill not found")
            return
        }
        #expect(pill.subviews.contains { $0 is UIVisualEffectView })
        #expect(pill.layer.shadowOpacity == 0.08)
        #expect(Theme.background.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            != Theme.background.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
    }
}
