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

/// The channel card (lib/widgets/card.dart:323-453, 03 §2.12): rounded-20
/// bordered row, 64×64 rounded-12 cover (Kingfisher with a 20pt spinner
/// placeholder and a gray podcast glyph on error), 14pt comfortaa w700
/// single-line title, 12pt two-line description. Whole-card tap opens the
/// Channel sheet via the injected callback.
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
    private let cardContainer = UIView()
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

        cardContainer.backgroundColor = Theme.cardBackground
        cardContainer.layer.borderColor = Theme.cardOutline.cgColor
        cardContainer.layer.borderWidth = 1
        cardContainer.layer.cornerRadius = 20
        cardContainer.layer.cornerCurve = .continuous
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.isAccessibilityElement = true
        cardContainer.accessibilityTraits = [.button]
        contentView.addSubview(cardContainer)
        cardContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 12
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.primaryBackground
        coverView.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(coverView)

        spinner.color = Theme.primary
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        coverView.addSubview(spinner)

        errorIconView.image = AppIcons.playerMain
        errorIconView.tintColor = Theme.secondaryText
        errorIconView.contentMode = .center
        errorIconView.isHidden = true
        errorIconView.translatesAutoresizingMaskIntoConstraints = false
        coverView.addSubview(errorIconView)

        // 14pt comfortaa w700 per 03 §2.12 (styles.dart defaultTitle is 16 —
        // the PodcastCard pins its own size).
        let baseTitle = UIFont(name: "Comfortaa-Bold", size: 14)
            ?? UIFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: baseTitle)
        titleLabel.textColor = Typography.cardTitleBold.color
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true

        descriptionLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .systemFont(ofSize: 12)
        )
        descriptionLabel.textColor = Theme.secondaryLabelGray
        descriptionLabel.numberOfLines = 2
        descriptionLabel.adjustsFontForContentSizeCategory = true

        let textColumn = UIStackView(arrangedSubviews: [titleLabel])
        textColumn.axis = .vertical
        textColumn.spacing = 2
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

            coverView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 12),
            coverView.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 12),
            coverView.widthAnchor.constraint(equalToConstant: 64),
            coverView.heightAnchor.constraint(equalToConstant: 64),

            spinner.centerXAnchor.constraint(equalTo: coverView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: coverView.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 20),
            spinner.heightAnchor.constraint(equalToConstant: 20),

            errorIconView.centerXAnchor.constraint(equalTo: coverView.centerXAnchor),
            errorIconView.centerYAnchor.constraint(equalTo: coverView.centerYAnchor),

            textColumn.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 12),
            textColumn.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -12),
            textColumn.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 12),
            textColumn.bottomAnchor.constraint(lessThanOrEqualTo: cardContainer.bottomAnchor, constant: -12),
        ])
    }

    @objc private func tapped() {
        guard let content else { return }
        onTap?(content)
    }
}
