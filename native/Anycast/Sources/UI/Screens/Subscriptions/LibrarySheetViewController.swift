import UIKit
import AnycastKit

/// Geometry of the Library sheet: a title over the three-column cover grid
/// and the sections below it. Pure, so the sheet's fit-content detent and
/// the grid layout share one formula (and it is testable without a view).
nonisolated enum ShowsSheetLayout {

    /// Top and bottom rhythm of the sheet (the other sheets' 28).
    static let inset = Spacing.sheetContent
    /// A plate's outer edge sits this far from the sheet edge; its content
    /// starts `plateInset` further in.
    static let plateInset = Spacing.pageH
    /// Where covers, section titles and plate content start: 16 + 16.
    static let contentInset = plateInset + Spacing.pageH
    /// Space above a section title (the first one rests under the sheet title).
    static let sectionGap = Spacing.sectionGap
    /// Section title to what it heads.
    static let titleToContent = Spacing.md
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

    /// Title block + content below it (`gridHeight`) + bottom gap: at least 350 pt, at most the large
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

/// The Library sheet behind the Podcast tab's "all shows" button, top to
/// bottom: Shows (the cover grid), Moments (sentences kept from transcripts,
/// hidden when there are none) and Recently played (the latest five History
/// rows, then a row that opens History). A floating fit-content sheet that
/// grows with its content up to the large detent (the grabber is on because
/// it is resizable) and scrolls beyond that.
///
/// Tapping a show dismisses the sheet and hands the show to `onSelect`,
/// which opens its Channel. Playing a moment dismisses the sheet and starts
/// the episode at the moment's position. "All history" dismisses the sheet
/// and opens History.
final class LibrarySheetViewController: UIViewController {

    private static let fitDetent = UISheetPresentationController.Detent.Identifier("library.fit")
    /// Latest History rows shown under Recently played.
    static let recentLimit = 5

    nonisolated enum Section: Hashable, Sendable {
        case showsTitle, shows, momentsTitle, moments, recentTitle, recent, empty
    }

    nonisolated enum Item: Hashable, Sendable {
        case title(String)
        case show(Int)
        case moment(UUID)
        case recent(String)
        case allHistory
        /// How to get a first Moment; the only row while Moments is empty.
        case momentsHint
        /// A plain sentence when there is nothing at all.
        case note(String)
    }

    /// Called after the sheet dismissed itself, with the tapped show.
    var onSelect: ((SubscriptionRow) -> Void)?

    private let context: UIContext
    private let database: AppDatabase
    private let momentStore: MomentStore
    private let shows: [SubscriptionRow]
    private(set) var moments: [Moment] = []
    private(set) var recent: [HistoryEpisodeRow] = []

    private let titleLabel = UILabel()
    private let collectionView: UICollectionView
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    /// Measured grid width, bottom safe area and content height; nil until
    /// the first layout, when the detent falls back to estimates.
    private var gridWidth: CGFloat?
    private var safeAreaBottom: CGFloat?
    private var contentHeight: CGFloat?
    private nonisolated(unsafe) var momentsObserver: NSObjectProtocol?

    static func present(
        from presenter: UIViewController,
        context: UIContext,
        shows: [SubscriptionRow],
        onSelect: @escaping (SubscriptionRow) -> Void
    ) {
        let sheet = LibrarySheetViewController(context: context, shows: shows)
        sheet.onSelect = onSelect
        presenter.present(sheet, animated: true)
    }

    /// `database` and `momentStore` default to the context's and the app's;
    /// tests inject their own.
    init(
        context: UIContext,
        shows: [SubscriptionRow],
        database: AppDatabase? = nil,
        momentStore: MomentStore = .shared
    ) {
        self.context = context
        self.shows = shows
        self.database = database ?? context.database
        self.momentStore = momentStore
        // The provider needs the finished data source; `self` is not usable
        // before `super.init`, so it reaches the sections through a box.
        let box = SectionBox()
        self.sectionBox = box
        let layout = UICollectionViewCompositionalLayout { index, environment in
            box.provider?(index, environment)
        }
        layout.register(GroupedPlateView.self, forDecorationViewOfKind: GroupedPlateView.elementKind)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
        box.provider = { [weak self] index, environment in
            self?.layoutSection(at: index, environment: environment)
        }

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

    deinit {
        if let momentsObserver {
            NotificationCenter.default.removeObserver(momentsObserver)
        }
    }

    private final class SectionBox {
        var provider: ((Int, NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection?)?
    }
    private let sectionBox: SectionBox

    // MARK: - Detent

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
        let width = gridWidth
            ?? ((presenterView?.bounds.width ?? 402) - 2 * ShowsSheetLayout.contentInset)
        let safeBottom = safeAreaBottom ?? (presenterView?.window?.safeAreaInsets.bottom ?? 0)
        return ShowsSheetLayout.detentHeight(
            titleLineHeight: ceil(TypographyV2.emphasis.font().lineHeight),
            gridHeight: contentHeight ?? estimatedContentHeight(gridWidth: width),
            safeAreaBottom: safeBottom,
            maximum: maximum
        )
    }

    /// Before the first layout: the grid plus a rough height per row.
    private func estimatedContentHeight(gridWidth: CGFloat) -> CGFloat {
        let title = ShowsSheetLayout.sectionGap + ceil(TypographyV2.meta.font().lineHeight)
            + ShowsSheetLayout.titleToContent
        var height = title + ShowsSheetLayout.gridHeight(
            gridWidth: gridWidth, count: shows.count, nameLineHeight: Self.nameLineHeight
        )
        if !moments.isEmpty { height += title + CGFloat(moments.count) * 72 }
        if !recent.isEmpty { height += title + CGFloat(recent.count) * 64 + 48 }
        return height
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)

        titleLabel.text = "Library"
        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.accessibilityTraits = .header
        titleLabel.accessibilityIdentifier = "library-sheet-title"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "library-sheet-list"
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        configureDataSource()

        view.addSubview(titleLabel)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: ShowsSheetLayout.inset),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: ShowsSheetLayout.contentInset),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -ShowsSheetLayout.contentInset),

            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Runs under the title row and the sheet's bottom edge, fading
            // out behind both; `viewDidLayoutSubviews` keeps the resting
            // layout of content that started below the title.
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        ScrollEdgeChrome.attachTopBand(
            to: collectionView, in: view, below: titleLabel.bottomAnchor,
            restingGap: ShowsSheetLayout.titleGap
        )
        ScrollEdgeChrome.attachBottomEdge(to: collectionView, in: view)
        view.bringSubviewToFront(titleLabel)

        moments = momentStore.all
        applySnapshot()
        momentsObserver = NotificationCenter.default.addObserver(
            forName: MomentStore.didChange, object: momentStore, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadMoments() }
        }
        Task { await reloadRecent() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ScrollEdgeChrome.clearTop(
            of: collectionView, to: titleLabel.frame.maxY + ShowsSheetLayout.titleGap
        )
        let width = collectionView.bounds.width - 2 * ShowsSheetLayout.contentInset
        let safeBottom = view.safeAreaInsets.bottom
        // The last row ends the same gap above the sheet's bottom edge that
        // the detent counts on, and scrolls clear of it when the content is
        // taller than the sheet.
        collectionView.contentInset.bottom = ShowsSheetLayout.bottomGap(safeAreaBottom: safeBottom)
        guard width > 0 else { return }
        // Rows still below the fold are counted at the list's small estimate
        // until they are laid out, which cut the last row off; never fit
        // the sheet to less than the per-row estimate of what is listed.
        let measured = max(
            collectionView.collectionViewLayout.collectionViewContentSize.height,
            estimatedContentHeight(gridWidth: width)
        )
        guard width != gridWidth || safeBottom != safeAreaBottom || abs(measured - (contentHeight ?? 0)) > 0.5
        else { return }
        gridWidth = width
        safeAreaBottom = safeBottom
        contentHeight = measured
        // The estimates gave way to measurements: refit the detent.
        sheetPresentationController?.invalidateDetents()
    }

    // MARK: - Data

    private func reloadMoments() {
        moments = momentStore.all
        applySnapshot()
    }

    func reloadRecent() async {
        let rows = (try? await database.historyRepository().listAll()) ?? []
        recent = Array(rows.filter { $0.enclosureUrl != nil }.prefix(Self.recentLimit))
        applySnapshot()
    }

    private func applySnapshot() {
        guard dataSource != nil else { return }
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if !shows.isEmpty {
            snapshot.appendSections([.showsTitle, .shows])
            snapshot.appendItems([.title("Shows")], toSection: .showsTitle)
            snapshot.appendItems(shows.indices.map(Item.show), toSection: .shows)
        }
        if shows.isEmpty && moments.isEmpty && recent.isEmpty {
            snapshot.appendSections([.empty])
            snapshot.appendItems([.note("Shows you follow appear here.")], toSection: .empty)
        } else {
            // Moments keeps its header while empty: the hint is the only
            // place that says the feature exists.
            snapshot.appendSections([.momentsTitle, .moments])
            snapshot.appendItems([.title("Moments")], toSection: .momentsTitle)
            snapshot.appendItems(
                moments.isEmpty ? [.momentsHint] : moments.map { Item.moment($0.id) }, toSection: .moments
            )
        }
        if !recent.isEmpty {
            snapshot.appendSections([.recentTitle, .recent])
            snapshot.appendItems([.title("Recently played")], toSection: .recentTitle)
            snapshot.appendItems(
                recent.compactMap(\.enclosureUrl).map(Item.recent) + [.allHistory], toSection: .recent
            )
        }
        // A replay keeps a row's key but changes its time: reconfigure.
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter {
            if case .recent = $0 { return true }
            return false
        })
        dataSource.apply(snapshot, animatingDifferences: false)
        // New rows change the content height without changing the view's
        // bounds, so ask for the layout pass that refits the detent.
        view.setNeedsLayout()
    }

    // MARK: - Cells

    private func configureDataSource() {
        let titleCell = UICollectionView.CellRegistration<LibrarySectionTitleCell, String> { cell, _, title in
            cell.configure(title: title)
        }
        let showCell = UICollectionView.CellRegistration<ShowCoverCell, Int> { [weak self] cell, _, index in
            guard let self, self.shows.indices.contains(index) else { return }
            let show = self.shows[index]
            cell.configure(title: show.title ?? "", imageURL: show.imageUrl)
        }
        let momentCell = UICollectionView.CellRegistration<MomentRowCell, UUID> { [weak self] cell, _, id in
            guard let self, let moment = self.moments.first(where: { $0.id == id }) else { return }
            cell.configure(moment)
            cell.onPlay = { [weak self] in self?.play(moment) }
            cell.onDelete = { [weak self] in self?.momentStore.remove(id: id) }
        }
        let recentCell = UICollectionView.CellRegistration<HistoryRowCell, String> { [weak self] cell, _, url in
            guard let self, let episode = self.recent.first(where: { $0.enclosureUrl == url }) else { return }
            cell.horizontalInset = ShowsSheetLayout.plateInset
            cell.configure(episode)
            cell.onTap = { [weak self] in self?.presentDetail(episode) }
        }
        let allHistoryCell = UICollectionView.CellRegistration<LibraryLinkCell, Int> { cell, _, _ in
            cell.configure(title: "All history")
        }
        let hintCell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, text in
            var content = UIListContentConfiguration.cell()
            content.text = text
            content.textProperties.font = TypographyV2.meta.font()
            content.textProperties.color = Theme.onSurfaceVariant
            content.textProperties.adjustsFontForContentSizeCategory = true
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(
                top: Spacing.cardInner, leading: ShowsSheetLayout.plateInset,
                bottom: Spacing.cardInner, trailing: ShowsSheetLayout.plateInset
            )
            cell.contentConfiguration = content
            cell.backgroundConfiguration = .clear()
        }
        let noteCell = UICollectionView.CellRegistration<LibrarySectionTitleCell, String> { cell, _, text in
            cell.configure(title: text, isHeader: false)
        }
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { view, indexPath, item in
            switch item {
            case .title(let title):
                return view.dequeueConfiguredReusableCell(using: titleCell, for: indexPath, item: title)
            case .show(let index):
                return view.dequeueConfiguredReusableCell(using: showCell, for: indexPath, item: index)
            case .moment(let id):
                return view.dequeueConfiguredReusableCell(using: momentCell, for: indexPath, item: id)
            case .recent(let url):
                return view.dequeueConfiguredReusableCell(using: recentCell, for: indexPath, item: url)
            case .allHistory:
                return view.dequeueConfiguredReusableCell(using: allHistoryCell, for: indexPath, item: 0)
            case .momentsHint:
                return view.dequeueConfiguredReusableCell(
                    using: hintCell, for: indexPath, item: "Hold a transcript line to keep it here."
                )
            case .note(let text):
                return view.dequeueConfiguredReusableCell(using: noteCell, for: indexPath, item: text)
            }
        }
    }

    // MARK: - Layout

    private func layoutSection(
        at index: Int, environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection? {
        let sections = dataSource.snapshot().sectionIdentifiers
        guard sections.indices.contains(index) else { return nil }
        switch sections[index] {
        case .showsTitle, .momentsTitle, .recentTitle:
            return Self.titleSection(isFirst: index == 0)
        case .shows:
            return Self.showsSection(width: environment.container.effectiveContentSize.width)
        case .moments:
            return momentsSection(environment)
        case .recent:
            return recentSection(environment)
        case .empty:
            return Self.titleSection(isFirst: true)
        }
    }

    private static func titleSection(isFirst: Bool) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(ceil(TypographyV2.meta.font().lineHeight))
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: isFirst ? 0 : ShowsSheetLayout.sectionGap,
            leading: ShowsSheetLayout.contentInset,
            bottom: ShowsSheetLayout.titleToContent,
            trailing: ShowsSheetLayout.contentInset
        )
        return section
    }

    private static func showsSection(width: CGFloat) -> NSCollectionLayoutSection {
        let gridWidth = width - 2 * ShowsSheetLayout.contentInset
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .absolute(ShowsSheetLayout.itemWidth(gridWidth: gridWidth)),
            heightDimension: .absolute(itemHeight(gridWidth: gridWidth))
        ))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(itemHeight(gridWidth: gridWidth))
            ),
            repeatingSubitem: item, count: ShowsSheetLayout.columns
        )
        group.interItemSpacing = .fixed(ShowsSheetLayout.columnGap)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = ShowsSheetLayout.rowGap
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: ShowsSheetLayout.contentInset, bottom: 0, trailing: ShowsSheetLayout.contentInset
        )
        return section
    }

    /// One grouped plate of list rows, `plateInset` from the sheet edges.
    private func plateSection(
        _ configuration: UICollectionLayoutListConfiguration, _ environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection {
        let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        let insets = NSDirectionalEdgeInsets(
            top: 0, leading: ShowsSheetLayout.plateInset, bottom: 0, trailing: ShowsSheetLayout.plateInset
        )
        section.contentInsets = insets
        let plate = NSCollectionLayoutDecorationItem.background(elementKind: GroupedPlateView.elementKind)
        plate.contentInsets = insets
        section.decorationItems = [plate]
        return section
    }

    private func listConfiguration(
        textLeading: @escaping (IndexPath) -> CGFloat
    ) -> UICollectionLayoutListConfiguration {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .clear
        configuration.showsSeparators = true
        configuration.itemSeparatorHandler = { [weak self] indexPath, sectionSeparator in
            var separator = sectionSeparator
            separator.topSeparatorVisibility = .hidden
            let last = (self?.itemCount(inSectionAt: indexPath.section) ?? 0) - 1
            separator.bottomSeparatorVisibility = indexPath.item >= last ? .hidden : .visible
            separator.bottomSeparatorInsets = NSDirectionalEdgeInsets(
                top: 0, leading: textLeading(indexPath), bottom: 0, trailing: ShowsSheetLayout.plateInset
            )
            separator.color = Theme.outlineVariant
            return separator
        }
        return configuration
    }

    private func momentsSection(_ environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        var configuration = listConfiguration { _ in ShowsSheetLayout.plateInset }
        configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self, case .moment(let id)? = self.dataSource.itemIdentifier(for: indexPath) else {
                return nil
            }
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
                self?.momentStore.remove(id: id)
                completion(true)
            }
            delete.image = AppIcons.delete
            return UISwipeActionsConfiguration(actions: [delete])
        }
        return plateSection(configuration, environment)
    }

    private func recentSection(_ environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let configuration = listConfiguration { [weak self] indexPath in
            // The rule above "All history" runs the full width; the rest
            // start at the text column, like History's.
            let rows = (self?.itemCount(inSectionAt: indexPath.section) ?? 0) - 1
            return indexPath.item >= rows - 1
                ? ShowsSheetLayout.plateInset
                : HistoryRowCell.textColumnLeading(inset: ShowsSheetLayout.plateInset)
        }
        return plateSection(configuration, environment)
    }

    private func itemCount(inSectionAt index: Int) -> Int {
        guard let dataSource else { return 0 }
        let sections = dataSource.snapshot().sectionIdentifiers
        guard sections.indices.contains(index) else { return 0 }
        return dataSource.snapshot().numberOfItems(inSection: sections[index])
    }

    // MARK: - Actions

    private func play(_ moment: Moment) {
        Haptics.tap()
        let context = context
        dismiss(animated: true) {
            Task { await MomentPlayback.play(moment, context: context) }
        }
    }

    private func openHistory() {
        Haptics.tap()
        let presenter = presentingViewController
        let context = context
        dismiss(animated: true) {
            guard let presenter else { return }
            HistoryDialogViewController.present(from: presenter, context: context)
        }
    }

    private func presentDetail(_ episode: HistoryEpisodeRow) {
        HistoryEpisodeActions.presentDetail(
            episode, from: self, context: context,
            didPlay: { [weak self] in await self?.reloadRecent() },
            remove: { [weak self] url in
                guard let self else { return }
                self.recent.removeAll { $0.enclosureUrl == url }
                self.applySnapshot()
                Task { [weak self] in
                    try? await self?.database.historyRepository().deleteMany([url])
                    await self?.reloadRecent()
                }
            }
        )
    }
}

