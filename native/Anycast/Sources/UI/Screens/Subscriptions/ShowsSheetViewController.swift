import UIKit
import AnycastKit

/// Geometry of the Shows sheet: a title over a three-column cover grid.
/// Pure, so the sheet's fit-content detent and the grid layout share one
/// formula (and it is testable without a view).
nonisolated enum ShowsSheetLayout {

    static let inset = Spacing.sheetContent
    static let columns = 3
    static let columnGap = Spacing.gap
    static let rowGap = Spacing.cardInner
    static let titleGap: CGFloat = 16
    /// Cover to name.
    static let nameGap = Spacing.sm
    static let minimumDetentHeight: CGFloat = 350

    static func itemWidth(gridWidth: CGFloat) -> CGFloat {
        (gridWidth - CGFloat(columns - 1) * columnGap) / CGFloat(columns)
    }

    /// Square cover over a one-line name.
    static func itemHeight(gridWidth: CGFloat, nameLineHeight: CGFloat) -> CGFloat {
        itemWidth(gridWidth: gridWidth) + nameGap + nameLineHeight
    }

    static func gridHeight(gridWidth: CGFloat, count: Int, nameLineHeight: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let rows = (count + columns - 1) / columns
        return CGFloat(rows) * itemHeight(gridWidth: gridWidth, nameLineHeight: nameLineHeight)
            + CGFloat(rows - 1) * rowGap
    }

    /// The grid rests this far above the sheet's bottom edge: the 28 pt
    /// inset, or the bottom safe area when that is larger (Detail's rule).
    static func bottomGap(safeAreaBottom: CGFloat) -> CGFloat {
        max(inset, safeAreaBottom)
    }

    /// Title block + grid + bottom gap: at least 350 pt, at most the large
    /// detent. A detent height stops at the bottom safe area (the system
    /// adds that on top), so the part of the gap the safe area already
    /// provides is not counted.
    static func detentHeight(
        titleLineHeight: CGFloat, gridHeight: CGFloat, safeAreaBottom: CGFloat, maximum: CGFloat
    ) -> CGFloat {
        let content = inset + titleLineHeight + titleGap + gridHeight
            + bottomGap(safeAreaBottom: safeAreaBottom) - safeAreaBottom
        return min(max(content, minimumDetentHeight), maximum)
    }
}

/// The Shows sheet behind the shelf's "All shows" button: every
/// subscription as a cover over its name. A floating fit-content sheet that
/// grows with the grid up to the large detent (the grabber is on because it
/// is resizable) and scrolls beyond that. Tapping a show dismisses the sheet
/// and hands the show to `onSelect`, which opens its Channel.
final class ShowsSheetViewController: UIViewController {

    private static let fitDetent = UISheetPresentationController.Detent.Identifier("shows.fit")

    /// Called after the sheet dismissed itself, with the tapped show.
    var onSelect: ((SubscriptionRow) -> Void)?

    private let shows: [SubscriptionRow]
    private let titleLabel = UILabel()
    private let collectionView: UICollectionView
    /// Measured grid width and bottom safe area; nil until the first
    /// layout, when the detent falls back to estimates from the presenter.
    private var gridWidth: CGFloat?
    private var safeAreaBottom: CGFloat?

    static func present(
        from presenter: UIViewController,
        shows: [SubscriptionRow],
        onSelect: @escaping (SubscriptionRow) -> Void
    ) {
        let sheet = ShowsSheetViewController(shows: shows)
        sheet.onSelect = onSelect
        presenter.present(sheet, animated: true)
    }

