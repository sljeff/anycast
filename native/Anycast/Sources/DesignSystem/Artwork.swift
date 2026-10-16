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

extension UIImageView {
    /// Loads a cover with the shared placeholder shown while loading and on
    /// failure (no spinners or generic glyphs).
    @MainActor
    func setArtwork(_ url: URL?, title: String?) {
        let placeholder = ArtworkPlaceholder.image(for: title)
        kf.setImage(
            with: url,
            placeholder: placeholder,
            options: [.transition(.none), .onFailureImage(placeholder)]
        )
    }
}
