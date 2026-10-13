import UIKit
import Kingfisher

/// Value payload for a channel (subscription) card — screens map
/// SubscriptionRow (or Discover channel hits) into this.
struct PodcastCardContent {
    var rssFeedURL: String
    var title: String
    var description: String
    var imageURL: String?
}

/// The channel card (lib/widgets/card.dart:323-453, 03 §2.12) in the
/// Anycast 2.0 card language: `CardSurfaceView` plate, 64×64 artwork-radius
/// cover (Kingfisher with a 20pt spinner placeholder and a podcast glyph on
/// error), titleSmall single-line title, bodySmall two-line description.
/// Whole-card tap opens the Channel sheet via the injected callback.
final class PodcastCardCell: UICollectionViewCell {

    static let reuseIdentifier = "PodcastCardCell"
    static let cardHeight: CGFloat = 88   // 64pt cover + 12pt padding ×2
    static let spacing: CGFloat = 12

    /// Whole-card tap → open Channel (card.dart:330-342).
    var onTap: ((PodcastCardContent) -> Void)?

    private var content: PodcastCardContent?
    /// Bumps on every (re)configure; a completion handler from a stale
    /// request — prepareForReuse's cancel lands its `.failure` callback one
    /// runloop turn later, after the reuse has already started a new load —
    /// must not clobber the new spinner/error state.
    private var coverGeneration = 0
    private let cardContainer = CardSurfaceView()
    private let coverView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let errorIconView = UIImageView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onTap = nil
        coverGeneration += 1
        coverView.kf.cancelDownloadTask()
        spinner.startAnimating()
        errorIconView.isHidden = true
    }

    func configure(_ content: PodcastCardContent) {
        self.content = content
        // The cardContainer is the accessibility element (the cell itself is
        // not); a label on the cell would never be read by VoiceOver.
        cardContainer.accessibilityLabel = content.title

        titleLabel.text = content.title
        descriptionLabel.text = content.description

        coverGeneration += 1
        let generation = coverGeneration
        spinner.startAnimating()
        errorIconView.isHidden = true
        coverView.kf.setImage(
            with: content.imageURL.flatMap(URL.init(string:)),
            placeholder: nil,
            options: [.transition(.none)],
            completionHandler: { [weak self] result in
                guard let self, generation == self.coverGeneration else { return }
                self.spinner.stopAnimating()
                if case .failure = result {
                    self.errorIconView.isHidden = false
                }
            }
        )
    }

    private func build() {
        contentView.backgroundColor = .clear

        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.isAccessibilityElement = true
        cardContainer.accessibilityTraits = [.button]
        contentView.addSubview(cardContainer)
        cardContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = Radius.artwork
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.surfaceContainerHighest
        coverView.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(coverView)

        spinner.color = Theme.primary
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        coverView.addSubview(spinner)

        errorIconView.image = AppIcons.playerMain
        errorIconView.tintColor = Theme.onSurfaceVariant
        errorIconView.contentMode = .center
        errorIconView.isHidden = true
        errorIconView.translatesAutoresizingMaskIntoConstraints = false
        coverView.addSubview(errorIconView)

        titleLabel.font = TypographyV2.titleSmall.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true

        descriptionLabel.font = TypographyV2.bodySmall.font()
        descriptionLabel.textColor = Theme.onSurfaceVariant
        descriptionLabel.numberOfLines = 2
        descriptionLabel.adjustsFontForContentSizeCategory = true

        let textColumn = UIStackView(arrangedSubviews: [titleLabel])
        textColumn.axis = .vertical
        textColumn.spacing = Spacing.xxs
        textColumn.alignment = .fill
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        textColumn.addArrangedSubview(descriptionLabel)
        cardContainer.addSubview(textColumn)

        NSLayoutConstraint.activate([
            cardContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            // 88 pt is the minimum (64pt cover + 12pt padding ×2); the card
            // self-sizes taller when the scaled fonts demand it (hosts use
            // .estimated heights).
            cardContainer.heightAnchor.constraint(
                greaterThanOrEqualToConstant: Self.cardHeight),

            coverView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: Spacing.gap),
            coverView.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: Spacing.gap),
            coverView.widthAnchor.constraint(equalToConstant: 64),
            coverView.heightAnchor.constraint(equalToConstant: 64),

            spinner.centerXAnchor.constraint(equalTo: coverView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: coverView.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 20),
            spinner.heightAnchor.constraint(equalToConstant: 20),

            errorIconView.centerXAnchor.constraint(equalTo: coverView.centerXAnchor),
            errorIconView.centerYAnchor.constraint(equalTo: coverView.centerYAnchor),

            textColumn.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: Spacing.gap),
            textColumn.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -Spacing.gap),
            textColumn.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: Spacing.gap),
            textColumn.bottomAnchor.constraint(lessThanOrEqualTo: cardContainer.bottomAnchor, constant: -Spacing.gap),
        ])
    }

    @objc private func tapped() {
        guard let content else { return }
        onTap?(content)
    }
}