    init(shows: [SubscriptionRow]) {
        self.shows = shows
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let width = environment.container.effectiveContentSize.width
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(ShowsSheetLayout.itemWidth(gridWidth: width)),
                heightDimension: .absolute(Self.itemHeight(gridWidth: width))
            ))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(Self.itemHeight(gridWidth: width))
                ),
                repeatingSubitem: item, count: ShowsSheetLayout.columns
            )
            group.interItemSpacing = .fixed(ShowsSheetLayout.columnGap)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = ShowsSheetLayout.rowGap
            return section
        }
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [
                .custom(identifier: Self.fitDetent) { [weak self] context in
                    self?.fitHeight(maximum: context.maximumDetentValue)
                },
                .large(),
            ]
            sheet.prefersGrabberVisible = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static var nameLineHeight: CGFloat {
        ceil(TypographyV2.meta.font().lineHeight)
    }

    private static func itemHeight(gridWidth: CGFloat) -> CGFloat {
        ShowsSheetLayout.itemHeight(gridWidth: gridWidth, nameLineHeight: nameLineHeight)
    }

    private func fitHeight(maximum: CGFloat) -> CGFloat {
        // Before the first layout the sheet is laid out at the presenter's
        // width and inherits its bottom safe area.
        let presenterView = presentingViewController?.view
        let width = gridWidth ?? ((presenterView?.bounds.width ?? 402) - 2 * ShowsSheetLayout.inset)
        let safeBottom = safeAreaBottom ?? (presenterView?.window?.safeAreaInsets.bottom ?? 0)
        return ShowsSheetLayout.detentHeight(
            titleLineHeight: ceil(TypographyV2.emphasis.font().lineHeight),
            gridHeight: ShowsSheetLayout.gridHeight(
                gridWidth: width, count: shows.count, nameLineHeight: Self.nameLineHeight
            ),
            safeAreaBottom: safeBottom,
            maximum: maximum
        )
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.surface

        let title = NSMutableAttributedString(
            string: "Shows",
            attributes: [.font: TypographyV2.emphasis.font(), .foregroundColor: Theme.onSurface]
        )
        title.append(NSAttributedString(
            string: " · \(shows.count)",
            attributes: [.font: TypographyV2.meta.font(), .foregroundColor: TypographyV2.meta.color]
        ))
        titleLabel.attributedText = title
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.accessibilityTraits = .header
        titleLabel.accessibilityLabel = "Shows, \(shows.count)"
        titleLabel.accessibilityIdentifier = "shows-sheet-title"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ShowCoverCell.self, forCellWithReuseIdentifier: ShowCoverCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: ShowsSheetLayout.inset),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: ShowsSheetLayout.inset),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -ShowsSheetLayout.inset),

            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: ShowsSheetLayout.inset),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -ShowsSheetLayout.inset),
            // Runs under the title row and the sheet's bottom edge, fading
            // out behind both; `viewDidLayoutSubviews` keeps the resting
            // layout of a grid that started below the title.
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        ScrollEdgeChrome.attachTopBand(
            to: collectionView, in: view, below: titleLabel.bottomAnchor, fadeColor: Theme.surface,
            restingGap: ShowsSheetLayout.titleGap
        )
        ScrollEdgeChrome.attachBottomEdge(to: collectionView, in: view, fadeColor: Theme.surface)
        view.bringSubviewToFront(titleLabel)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ScrollEdgeChrome.clearTop(
            of: collectionView, to: titleLabel.frame.maxY + ShowsSheetLayout.titleGap
        )
        let width = collectionView.bounds.width
        let safeBottom = view.safeAreaInsets.bottom
        // The last row ends the same gap above the sheet's bottom edge that
        // the detent counts on, and scrolls clear of it when the grid is
        // taller than the sheet.
        collectionView.contentInset.bottom = ShowsSheetLayout.bottomGap(safeAreaBottom: safeBottom)
        guard width > 0, width != gridWidth || safeBottom != safeAreaBottom else { return }
        gridWidth = width
        safeAreaBottom = safeBottom
        // The estimates gave way to measurements: refit the detent.
        sheetPresentationController?.invalidateDetents()
    }
}

// MARK: - Data source / delegate

extension ShowsSheetViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        shows.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ShowCoverCell.reuseIdentifier,
            for: indexPath
        )
        if let cover = cell as? ShowCoverCell, shows.indices.contains(indexPath.item) {
            let show = shows[indexPath.item]
            cover.configure(title: show.title ?? "", imageURL: show.imageUrl)
        }
        return cell
    }
}

extension ShowsSheetViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard shows.indices.contains(indexPath.item) else { return }
        let show = shows[indexPath.item]
        Haptics.tap()
        dismiss(animated: true) { [onSelect] in onSelect?(show) }
    }
}
