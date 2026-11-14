import UIKit
import Kingfisher

/// The one missing-artwork treatment (Anycast 2.0 UI kit
/// `EpisodeArtworkView`): the show's initial on a sand tile, used while a
/// cover loads and when it fails. The image carries light and dark
/// renderings, so it follows the appearance like a dynamic color.
@MainActor
enum ArtworkPlaceholder {

    private static var cache: [String: UIImage] = [:]

    static func image(for title: String?) -> UIImage {
        let initial = title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first.map { String($0).localizedUppercase } ?? ""
        if let cached = cache[initial] { return cached }

        let asset = UIImageAsset()
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            asset.register(render(initial: initial, traits: traits), with: traits)
        }
        let image = asset.image(with: UITraitCollection.current)
        cache[initial] = image
        return image
    }

    private static func render(initial: String, traits: UITraitCollection) -> UIImage {
        let side: CGFloat = 120
        let format = UIGraphicsImageRendererFormat(for: traits)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            Theme.surfaceContainerHighest.resolvedColor(with: traits).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
            guard !initial.isEmpty else { return }
            let text = NSAttributedString(string: initial, attributes: [
                .font: ThemeRegistry.current.typography.font(side * 0.42, .semibold, .display),
                .foregroundColor: Theme.onSurfaceVariant.resolvedColor(with: traits).withAlphaComponent(0.55),
            ])
            let size = text.size()
            text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
        }
    }
}

/// How list covers are decoded and cached. Views never decode full-size art
/// for a 36 pt slot: every cover is downsampled to one of a few buckets, so
/// one cover costs at most three cache entries instead of one per view size.
/// Views and prefetchers build their options here, because the cache key
/// carries the processor: a mismatch makes a prefetch silently useless.
enum ArtworkSizing {

    /// Pixel-side buckets, in points: small rows (36 / 44 / 56 / 64), medium
    /// tiles (88 / 120 / 160) and everything larger (player, large headers).
    static let small: CGFloat = 64
    static let medium: CGFloat = 160
    static let large: CGFloat = 400

    static func bucket(for side: CGFloat) -> CGFloat {
        if side <= small { return small }
        if side <= medium { return medium }
        return large
    }

    /// The options that decide the cache key and the decode: shared by
    /// `setArtwork` and `ImagePrefetcher`.
    @MainActor
    static func processingOptions(side: CGFloat) -> KingfisherOptionsInfo {
        let bucketSide = bucket(for: side)
        return [
            .processor(DownsamplingImageProcessor(size: CGSize(width: bucketSide, height: bucketSide))),
            .scaleFactor(UIScreen.main.scale),
            .cacheOriginalImage,
            .loadDiskFileSynchronously,
        ]
    }
}

extension UIImageView {
    /// Loads a cover with the shared placeholder shown while loading and on
    /// failure (no spinners or generic glyphs). `side` is the view's point
    /// size (the largest it reaches); the image is decoded at its bucket.
    /// A memory hit is applied immediately, before Kingfisher can swap in
    /// the placeholder on a recycled cell. A network arrival crossfades in
    /// `Motion.quick`; Reduce Motion and cache hits do not animate.
    @MainActor
    func setArtwork(_ url: URL?, title: String?, side: CGFloat) {
        applyArtworkHairline()
        let placeholder = ArtworkPlaceholder.image(for: title)
        guard let url else {
            kf.cancelDownloadTask()
            image = placeholder
            return
        }
        let options = ArtworkSizing.processingOptions(side: side)
        if let memory = ImageCache.default.retrieveImageInMemoryCache(
            forKey: url.absoluteString, options: options
        ) {
            kf.cancelDownloadTask()
            image = memory
            return
        }
        let transition: ImageTransition = Motion.reduceMotion ? .none : .fade(Motion.quick)
        kf.setImage(
            with: url,
            placeholder: placeholder,
            options: options + [.transition(transition), .onFailureImage(placeholder)]
        )
    }

    /// The cover's 0.5 pt inner hairline (`sandAlpha4`). Content casts no
    /// shadow, so this is what keeps a pale cover from melting into its
    /// ground. The layer border draws over the image and follows the corner
    /// radius; it is set up once per view and re-resolved on appearance
    /// changes.
    @MainActor
    func applyArtworkHairline() {
        guard layer.borderWidth == 0 else { return }
        layer.borderWidth = 0.5
        layer.borderColor = AnycastColor.sandAlpha4.resolvedColor(with: traitCollection).cgColor
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UIImageView, _: UITraitCollection) in
            view.layer.borderColor = AnycastColor.sandAlpha4.resolvedColor(with: view.traitCollection).cgColor
        }
    }
}
