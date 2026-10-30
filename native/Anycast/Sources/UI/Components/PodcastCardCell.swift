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

/// The channel row (lib/widgets/card.dart:323-453, 03 §2.12) as one row of
/// a grouped plate (adopted 2026-10-21: lists prefer one plate over stacked
/// cards): a 56 pt cover (radius sm, the shared artwork placeholder while
/// loading and on error), the Emphasis title on one line and the Meta
/// description on two. Rows after the first draw a hairline that starts at
/// the text, past the cover. The plate is the section's background
/// (`makeGroupedLayout`). Touching a row only fills it; nothing scales.
/// Whole-row tap opens the Channel sheet via the injected callback.
final class PodcastCardCell: UICollectionViewCell {

    static let reuseIdentifier = "PodcastCardCell"
    /// 12 pt padding around the text column (22 title + 2 + 40 description).
    static let rowHeight: CGFloat = 88
    static let coverSide: CGFloat = 56

    /// Whole-row tap → open Channel (card.dart:330-342).
    var onTap: ((PodcastCardContent) -> Void)?


    private var content: PodcastCardContent?
    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onTap = nil
        setPosition(isFirst: false, isLast: false)
        coverView.kf.cancelDownloadTask()
    }

    func configure(_ content: PodcastCardContent) {
        self.content = content
        contentView.accessibilityLabel = content.title

        titleLabel.text = content.title
        descriptionLabel.text = content.description

        coverView.setArtwork(content.imageURL.flatMap(URL.init(string:)), title: content.title)
    }

    /// Where the row sits on its plate: the first row has no hairline, and
    /// the first and last rows round their press fill into the plate's
    /// corners.
    func setPosition(isFirst: Bool, isLast: Bool) {
        separator.isHidden = isFirst
        var corners: CACornerMask = []
        if isFirst { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if isLast { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        contentView.layer.maskedCorners = corners
        contentView.layer.cornerRadius = corners.isEmpty ? 0 : Radius.card
    }

    private func build() {
        contentView.backgroundColor = .clear
        contentView.layer.cornerCurve = .continuous
        contentView.isAccessibilityElement = true
        contentView.accessibilityTraits = [.button]
        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = Radius.sm
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.surfaceContainerHighest
        coverView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(coverView)

        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = TypographyV2.emphasis.color
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true

        descriptionLabel.font = TypographyV2.meta.font()
        descriptionLabel.textColor = TypographyV2.meta.color
        descriptionLabel.numberOfLines = 2
        descriptionLabel.adjustsFontForContentSizeCategory = true

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel])
        textColumn.axis = .vertical
        textColumn.spacing = Spacing.xxs
        textColumn.alignment = .fill
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textColumn)

        separator.backgroundColor = Theme.outline
        separator.isUserInteractionEnabled = false
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            // 80 pt minimum (the cover plus 12 pt above and below); the text
            // column usually sets the height and grows with Dynamic Type.
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.coverSide + Spacing.gap * 2),

            coverView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.pageH),
            coverView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: Self.coverSide),
            coverView.heightAnchor.constraint(equalToConstant: Self.coverSide),

            textColumn.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: Spacing.gap),
            textColumn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.pageH),
            textColumn.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: Spacing.gap),
            textColumn.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Spacing.gap),
            textColumn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            separator.topAnchor.constraint(equalTo: contentView.topAnchor),
            separator.leadingAnchor.constraint(equalTo: textColumn.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.pageH),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    /// Grouped-plate rows answer a touch with a fill, never a scale.
    override var isHighlighted: Bool {
        didSet {
            let fill = isHighlighted ? AnycastColor.sandAlpha5 : .clear
            UIView.animate(withDuration: isHighlighted ? 0.1 : Motion.quick) {
                self.contentView.backgroundColor = fill
            }
        }
    }

    @objc private func tapped() {
        guard let content else { return }
        onTap?(content)
    }

    /// The channel list layout: one section of full-width rows on a grouped
    /// plate inset `horizontal` from the edges, `top` below the list's top
    /// and `bottom` clear of the tab bar and mini player.
    static func makeGroupedLayout(
        top: CGFloat = Spacing.gap, horizontal: CGFloat = Spacing.pageH, bottom: CGFloat = 88
    ) -> UICollectionViewCompositionalLayout {
        let insets = NSDirectionalEdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal)
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(rowHeight)
                )
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: item.layoutSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = insets
            let plate = NSCollectionLayoutDecorationItem.background(elementKind: GroupedPlateView.elementKind)
            plate.contentInsets = insets
            section.decorationItems = [plate]
            return section
        }
        layout.register(GroupedPlateView.self, forDecorationViewOfKind: GroupedPlateView.elementKind)
        return layout
    }
}

/// The plate behind a grouped list: `surface`, radius-card corners and the
/// content hairline, clipping the rows' press fill to its corners.
final class GroupedPlateView: UICollectionReusableView {

    static let elementKind = "grouped-plate"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.surface
        layer.cornerRadius = Radius.card
        layer.cornerCurve = .continuous
        layer.borderWidth = Spacing.hairline
        updateStroke()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.updateStroke()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateStroke() {
        layer.borderColor = AnycastColor.sandAlpha3.resolvedColor(with: traitCollection).cgColor
    }
}
