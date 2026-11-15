import UIKit
import Kingfisher

/// Opaque handle for one in-flight show-notes image load. `cancel` is
/// idempotent and safe from any isolation domain; cancelling after the
/// completion has already been delivered is a no-op.
nonisolated final class ShowNotesImageLoadToken: Sendable {

    let cancel: @Sendable () -> Void

    init(cancel: @escaping @Sendable () -> Void) {
        self.cancel = cancel
    }
}

/// Decouples show-notes attachments from Kingfisher so the text view and
/// its tests can drive the same pipeline. Implementations deliver a loaded
/// image on success and nil on failure; the completion may fire on any
/// executor, so receivers must hop to the main actor before touching UIKit
/// state.
nonisolated protocol ShowNotesImageLoading: Sendable {

    func load(
        url: URL,
        targetSize: CGSize,
        completion: @escaping @Sendable (UIImage?) -> Void
    ) -> ShowNotesImageLoadToken
}

/// Kingfisher-backed production loader. The requested `targetSize` is
/// bucketed to 64 px multiples before building the processor: the processor
/// identifier is part of the processed-image cache key, and bucketing keeps
/// that key stable across small width changes (Dynamic Type, rotation)
/// instead of caching one bitmap per pixel of column width. The original
/// bytes are cached alongside the downsampled variant so the fullscreen
/// viewer can hit the same disk entry.
nonisolated final class KingfisherShowNotesImageLoader: ShowNotesImageLoading {

    static let shared = KingfisherShowNotesImageLoader()

    private static let bucketSize: CGFloat = 64

    func load(
        url: URL,
        targetSize: CGSize,
        completion: @escaping @Sendable (UIImage?) -> Void
    ) -> ShowNotesImageLoadToken {
        let target = Self.bucketed(targetSize)
        let task = KingfisherManager.shared.retrieveImage(
            with: .network(url),
            options: [
                .processor(DownsamplingImageProcessor(size: target)),
                .cacheOriginalImage,
                .transition(.none),
                // Kingfisher defaults to scale 1; without the screen scale
                // every inline image decodes at 1x and looks soft on 2x/3x
                // displays (the processor sizes by points * scale).
                .scaleFactor(UIScreen.main.scale),
            ],
            completionHandler: { result in
                switch result {
                case let .success(retrieved): completion(retrieved.image)
                case .failure: completion(nil)
                }
            }
        )
        return ShowNotesImageLoadToken { task?.cancel() }
    }

    /// Rounds each dimension up to the next 64 px bucket (minimum 64) so
    /// the downsample target always covers the requested display size.
    private static func bucketed(_ size: CGSize) -> CGSize {
        func bucket(_ value: CGFloat) -> CGFloat {
            guard value > 0 else { return bucketSize }
            return ceil(value / bucketSize) * bucketSize
        }
        return CGSize(width: bucket(size.width), height: bucket(size.height))
    }
}
