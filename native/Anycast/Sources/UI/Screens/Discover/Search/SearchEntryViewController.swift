import UIKit

/// The Search tab's entry state, shown while there is no active query:
/// "Recent" (the recent queries as one grouped plate, swipe a row to delete
/// it, "Clear" empties the list) above "Categories" (a two-column grid of
/// tonal capsules). A tap on either submits its text through `onSelect`.
/// The categories load once per page lifetime (a failed load is retried on
/// the next appearance); on failure or when empty the section stays hidden.
/// With neither section the page is empty. The list runs under the page's
/// top chrome (the owner keeps the first row clear of it) and rides the
/// keyboard.
@MainActor
final class SearchEntryViewController: UIViewController, UICollectionViewDelegate {

    nonisolated enum Section: Hashable, Sendable {
        case recentsHeader, recents, categoriesHeader, categories
    }

    nonisolated enum Item: Hashable, Sendable {
        case header(Section)
        case recent(String)
        case category(String)
    }

    /// A recent query or a category was chosen; the text is the query.
    var onSelect: ((String) -> Void)?

    private(set) var recents: [String] = []
    private(set) var categories: [String] = []
    /// The sections on screen, top to bottom.
    private(set) var sections: [Section] = []

    /// The list's adjusted inset changed (the safe-area share arrives late).
    var onAdjustedInsetChange: (() -> Void)?

    private(set) lazy var collectionView: UICollectionView = {
        let list = EntryCollectionView(frame: .zero, collectionViewLayout: makeLayout())
        list.onAdjustedInsetChange = { [weak self] in self?.onAdjustedInsetChange?() }
        return list
    }()

    private let store: RecentSearchStore
    private let loadCategories: () async throws -> [String]
    private var isLoadingCategories = false
    private var didLoadCategories = false
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    init(store: RecentSearchStore, loadCategories: @escaping () async throws -> [String]) {
        self.store = store
        self.loadCategories = loadCategories
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildCollectionView()
        recents = store.queries
        apply(animated: false)
        loadCategoriesIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadCategoriesIfNeeded()
    }

    /// Re-reads the recent queries (the owner records them as searches run).
    func reload() {
        loadViewIfNeeded()
        recents = store.queries
        apply(animated: view.window != nil)
    }

    /// Submits the text behind a row or capsule.
    func activate(_ item: Item) {
        switch item {
        case .recent(let query), .category(let query): onSelect?(query)
        case .header: break
        }
    }

    // MARK: - Data

    private func loadCategoriesIfNeeded() {
        guard !didLoadCategories, !isLoadingCategories else { return }
        isLoadingCategories = true
        Task { [weak self] in
            guard let self else { return }
            let names = try? await self.loadCategories()
            self.isLoadingCategories = false
            guard let names else { return }
            self.didLoadCategories = true
            self.categories = names
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            self.apply(animated: self.view.window != nil)
        }
    }

    private func apply(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if !recents.isEmpty {
            snapshot.appendSections([.recentsHeader, .recents])
            snapshot.appendItems([.header(.recentsHeader)], toSection: .recentsHeader)
            snapshot.appendItems(recents.map(Item.recent), toSection: .recents)
        }
        if !categories.isEmpty {
            snapshot.appendSections([.categoriesHeader, .categories])
            snapshot.appendItems([.header(.categoriesHeader)], toSection: .categoriesHeader)
            snapshot.appendItems(categories.map(Item.category), toSection: .categories)
        }
        // Rows round their press fill by position; a delete moves the ends.
        snapshot.reconfigureItems(recents.map(Item.recent))
        sections = snapshot.sectionIdentifiers
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func delete(_ query: String) {
        store.remove(query)
        recents = store.queries
        apply(animated: true)
    }

    private func clearRecents() {
        store.clear()
        recents = []
        apply(animated: true)
    }

    // MARK: - Build

    private func buildCollectionView() {
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        // The list ends at the keyboard (the guide's top is the view's
        // bottom while the keyboard is down).
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])

