import CoreGraphics
import Foundation

/// Pure geometry helpers for sizing show-notes images. No UIKit — CoreGraphics
/// types only, so this is usable from any actor or nonisolated context.
public enum ImageFit {

    /// Fit-width scaling for a single image.
    ///
    /// - Intrinsic size drives the aspect ratio; the result fills
    ///   `availableWidth` unless a constraint below applies.
    /// - Intrinsic width OR height of 2 px or less is a tracking pixel /
    ///   spacer: returns `.zero` so the caller can collapse the attachment.
    /// - Small icons (intrinsic width strictly below `minimumContentWidth`)
    ///   are returned at their intrinsic size — never upscaled, never the
    ///   placeholder — but still subject to `maxHeight`.
    /// - When the fitted height would exceed `maxHeight`, the image is
    ///   re-scaled by height instead (width shrinks proportionally).
    /// - Invalid inputs (non-positive intrinsic width/height, availableWidth,
    ///   or maxHeight) return a 16:9 placeholder of
    ///   `(availableWidth, availableWidth * 9 / 16)`. A negative
    ///   `minimumContentWidth` is clamped to 0 (icon protection disabled)
    ///   rather than treated as invalid, because it is a threshold, not a
    ///   dimension.
    public static func size(
        intrinsic: CGSize,
        availableWidth: CGFloat,
        maxHeight: CGFloat = .greatestFiniteMagnitude,
        minimumContentWidth: CGFloat = 32
    ) -> CGSize {
        if intrinsic.width <= 0 || intrinsic.height <= 0 || availableWidth <= 0 || maxHeight <= 0 {
            return CGSize(width: availableWidth, height: availableWidth * 9 / 16)
        }
        // Tracking pixels and 1 px spacer strips: collapse, don't render.
        if intrinsic.width <= 2 || intrinsic.height <= 2 {
            return .zero
        }
        let minimum = max(0, minimumContentWidth)
        if intrinsic.width < minimum {
            let iconHeight = min(intrinsic.height, maxHeight)
            return CGSize(width: intrinsic.width * (iconHeight / intrinsic.height), height: iconHeight)
        }
        let width = availableWidth
        let height = intrinsic.height * (width / intrinsic.width)
        if height > maxHeight {
            let scaled = width * (maxHeight / height)
            return CGSize(width: scaled, height: maxHeight)
        }
        return CGSize(width: width, height: height)
    }

    /// Centered aspect-fit rectangle: the largest rect with the image's aspect
    /// ratio that fits inside `bounds`, centered. Returns `.zero` for
    /// non-positive image or bounds dimensions.
    public static func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }
}