// MARK: - Delegate

extension LibrarySheetViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        isSelectable(dataSource.itemIdentifier(for: indexPath))
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        isSelectable(dataSource.itemIdentifier(for: indexPath))
    }

    /// Titles, the Moments hint and the empty note are text, not targets.
    private func isSelectable(_ item: Item?) -> Bool {
        switch item {
        case .title?, .momentsHint?, .note?: return false
        default: return true
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        switch dataSource.itemIdentifier(for: indexPath) {
        case .show(let index)?:
            guard shows.indices.contains(index) else { return }
            let show = shows[index]
            Haptics.tap()
            dismiss(animated: true) { [onSelect] in onSelect?(show) }
        case .moment(let id)?:
            guard let moment = moments.first(where: { $0.id == id }) else { return }
            play(moment)
        case .recent(let url)?:
            guard let episode = recent.first(where: { $0.enclosureUrl == url }) else { return }
            presentDetail(episode)
        case .allHistory?:
            openHistory()
        case .title?, .momentsHint?, .note?, nil:
            break
        }
    }
}

// MARK: - Cells

/// A section title: Meta, secondary colour, at the sheet's content edge.
final class LibrarySectionTitleCell: UICollectionViewCell {

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = TypographyV2.meta.font()
        label.textColor = TypographyV2.meta.color
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        accessibilityTraits = .header
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(title: String, isHeader: Bool = true) {
        label.text = title
        accessibilityLabel = title
        accessibilityTraits = isHeader ? .header : .staticText
    }
}