        let headerCell = UICollectionView.CellRegistration<SearchEntryHeaderCell, Section> { [weak self] cell, _, section in
            if section == .recentsHeader {
                cell.configure(title: "Recent", actionTitle: "Clear") { self?.clearRecents() }
            } else {
                cell.configure(title: "Categories", actionTitle: nil, onAction: nil)
            }
        }
        let recentCell = UICollectionView.CellRegistration<SearchRecentCell, String> { [weak self] cell, indexPath, query in
            let count = self?.recents.count ?? 0
            cell.configure(query: query, isFirst: indexPath.item == 0, isLast: indexPath.item == count - 1)
        }
        let categoryCell = UICollectionView.CellRegistration<SearchCategoryCell, String> { cell, _, name in
            cell.configure(name: name)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { view, indexPath, item in
            switch item {
            case .header(let section):
                return view.dequeueConfiguredReusableCell(using: headerCell, for: indexPath, item: section)
            case .recent(let query):
                return view.dequeueConfiguredReusableCell(using: recentCell, for: indexPath, item: query)
            case .category(let name):
                return view.dequeueConfiguredReusableCell(using: categoryCell, for: indexPath, item: name)
            }
        }
    }

    // MARK: - Layout

    /// Row and capsule minimum height.
    private static let rowHeight: CGFloat = 44

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let self else { return Self.headerSection() }
            let sections = self.sections
            let section = sections.indices.contains(index) ? sections[index] : .recentsHeader
            // The last section rests clear of the tab bar and mini player.
            let isLast = index == sections.count - 1
            switch section {
            case .recentsHeader, .categoriesHeader: return Self.headerSection()
            case .recents: return self.recentsSection(environment, isLast: isLast)
            case .categories: return Self.categoriesSection()
            }
        }
        layout.register(GroupedPlateView.self, forDecorationViewOfKind: GroupedPlateView.elementKind)
        return layout
    }

    private static func headerSection() -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1), heightDimension: .estimated(rowHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Spacing.pageH, bottom: 0, trailing: Spacing.pageH
        )
        return section
    }

    /// One grouped plate of list rows (list sections carry the swipe actions).
    private func recentsSection(
        _ environment: NSCollectionLayoutEnvironment, isLast: Bool
    ) -> NSCollectionLayoutSection {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .clear
        configuration.showsSeparators = true
        configuration.itemSeparatorHandler = { [weak self] indexPath, sectionSeparator in
            var separator = sectionSeparator
            separator.topSeparatorVisibility = .hidden
            let isLastRow = indexPath.item >= (self?.recents.count ?? 0) - 1
            separator.bottomSeparatorVisibility = isLastRow ? .hidden : .visible
            separator.bottomSeparatorInsets = NSDirectionalEdgeInsets(
                top: 0, leading: SearchRecentCell.textColumnLeading, bottom: 0, trailing: 0
            )
            separator.color = Theme.outline
            return separator
        }
        configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self, case .recent(let query)? = self.dataSource.itemIdentifier(for: indexPath) else {
                return nil
            }
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
                self?.delete(query)
                completion(true)
            }
            delete.image = AppIcons.delete
            return UISwipeActionsConfiguration(actions: [delete])
        }
        let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        let insets = NSDirectionalEdgeInsets(
            top: 0, leading: Spacing.pageH, bottom: isLast ? Spacing.pageBottomSafe : Spacing.gap,
            trailing: Spacing.pageH
        )
        section.contentInsets = insets
        let plate = NSCollectionLayoutDecorationItem.background(elementKind: GroupedPlateView.elementKind)
        plate.contentInsets = insets
        section.decorationItems = [plate]
        return section
    }

    /// Two equal columns of capsules; each item carries half the column gap
    /// as inset, so the section insets give it back.
    private static func categoriesSection() -> NSCollectionLayoutSection {
        let half = Spacing.md / 2
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(0.5), heightDimension: .estimated(rowHeight)
        ))
        item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: half, bottom: 0, trailing: half)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .estimated(rowHeight)
            ),
            repeatingSubitem: item, count: 2
        )
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = Spacing.md
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Spacing.pageH - half, bottom: Spacing.pageBottomSafe,
            trailing: Spacing.pageH - half
        )
        return section
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        if case .header? = dataSource.itemIdentifier(for: indexPath) { return false }
        return true
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        activate(item)
    }
}

