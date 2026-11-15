import Foundation
import CoreImage
import CoreGraphics

/// Exact port of palette_generator 0.3.3+5's quantizer (the algorithm the
/// shipped app used via `updatePaletteGenerator`, pinned by G_palette):
///
/// 1. Histogram pixels quantized to 5 bits/channel.
/// 2. Drop colors the default filter rejects (near-black, near-white, and
///    colors near the red "I line" — see `avoidRedBlackWhitePaletteFilter`).
/// 3. If more colors remain than the maximum (16), run the modified
///    median-cut: repeatedly split the largest-VOLUME color box at its
///    population median along the longest channel dimension.
/// 4. Each box contributes its population-weighted average color.
/// 5. `dominantColor` = the surviving color with the largest population.
///
/// Deterministic given the decoded pixels; box-range sorting uses Dart's own
/// unstable sort (`DartSort`) because the split-point scan depends on the
/// exact order of equal-key colors.
extension Palette {

    static let maximumColorCount = 16
    static let quantizeMask: UInt8 = 0xF8 // top 5 bits of each channel

    struct QuantizedColor: Hashable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
    }

    public static func dominantColor(imageData: Data) -> UInt32? {
        guard let source = CIImage(data: imageData) else { return nil }
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let width = Int(extent.width.rounded())
        let height = Int(extent.height.rounded())
        guard let bitmap = renderPixels(source, width: width, height: height) else {
            return nil
        }
        return quantizeDominant(pixelData: bitmap, width: width, height: height)
    }

    /// The quantizer over already-decoded RGBA8 pixels (full resolution —
    /// palette_generator histograms the decoded image as-is).
    static func quantizeDominant(pixelData: [UInt8], width: Int, height: Int) -> UInt32? {
        // 1. Histogram (insertion-ordered, like Dart's LinkedHashMap).
        var histogram: [QuantizedColor: Int] = [:]
        var order: [QuantizedColor] = []
        for index in 0..<(width * height) {
            let offset = index * 4
            guard pixelData[offset + 3] != 0 else { continue }
            let color = QuantizedColor(
                red: pixelData[offset] & quantizeMask,
                green: pixelData[offset + 1] & quantizeMask,
                blue: pixelData[offset + 2] & quantizeMask
            )
            if histogram[color] == nil {
                order.append(color)
                histogram[color] = 0
            }
            histogram[color]! += 1
        }
        guard !histogram.isEmpty else { return nil }

        // 2. Default filter: avoidRedBlackWhitePaletteFilter.
        let filtered = order.filter { !shouldIgnore($0) }
        guard !filtered.isEmpty else { return nil }
        var colors = filtered

        var palette: [(color: QuantizedColor, population: Int)] = []
        if colors.count <= maximumColorCount {
            palette = colors.map { ($0, histogram[$0]!) }
        } else {
            palette = quantize(colors: &colors, histogram: histogram)
        }
        guard !palette.isEmpty else { return nil }

        // 5. Dominant = largest population (Dart's descending sort).
        let sorted = DartSort.sorted(palette) { lhs, rhs in
            rhs.population - lhs.population
        }
        let dominant = sorted[0].color
        return 0xFF00_0000
            | (UInt32(dominant.red) << 16)
            | (UInt32(dominant.green) << 8)
            | UInt32(dominant.blue)
    }

    // MARK: - Volume-box quantization (median-cut by volume)

    private struct VolumeBox {
        var lowerIndex: Int
        var upperIndex: Int
        var minRed = 255, maxRed = 0
        var minGreen = 255, maxGreen = 0
        var minBlue = 255, maxBlue = 0
        var population = 0

        init(lowerIndex: Int, upperIndex: Int) {
            self.lowerIndex = lowerIndex
            self.upperIndex = upperIndex
        }

        var volume: Int {
            (maxRed - minRed + 1) * (maxGreen - minGreen + 1) * (maxBlue - minBlue + 1)
        }

        var canSplit: Bool { 1 + upperIndex - lowerIndex > 1 }

        mutating func fitMinimumBox(_ colors: [QuantizedColor], histogram: [QuantizedColor: Int]) {
            var minRed = 256, minGreen = 256, minBlue = 256
            var maxRed = -1, maxGreen = -1, maxBlue = -1
            var count = 0
            for index in lowerIndex...upperIndex {
                let color = colors[index]
                count += histogram[color]!
                minRed = min(minRed, Int(color.red)); maxRed = max(maxRed, Int(color.red))
                minGreen = min(minGreen, Int(color.green)); maxGreen = max(maxGreen, Int(color.green))
                minBlue = min(minBlue, Int(color.blue)); maxBlue = max(maxBlue, Int(color.blue))
            }
            self.minRed = minRed; self.maxRed = maxRed
            self.minGreen = minGreen; self.maxGreen = maxGreen
            self.minBlue = minBlue; self.maxBlue = maxBlue
            population = count
        }

        mutating func split(_ colors: inout [QuantizedColor], histogram: [QuantizedColor: Int]) -> VolumeBox {
            let splitPoint = findSplitPoint(&colors, histogram: histogram)
            var newBox = VolumeBox(lowerIndex: splitPoint + 1, upperIndex: upperIndex)
            newBox.fitMinimumBox(colors, histogram: histogram)
            upperIndex = splitPoint
            fitMinimumBox(colors, histogram: histogram)
            return newBox
        }

        private enum Component { case red, green, blue }

        private var longestDimension: Component {
            let redLength = maxRed - minRed
            let greenLength = maxGreen - minGreen
            let blueLength = maxBlue - minBlue
            if redLength >= greenLength && redLength >= blueLength { return .red }
            if greenLength >= redLength && greenLength >= blueLength { return .green }
            return .blue
        }

        private mutating func findSplitPoint(_ colors: inout [QuantizedColor], histogram: [QuantizedColor: Int]) -> Int {
            let dimension = longestDimension
            func composite(_ color: QuantizedColor) -> Int {
                switch dimension {
                case .red: return (Int(color.red) << 16) | (Int(color.green) << 8) | Int(color.blue)
                case .green: return (Int(color.green) << 16) | (Int(color.red) << 8) | Int(color.blue)
                case .blue: return (Int(color.blue) << 16) | (Int(color.green) << 8) | Int(color.red)
                }
            }
            var subset = Array(colors[lowerIndex...upperIndex])
            subset = DartSort.sorted(subset) { lhs, rhs in
                let lhsValue = composite(lhs)
                let rhsValue = composite(rhs)
                return lhsValue < rhsValue ? -1 : (lhsValue > rhsValue ? 1 : 0)
            }
            colors.replaceSubrange(lowerIndex...upperIndex, with: subset)

            // Dart: (population / 2).round() — half away from zero.
            let median = population % 2 == 0
                ? population / 2
                : (population + 1) / 2
            var count = 0
            for (offset, color) in subset.enumerated() {
                count += histogram[color]!
                if count >= median {
                    return min(upperIndex - 1, offset + lowerIndex)
                }
            }
            return lowerIndex
        }

        func averageColor(_ colors: [QuantizedColor], histogram: [QuantizedColor: Int])
            -> (color: QuantizedColor, population: Int)? {
            var redSum = 0, greenSum = 0, blueSum = 0
            var total = 0
            for index in lowerIndex...upperIndex {
                let color = colors[index]
                let population = histogram[color]!
                total += population
                redSum += population * Int(color.red)
                greenSum += population * Int(color.green)
                blueSum += population * Int(color.blue)
            }
            guard total > 0 else { return nil }
            func roundHalfAway(_ value: Int, _ divisor: Int) -> UInt8 {
                let quotient = Double(value) / Double(divisor)
                let rounded = quotient < 0
                    ? (quotient - 0.5).rounded(.up)
                    : (quotient + 0.5).rounded(.down)
                return UInt8(max(0, min(255, rounded)))
            }
            let average = QuantizedColor(
                red: roundHalfAway(redSum, total),
                green: roundHalfAway(greenSum, total),
                blue: roundHalfAway(blueSum, total)
            )
            return (average, total)
        }
    }

    private static func quantize(
        colors: inout [QuantizedColor],
        histogram: [QuantizedColor: Int]
    ) -> [(color: QuantizedColor, population: Int)] {
        var queue: [VolumeBox] = []
        var root = VolumeBox(lowerIndex: 0, upperIndex: colors.count - 1)
        root.fitMinimumBox(colors, histogram: histogram)
        queue.append(root)

        while queue.count < maximumColorCount {
            // Largest volume first (ties: lowest array position, mirroring a
            // max-heap's deterministic scan).
            var bestIndex = 0
            for index in queue.indices where queue[index].volume > queue[bestIndex].volume {
                bestIndex = index
            }
            guard queue[bestIndex].canSplit else { break }
            let newBox = queue[bestIndex].split(&colors, histogram: histogram)
            queue.append(newBox)
        }

        var results: [(color: QuantizedColor, population: Int)] = []
        for box in queue {
            if let average = box.averageColor(colors, histogram: histogram),
               !shouldIgnore(average.color) {
                results.append(average)
            }
        }
        return results
    }

    // MARK: - Default filter (avoidRedBlackWhitePaletteFilter)

    static func shouldIgnore(_ color: QuantizedColor) -> Bool {
        // HSL from sRGB (0…1).
        let red = Double(color.red) / 255
        let green = Double(color.green) / 255
        let blue = Double(color.blue) / 255
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let lightness = (maximum + minimum) / 2
        if lightness <= 0.05 { return true }   // isBlack
        if lightness >= 0.95 { return true }   // isWhite

        // Near the red I line: hue 10°…37° with low saturation.
        let delta = maximum - minimum
        let saturation: Double
        if delta == 0 {
            return false
        } else if lightness <= 0.5 {
            saturation = delta / (maximum + minimum)
        } else {
            saturation = delta / (2 - maximum - minimum)
        }
        var hue: Double
        if maximum == red {
            hue = (green - blue) / delta
        } else if maximum == green {
            hue = 2 + (blue - red) / delta
        } else {
            hue = 4 + (red - green) / delta
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        if hue >= 10 && hue <= 37 && saturation <= 0.82 {
            return true
        }
        return false
    }

    // MARK: - Pixel decode

    private static func renderPixels(_ image: CIImage, width: Int, height: Int) -> [UInt8]? {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &buffer,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        return buffer
    }
}
