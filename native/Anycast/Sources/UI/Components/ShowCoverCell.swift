import UIKit
import Kingfisher

/// A subscription in the Shows sheet's cover grid (Anycast 2.0 UI kit
/// `ShowCoverCell`): the square artwork (card radius, show-initial
/// placeholder) over the one-line show name.
final class ShowCoverCell: UICollectionViewCell {

    static let reuseIdentifier = "ShowCoverCell"

    var onTap: (() -> Void)?

    private let coverView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = Radius.md
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.surfaceContainerHigh

        titleLabel.font = TypographyV2.meta.font()
        titleLabel.textColor = Theme.onSurfaceVariant
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [coverView, titleLabel])
        stack.axis = .vertical
        stack.spacing = Spacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            coverView.heightAnchor.constraint(equalTo: coverView.widthAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = [.button]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onTap = nil
        coverView.kf.cancelDownloadTask()
    }

    override var isHighlighted: Bool {
        didSet {
            guard !Motion.reduceMotion else { return }
            UIView.animate(withDuration: Motion.pressIn, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.contentView.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: Motion.pressScaleSubtle, y: Motion.pressScaleSubtle)
                    : .identity
            }
        }
    }

    func configure(title: String, imageURL: String?) {
        titleLabel.text = title
        accessibilityLabel = title
        coverView.setArtwork(imageURL.flatMap(URL.init(string:)), title: title)
    }
}