/// Reports adjusted-inset changes to its owner.
private final class EntryCollectionView: UICollectionView {
    var onAdjustedInsetChange: (() -> Void)?

    override func adjustedContentInsetDidChange() {
        super.adjustedContentInsetDidChange()
        onAdjustedInsetChange?()
    }
}

// MARK: - Cells

/// A section label (Meta) with an optional trailing text action in the
/// action colour.
private final class SearchEntryHeaderCell: UICollectionViewCell {

    private let titleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = TypographyV2.meta.font()
        titleLabel.textColor = TypographyV2.meta.color
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = Theme.primary
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: Spacing.gap, leading: Spacing.gap, bottom: Spacing.gap, trailing: 0
        )
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.body.font()
            return outgoing
        }
        actionButton.configuration = configuration
        actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(actionButton)

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor),
            actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(title: String, actionTitle: String?, onAction: (() -> Void)?) {
        titleLabel.text = title
        actionButton.configuration?.title = actionTitle
        actionButton.isHidden = actionTitle == nil
        self.onAction = onAction
    }
}

/// One recent query as a row of the grouped plate: the clock-arrow symbol
/// and the query on one truncating line. A touch fills the row (the plate's
/// corners clip the fill); nothing scales.
private final class SearchRecentCell: UICollectionViewListCell {

    private static let iconSide: CGFloat = 20
    /// Where the query (and the row separator) starts.
    static let textColumnLeading = Spacing.pageH + iconSide + Spacing.gap

    private let iconView = UIImageView(image: AppIcons.recentSearch)
    private let queryLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
        contentView.layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = [.button]

        iconView.tintColor = Theme.onSurfaceVariant
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        queryLabel.font = TypographyV2.body.font()
        queryLabel.textColor = TypographyV2.body.color
        queryLabel.numberOfLines = 1
        queryLabel.lineBreakMode = .byTruncatingTail
        queryLabel.adjustsFontForContentSizeCategory = true
        queryLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(queryLabel)

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.pageH),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSide),
            queryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.textColumnLeading),
            queryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.pageH),
            queryLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Spacing.gap),
            queryLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Spacing.gap),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(query: String, isFirst: Bool, isLast: Bool) {
        queryLabel.text = query
        accessibilityLabel = query
        var corners: CACornerMask = []
        if isFirst { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if isLast { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        contentView.layer.maskedCorners = corners
        contentView.layer.cornerRadius = corners.isEmpty ? 0 : Radius.card
    }

    override var isHighlighted: Bool {
        didSet {
            let fill = isHighlighted ? AnycastColor.sandAlpha5 : .clear
            UIView.animate(withDuration: isHighlighted ? 0.1 : Motion.quick) {
                self.contentView.backgroundColor = fill
            }
        }
    }
}

/// A category as a tonal capsule: sand fill, the name centred on one
/// truncating line, at least 44 pt tall. A touch deepens the fill.
private final class SearchCategoryCell: UICollectionViewCell {

    private let nameLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = AnycastColor.sandAlpha4
        contentView.layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = [.button]

        nameLabel.font = TypographyV2.body.font()
        nameLabel.textColor = TypographyV2.body.color
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.pageH),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.pageH),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Spacing.gap),
            nameLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Spacing.gap),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(name: String) {
        nameLabel.text = name
        accessibilityLabel = name
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layer.cornerRadius = contentView.bounds.height / 2
    }

    override var isHighlighted: Bool {
        didSet {
            let fill = isHighlighted ? AnycastColor.sandAlpha8 : AnycastColor.sandAlpha4
            UIView.animate(withDuration: isHighlighted ? 0.1 : Motion.quick) {
                self.contentView.backgroundColor = fill
            }
        }
    }
}