/// One kept moment: the quote (Body, up to three lines), then
/// "Show · 12:40" (Meta) with a play button at the trailing edge. The whole
/// row plays; the button is the visible affordance and a 44 pt hit target.
final class MomentRowCell: UICollectionViewListCell {

    static let playButtonSide: CGFloat = 44

    var onPlay: (() -> Void)?
    var onDelete: (() -> Void)?

    let quoteLabel = UILabel()
    let metaLabel = UILabel()
    let playButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)

        quoteLabel.font = TypographyV2.body.font()
        quoteLabel.textColor = Theme.onSurface
        quoteLabel.numberOfLines = 3
        quoteLabel.lineBreakMode = .byTruncatingTail
        quoteLabel.adjustsFontForContentSizeCategory = true

        metaLabel.font = TypographyV2.meta.font()
        metaLabel.textColor = TypographyV2.meta.color
        metaLabel.numberOfLines = 1
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.adjustsFontForContentSizeCategory = true

        let textColumn = UIStackView(arrangedSubviews: [quoteLabel, metaLabel])
        textColumn.axis = .vertical
        textColumn.spacing = Spacing.xxs
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textColumn)

        var configuration = UIButton.Configuration.plain()
        configuration.image = AppIcons.play
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 14, weight: .medium
        )
        configuration.baseForegroundColor = Theme.primary
        configuration.contentInsets = .zero
        playButton.configuration = configuration
        playButton.accessibilityLabel = "Play moment"
        playButton.addPressFeedback()
        playButton.addAction(UIAction { [weak self] _ in self?.onPlay?() }, for: .touchUpInside)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(playButton)

        let inset = ShowsSheetLayout.plateInset
        NSLayoutConstraint.activate([
            textColumn.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: inset),
            textColumn.trailingAnchor.constraint(equalTo: playButton.leadingAnchor),
            textColumn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Spacing.gap),
            textColumn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Spacing.gap),

            // The glyph is about 12 pt wide; flush with the plate edge it
            // ends 16 pt inside it, like the text starts.
            playButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            playButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: Self.playButtonSide),
            playButton.heightAnchor.constraint(equalToConstant: Self.playButtonSide),
        ])

        configurationUpdateHandler = { cell, state in
            var background = UIBackgroundConfiguration.clear()
            if state.isHighlighted || state.isSelected {
                background.backgroundColor = AnycastColor.sandAlpha5
            }
            cell.backgroundConfiguration = background
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onPlay = nil
        onDelete = nil
    }

    func configure(_ moment: Moment) {
        quoteLabel.text = moment.text
        let time = LyricsTimestamp.string(milliseconds: moment.startMilliseconds)
        metaLabel.text = moment.showTitle.isEmpty ? time : "\(moment.showTitle) · \(time)"
        // The row is the one element; the button is its visual twin.
        playButton.isAccessibilityElement = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = [moment.text, metaLabel.text].compactMap { $0 }.joined(separator: ", ")
        accessibilityHint = "Plays from this moment"
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Delete") { [weak self] _ in
                self?.onDelete?()
                return true
            }
        ]
    }

    override func accessibilityActivate() -> Bool {
        onPlay?()
        return true
    }
}

/// A plate row that opens something: a Body title and a disclosure chevron.
final class LibraryLinkCell: UICollectionViewListCell {

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = TypographyV2.body.font()
        label.textColor = Theme.onSurface
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        let chevron = UIImageView(image: AppIcons.disclosure)
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        chevron.tintColor = TypographyV2.meta.color
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(chevron)

        let inset = ShowsSheetLayout.plateInset
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: inset),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Spacing.gap),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Spacing.gap),
            chevron.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: Spacing.md),
            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -inset),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button

        configurationUpdateHandler = { cell, state in
            var background = UIBackgroundConfiguration.clear()
            if state.isHighlighted || state.isSelected {
                background.backgroundColor = AnycastColor.sandAlpha5
            }
            cell.backgroundConfiguration = background
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(title: String) {
        label.text = title
        accessibilityLabel = title
    }
}
