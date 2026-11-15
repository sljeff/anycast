import UIKit
import Kingfisher
import AnycastKit

/// Async dominant-color extraction for cover art (03 §5.4): Kingfisher
/// loads the image bytes, AnycastKit's `Palette.dominantColor` (the exact
/// palette_generator quantizer port, G_palette) computes the color, and
/// results are memoized per URL in an NSCache (07 §2.3: the Dart version
/// re-decoded and re-computed on every open/episode change — same result,
/// faster here). Falls back to 0xFF111316 when anything fails.
@MainActor
final class PaletteService {

    static let shared = PaletteService()

    /// RGB-packed like the Dart palette API (0xRRGGBB). Nonisolated so the
    /// off-main extraction path can read it.
    nonisolated static let fallbackRGB: UInt32 = 0x11_13_16

    private var colorCache: [String: UInt32] = [:]
    private var inFlight: [String: Task<UInt32, Never>] = [:]

    /// Cached value without loading (instant UI paths); nil on miss.
    func cachedDominantColor(for urlString: String) -> UIColor? {
        colorCache[urlString].map { Self.rgbColor($0) }
    }

    /// Loads (network or Kingfisher disk cache) and computes. Always
    /// resolves — failures yield the 0xFF111316 fallback, never throw.
    func dominantColor(from urlString: String) async -> UIColor {
        Self.rgbColor(await dominantRGB(from: urlString))
    }

    func dominantRGB(from urlString: String) async -> UInt32 {
        if let cached = colorCache[urlString] {
            return cached
        }
        if let task = inFlight[urlString] {
            return await task.value
        }
        let task = Task<UInt32, Never>(priority: .userInitiated) { [weak self] in
            let rgb = await Self.extractRGB(urlString: urlString)
            self?.store(rgb: rgb, urlString: urlString)
            return rgb
        }
        inFlight[urlString] = task
        let value = await task.value
        inFlight[urlString] = nil
        return value
    }

    private func store(rgb: UInt32, urlString: String) {
        colorCache[urlString] = rgb
        if colorCache.count > 256 {
            // Pure display cache — no eviction order tracked, drop wholesale.
            colorCache.removeAll(keepingCapacity: true)
        }
    }

    /// Kingfisher fetch + quantizer, off the main actor. The fetched image is
    /// downsampled first, then re-encoded losslessly (PNG) so the quantizer
    /// sees raw pixel data — palette_generator operated on decoded pixels,
    /// not the original file. The quantizer histograms every pixel, so the
    /// full-resolution encode/decode only added cost: a 256pt thumbnail
    /// carries the same color distribution and the extraction is unaffected.
    nonisolated private static func extractRGB(urlString: String) async -> UInt32 {
        guard let url = URL(string: urlString) else { return fallbackRGB }
        do {
            let result = try await KingfisherManager.shared.retrieveImage(with: .network(url))
            guard let data = downsample(result.image).kf.data(format: .PNG, compressionQuality: 1.0),
                  let rgb = Palette.dominantColor(imageData: data)
            else { return fallbackRGB }
            return rgb
        } catch {
            return fallbackRGB
        }
    }

    /// Caps the longest side at 256 px (UIGraphicsImageRenderer is safe off
    /// the main thread, unlike the legacy context APIs).
    nonisolated private static func downsample(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 256
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: (size.width * scale).rounded(.down), height: (size.height * scale).rounded(.down))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    nonisolated private static func rgbColor(_ rgb: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
