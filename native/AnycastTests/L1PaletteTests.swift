import Foundation
import Testing
@testable import AnycastKit

/// G_palette: dominant-color parity. Assertion is CIEDE2000 < 10 against the
/// palette_generator goldens (05 §3) — never exact equality, the quantizer
/// algorithms differ.
@Suite
struct L1PaletteTests {

    @Test("Dominant color stays within CIEDE2000 < 10 of golden")
    func paletteParity() throws {
        let data = try Data(contentsOf: RepoAssets.golden("G_palette_dominant.json"))
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let cases = object["cases"] as! [[String: Any]]

        #expect(!cases.isEmpty)
        var worst: Double = 0
        for expectedCase in cases {
            let file = expectedCase["file"] as! String
            let expectedInt = UInt32(truncatingIfNeeded: (expectedCase["dominantColor_int"] as! NSNumber).uint64Value)

            let imageData = try Data(contentsOf: RepoAssets.fixture("images/\(file)"))
            guard let dominant = Palette.dominantColor(imageData: imageData) else {
                Issue.record("\(file): no dominant color produced")
                continue
            }
            let delta = Palette.ciede2000(lhs: dominant, rhs: expectedInt)
            worst = max(worst, delta)
            if delta >= 10 {
                Issue.record("\(file): CIEDE2000 \(delta) ≥ 10 (got 0x\(String(dominant, radix: 16)), golden 0x\(String(expectedInt, radix: 16)))")
            }
        }
        print("palette worst CIEDE2000: \(worst)")
    }

    @Test("CIEDE2000 sanity: identical colors = 0, black/white ≈ 100")
    func ciedeSanity() {
        #expect(Palette.ciede2000(lhs: 0xFF336699, rhs: 0xFF336699) < 1e-9)
        #expect(Palette.ciede2000(lhs: 0xFF000000, rhs: 0xFFFFFFFF) > 50)
    }
}
