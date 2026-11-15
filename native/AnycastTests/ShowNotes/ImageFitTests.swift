import CoreGraphics
import Foundation
import Testing

@testable import AnycastKit

/// ImageFit pure-geometry fixtures. Dimensions were chosen so every ratio is
/// exactly representable in binary floating point (powers of two), keeping the
/// comparisons exact.
@Suite
struct ImageFitTests {

    // MARK: - size(intrinsic:availableWidth:…)

    @Test("Square image fills the width and keeps its aspect")
    func square() {
        let size = ImageFit.size(intrinsic: CGSize(width: 1024, height: 1024), availableWidth: 320)
        #expect(size == CGSize(width: 320, height: 320))
    }

    @Test("Wide image fills the width")
    func wide() {
        let size = ImageFit.size(intrinsic: CGSize(width: 1280, height: 640), availableWidth: 320)
        #expect(size == CGSize(width: 320, height: 160))
    }

    @Test("Tall image scales by width when no maxHeight applies")
    func tallUnconstrained() {
        let size = ImageFit.size(intrinsic: CGSize(width: 400, height: 1600), availableWidth: 300)
        #expect(size == CGSize(width: 300, height: 1200))
    }

    @Test("maxHeight re-scales the image by height")
    func maxHeightRescale() {
        let size = ImageFit.size(
            intrinsic: CGSize(width: 400, height: 1600),
            availableWidth: 300,
            maxHeight: 300
        )
        // Fitted height 1200 exceeds 300, so width shrinks: 300 * 300/1200.
        #expect(size == CGSize(width: 75, height: 300))
    }

    @Test("maxHeight above the fitted height is a no-op")
    func maxHeightNoOp() {
        let size = ImageFit.size(
            intrinsic: CGSize(width: 1280, height: 640),
            availableWidth: 320,
            maxHeight: 400
        )
        #expect(size == CGSize(width: 320, height: 160))
    }

    @Test("Zero intrinsic dimensions fall back to the 16:9 placeholder")
    func zeroIntrinsic() {
        let size = ImageFit.size(intrinsic: CGSize(width: 0, height: 100), availableWidth: 200)
        #expect(size == CGSize(width: 200, height: 112.5))
        let zeroHeight = ImageFit.size(intrinsic: CGSize(width: 100, height: 0), availableWidth: 200)
        #expect(zeroHeight == CGSize(width: 200, height: 112.5))
    }

    @Test("Negative inputs fall back to the 16:9 placeholder")
    func negativeValues() {
        let size = ImageFit.size(intrinsic: CGSize(width: -5, height: 100), availableWidth: 200)
        #expect(size == CGSize(width: 200, height: 112.5))
        let zeroWidth = ImageFit.size(intrinsic: CGSize(width: 100, height: 50), availableWidth: 0)
        #expect(zeroWidth == CGSize(width: 0, height: 0))
        let zeroMax = ImageFit.size(
            intrinsic: CGSize(width: 100, height: 50),
            availableWidth: 200,
            maxHeight: 0
        )
        #expect(zeroMax == CGSize(width: 200, height: 112.5))
    }

    @Test("Small icons (intrinsic width below minimumContentWidth) are not upscaled")
    func smallIconNotUpscaled() {
        let size = ImageFit.size(intrinsic: CGSize(width: 24, height: 24), availableWidth: 320)
        #expect(size == CGSize(width: 24, height: 24))
    }

    @Test("Width exactly at minimumContentWidth still fits the width")
    func iconAtThreshold() {
        let size = ImageFit.size(intrinsic: CGSize(width: 32, height: 16), availableWidth: 300)
        #expect(size == CGSize(width: 300, height: 150))
    }

    @Test("minimumContentWidth of 0 disables the icon rule")
    func iconRuleDisabled() {
        let size = ImageFit.size(
            intrinsic: CGSize(width: 16, height: 16),
            availableWidth: 100,
            minimumContentWidth: 0
        )
        #expect(size == CGSize(width: 100, height: 100))
    }

    // MARK: - aspectFitRect(imageSize:in:)

    @Test("aspectFitRect centers a landscape image vertically")
    func aspectFitLandscape() {
        let rect = ImageFit.aspectFitRect(
            imageSize: CGSize(width: 100, height: 50),
            in: CGRect(x: 0, y: 0, width: 200, height: 200)
        )
        #expect(rect == CGRect(x: 0, y: 50, width: 200, height: 100))
    }

    @Test("aspectFitRect centers a portrait image horizontally")
    func aspectFitPortrait() {
        let rect = ImageFit.aspectFitRect(
            imageSize: CGSize(width: 50, height: 100),
            in: CGRect(x: 0, y: 0, width: 200, height: 100)
        )
        #expect(rect == CGRect(x: 75, y: 0, width: 50, height: 100))
    }

    @Test("aspectFitRect returns the bounds when the aspect already matches")
    func aspectFitExact() {
        let rect = ImageFit.aspectFitRect(
            imageSize: CGSize(width: 200, height: 100),
            in: CGRect(x: 10, y: 20, width: 200, height: 100)
        )
        #expect(rect == CGRect(x: 10, y: 20, width: 200, height: 100))
    }

    @Test("aspectFitRect centers inside a non-origin bounds")
    func aspectFitNonOrigin() {
        let rect = ImageFit.aspectFitRect(
            imageSize: CGSize(width: 100, height: 100),
            in: CGRect(x: 100, y: 100, width: 300, height: 100)
        )
        #expect(rect == CGRect(x: 200, y: 100, width: 100, height: 100))
    }

    @Test("aspectFitRect returns zero for invalid dimensions")
    func aspectFitInvalid() {
        #expect(ImageFit.aspectFitRect(
            imageSize: CGSize(width: 0, height: 10),
            in: CGRect(x: 0, y: 0, width: 100, height: 100)
        ) == .zero)
        #expect(ImageFit.aspectFitRect(
            imageSize: CGSize(width: 10, height: 10),
            in: CGRect(x: 0, y: 0, width: 0, height: 100)
        ) == .zero)
    }
}


// MARK: - Collapse & clamp guards

@Test("Tracking pixels and 1px spacers collapse to zero")
func trackingPixelsCollapse() {
    #expect(ImageFit.size(intrinsic: CGSize(width: 1, height: 1), availableWidth: 320) == .zero)
    #expect(ImageFit.size(intrinsic: CGSize(width: 3, height: 2), availableWidth: 320) == .zero)
    #expect(ImageFit.size(intrinsic: CGSize(width: 2, height: 900), availableWidth: 320) == .zero)
}

@Test("Small icons are height-clamped too, not just fit-width images")
func iconsRespectMaxHeight() {
    let size = ImageFit.size(
        intrinsic: CGSize(width: 16, height: 900),
        availableWidth: 320,
        maxHeight: 200
    )
    #expect(size.height <= 200)
    #expect(abs(size.width / size.height - 16.0 / 900.0) < 0.001)
}
