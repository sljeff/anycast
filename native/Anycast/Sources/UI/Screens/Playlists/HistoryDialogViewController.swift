import UIKit
import Kingfisher
import AnycastKit

/// Calendar bucket for the History sheet. Display only — the stored order
/// is `lastPlayedAt`.
enum HistoryDaySection: Int, Hashable, CaseIterable {
    case today
    case yesterday
    case earlier

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .earlier: return "Earlier"
        }
    }
}

enum HistoryDayGrouping {

    static func section(
        for lastPlayedAt: Int64?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> HistoryDaySection {
        guard let lastPlayedAt else { return .earlier }
        let date = Date(timeIntervalSince1970: TimeInterval(lastPlayedAt) / 1000)
        // Compare against the injected clock. `isDateInToday` / `isDateInYesterday`
        // always use the wall clock, so a caller-supplied `now` would be ignored.
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
              calendar.isDate(date, inSameDayAs: startOfYesterday) else {
            return .earlier
        }
        return .yesterday
    }

    /// Non-empty buckets in Today / Yesterday / Earlier order. `episodes`
    /// is already newest-first; that order is kept inside each bucket.
    static func grouped(
        _ episodes: [HistoryEpisodeRow],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [(section: HistoryDaySection, rows: [HistoryEpisodeRow])] {
        var buckets: [HistoryDaySection: [HistoryEpisodeRow]] = [:]
        for episode in episodes {
            let section = section(for: episode.lastPlayedAt, now: now, calendar: calendar)
            buckets[section, default: []].append(episode)
        }
        return HistoryDaySection.allCases.compactMap { section in
            guard let rows = buckets[section], !rows.isEmpty else { return nil }
            return (section, rows)
        }
    }
}

enum HistoryPresentation {

    /// "Night Kitchen · 2h ago". Either side is dropped when it is missing.
    static func subtitle(channel: String?, lastPlayedAt: Int64?, now: Date = Date()) -> String {
        var parts: [String] = []
        if let channel, !channel.isEmpty { parts.append(channel) }
        if let lastPlayedAt {
            parts.append(RelativeTimeFormatter.format(lastPlayedAt, now: now))
        }
        return parts.joined(separator: " · ")
    }
}

/// History, opened from Settings (after that sheet dismisses) and from the
/// Inbox tail or empty-state link. One `AppSheets` page sheet at medium
/// and large: a "History" title, Clear All when the list is non-empty, and
/// day-grouped rows. Tap opens Detail. Swipe deletes one row. Clear All
/// asks with a system alert, then deletes. The empty state is one sentence
/// and an Explore button that closes the sheet and opens Discover.
@MainActor
final class HistoryDialogViewController: UIViewController {

    private let context: UIContext
    /// The context's database; tests inject a temporary one.
    private let database: AppDatabase

    private(set) var episodes: [HistoryEpisodeRow] = []
    private var isLoading = true

    private var dataSource: UICollectionViewDiffableDataSource<HistoryDaySection, String>!

    private let headerStack = UIStackView()
    private let titleLabel = UILabel()
    private let clearButton = UIButton(type: .system)
    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let emptyStack = UIStackView()
    private let emptyLabel = UILabel()
    private let exploreButton = AnycastButton.make(.secondary, title: "Explore")

    static func present(from presenter: UIViewController, context: UIContext) {
        let controller = HistoryDialogViewController(context: context)
        AppSheets.presentExpand(controller, from: presenter, detents: [.medium(), .large()])
    }

    init(context: UIContext, database: AppDatabase? = nil) {
        self.context = context
        self.database = database ?? context.database
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        buildSheet()
        configureDataSource()
        Task { await reload() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ScrollEdgeChrome.clearTop(of: collectionView, to: headerStack.frame.maxY + Spacing.gap)
        let inset = view.safeAreaInsets.bottom
        if abs(collectionView.contentInset.bottom - inset) > 0.5 {
            collectionView.contentInset.bottom = inset
        }
    }

    // MARK: - Build

    private func buildSheet() {
        titleLabel.text = "History"
        titleLabel.font = TypographyV2.headlineMedium.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var clearConfiguration = UIButton.Configuration.plain()
        clearConfiguration.title = "Clear All"
        clearConfiguration.baseForegroundColor = Theme.error
        clearConfiguration.contentInsets = .zero
        clearConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.body.font()
            return outgoing
        }
        clearButton.configuration = clearConfiguration
        clearButton.titleLabel?.adjustsFontForContentSizeCategory = true
        clearButton.accessibilityLabel = "Clear All"
        clearButton.accessibilityIdentifier = "history-clear-all"
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        clearButton.isHidden = true
        clearButton.addAction(UIAction { [weak self] _ in self?.clearAllTapped() }, for: .touchUpInside)

        let spacer = UIView()
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = Spacing.gap
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(spacer)
        headerStack.addArrangedSubview(clearButton)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerStack)

        spinner.color = Theme.primary
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        emptyLabel.text = "Play an episode and it shows up here."
        emptyLabel.font = TypographyV2.emphasis.font()
        emptyLabel.textColor = Theme.onSurface
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.adjustsFontForContentSizeCategory = true

        exploreButton.accessibilityLabel = "Explore"
        exploreButton.accessibilityIdentifier = "history-explore"
        exploreButton.addAction(UIAction { [weak self] _ in self?.exploreTapped() }, for: .touchUpInside)

        emptyStack.axis = .vertical
        emptyStack.alignment = .center
        emptyStack.spacing = Spacing.cardInner
        emptyStack.addArrangedSubview(emptyLabel)
        emptyStack.addArrangedSubview(exploreButton)
        emptyStack.isHidden = true
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStack)

        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        let emptyCenter = emptyStack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        emptyCenter.priority = .defaultHigh

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: Spacing.sheetContent),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.sheetContent),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.sheetContent),

            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: Spacing.sheetContent),
            emptyStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -Spacing.sheetContent),
            emptyStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStack.topAnchor.constraint(greaterThanOrEqualTo: headerStack.bottomAnchor, constant: Spacing.xl),
            emptyStack.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            emptyCenter,

            exploreButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        ScrollEdgeChrome.attachTopBand(
            to: collectionView, in: view, below: headerStack.bottomAnchor, restingGap: Spacing.gap
        )
        ScrollEdgeChrome.attachBottomEdge(to: collectionView, in: view)
        view.bringSubviewToFront(headerStack)
    }

    private func configureDataSource() {
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        collectionView.register(
            HistoryRowCell.self, forCellWithReuseIdentifier: HistoryRowCell.reuseIdentifier
        )
        collectionView.delegate = self

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            let title = self?.dataSource.sectionIdentifier(for: indexPath.section)?.title ?? ""
            var config = header.defaultContentConfiguration()
            config.text = title
            config.textProperties.font = TypographyV2.meta.font()
            config.textProperties.color = Theme.onSurfaceVariant
            config.textProperties.numberOfLines = 0
            config.textProperties.adjustsFontForContentSizeCategory = true
            config.directionalLayoutMargins = NSDirectionalEdgeInsets(
                top: Spacing.gap,
                leading: Spacing.sheetContent,
                bottom: Spacing.xs,
                trailing: Spacing.sheetContent
            )
            header.contentConfiguration = config
            header.backgroundConfiguration = .clear()
            header.accessibilityTraits = .header
        }

        dataSource = UICollectionViewDiffableDataSource<HistoryDaySection, String>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, enclosureURL in
            guard let self,
                  let cell = collectionView.dequeueReusableCell(
                      withReuseIdentifier: HistoryRowCell.reuseIdentifier, for: indexPath
                  ) as? HistoryRowCell,
                  let episode = self.episodes.first(where: { $0.enclosureUrl == enclosureURL }) else {
                return HistoryRowCell()
            }
            cell.configure(episode)
            cell.onDelete = { [weak self] in
                self?.deleteEpisode(url: enclosureURL)
            }
            cell.onTap = { [weak self] in
                self?.presentDetail(episode)
            }
            return cell
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    /// A plain list: rows swipe to delete, hairlines only between rows,
    /// starting at the text column. Day headers are display-only.
    private func makeLayout() -> UICollectionViewCompositionalLayout {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = true
        configuration.backgroundColor = .clear
        configuration.headerMode = .supplementary
        configuration.headerTopPadding = Spacing.sm
        configuration.itemSeparatorHandler = { [weak self] indexPath, sectionSeparator in
            var separator = sectionSeparator
            separator.topSeparatorVisibility = .hidden
            let count = self?.itemCount(inSectionAt: indexPath.section) ?? 0
            let isLast = indexPath.item >= count - 1
            separator.bottomSeparatorVisibility = isLast ? .hidden : .visible
            separator.bottomSeparatorInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: HistoryRowCell.textColumnLeading,
                bottom: 0,
                trailing: Spacing.sheetContent
            )
            separator.color = Theme.outlineVariant
            return separator
        }
        configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self, let url = self.dataSource.itemIdentifier(for: indexPath) else { return nil }
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
                self?.deleteEpisode(url: url)
                completion(true)
            }
            delete.image = AppIcons.delete
            return UISwipeActionsConfiguration(actions: [delete])
        }
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    private func itemCount(inSectionAt index: Int) -> Int {
        guard let dataSource, let section = dataSource.sectionIdentifier(for: index) else { return 0 }
        return dataSource.snapshot().numberOfItems(inSection: section)
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<HistoryDaySection, String>()
        for group in HistoryDayGrouping.grouped(episodes) {
            let identifiers = group.rows.compactMap(\.enclosureUrl)
            guard !identifiers.isEmpty else { continue }
            snapshot.appendSections([group.section])
            snapshot.appendItems(identifiers, toSection: group.section)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
        renderStates()
    }

    private func renderStates() {
        spinner.isHidden = !isLoading
        if isLoading { spinner.startAnimating() } else { spinner.stopAnimating() }
        let isEmpty = !isLoading && episodes.isEmpty
        emptyStack.isHidden = !isEmpty
        collectionView.isHidden = isLoading || isEmpty
        clearButton.isHidden = isLoading || episodes.isEmpty
    }

    // MARK: - Data

    private func reload() async {
        episodes = (try? await database.historyRepository().listAll()) ?? []
        isLoading = false
        applySnapshot()
    }

    func deleteEpisode(url: String) {
        episodes.removeAll { $0.enclosureUrl == url }
        applySnapshot()
        Task { [weak self] in
            do {
                try await self?.database.historyRepository().deleteMany([url])
            } catch {
                // The DB is the source of truth: a failed write reverts the
                // optimistic row removal instead of silently diverging.
                await self?.reload()
            }
        }
    }

    // MARK: - Clear All

    private func clearAllTapped() {
        guard !episodes.isEmpty else { return }
        let alert = UIAlertController(
            title: "Clear all listening history?",
            message: "This only removes History on this device. Playlists and progress stay.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { [weak self] _ in
            self?.commitClearAll()
        })
        present(alert, animated: true)
    }

    /// Deletes every history row. The alert is the confirmation; this does
    /// not touch playlists, progress, or subscriptions.
    func commitClearAll() {
        let urls = episodes.compactMap(\.enclosureUrl)
        guard !urls.isEmpty else { return }
        episodes = []
        applySnapshot()
        let repository = database.historyRepository()
        Task { [weak self] in
            do {
                try await repository.deleteMany(urls)
            } catch {
                await self?.reload()
            }
        }
    }

    private func exploreTapped() {
        // Same destination as the Inbox empty state's Explore: Discover.
        let tabs = context.tabs
        dismiss(animated: true) {
            tabs.select(2)
        }
    }
}

// MARK: - Row tap → Detail

extension HistoryDialogViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let url = dataSource.itemIdentifier(for: indexPath),
              let episode = episodes.first(where: { $0.enclosureUrl == url }) else { return }
        presentDetail(episode)
    }

    private func presentDetail(_ episode: HistoryEpisodeRow) {
        let detailEpisode = DetailViewController.Episode(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? "",
            pubDateMilliseconds: episode.pubDate,
            durationMilliseconds: episode.duration,
            imageURL: episode.imageUrl,
            rssFeedURL: episode.rssFeedUrl ?? "",
            enclosureURL: episode.enclosureUrl ?? "",
            descriptionHTML: episode.description ?? ""
        )
        DetailViewController.present(
            from: self,
            episode: detailEpisode,
            actions: [
                EpisodeCardAction(
                    icon: AppIcons.play,
                    accessibilityLabel: "Play"
                ) { [weak self] in
                    Task { await self?.playFromHistory(episode) }
                },
                EpisodeCardAction(
                    icon: AppIcons.remove,
                    accessibilityLabel: "Remove"
                ) { [weak self] in
                    guard let url = episode.enclosureUrl else { return }
                    self?.deleteEpisode(url: url)
                },
            ],
            htmlRenderer: HTMLContentRenderer(),
            shortenURL: { [weak self] url in
                await self?.context.api.getShortURL(for: url) ?? url
            }
        )
    }

    private func playFromHistory(_ episode: HistoryEpisodeRow) async {
        let playlistId = ChannelPlaylistLogic.defaultPlaylistID
        var row = PlaylistEpisodeRow(
            title: episode.title,
            description: episode.description,
            duration: episode.duration,
            enclosureUrl: episode.enclosureUrl,
            pubDate: episode.pubDate,
            imageUrl: episode.imageUrl,
            channelTitle: episode.channelTitle,
            rssFeedUrl: episode.rssFeedUrl,
            playlistId: playlistId
        )
        let repository = context.database.playlistRepository()
        try? await repository.insertOrUpdateByIndex(row, playlistId: playlistId, index: 0)
        if let stored = try? await repository.episode(byEnclosureURL: episode.enclosureUrl ?? "") {
            row = stored
        }
        await context.playback.playByEpisode(row)
    }
}

// MARK: - Row cell

/// One history row: rounded cover, one wrapping title, show name and relative time.
final class HistoryRowCell: UICollectionViewListCell {

    static let reuseIdentifier = "HistoryRowCell"

    private static let coverSize: CGFloat = 56
    /// Where the text column (and the row separator) starts.
    static let textColumnLeading = Spacing.sheetContent + coverSize + Spacing.gap

    var onDelete: (() -> Void)?
    var onTap: (() -> Void)?

    private let coverView = UIImageView()
    let titleLabel = UILabel()
    private let channelLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onDelete = nil
        onTap = nil
        coverView.kf.cancelDownloadTask()
    }

    private func build() {
        backgroundConfiguration = .clear()

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = Radius.sm
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.surfaceContainerHigh
        coverView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(coverView)

        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.adjustsFontForContentSizeCategory = true

        channelLabel.font = TypographyV2.meta.font()
        channelLabel.textColor = Theme.onSurfaceVariant
        channelLabel.numberOfLines = 0
        channelLabel.lineBreakMode = .byWordWrapping
        channelLabel.adjustsFontForContentSizeCategory = true

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, channelLabel])
        textColumn.axis = .vertical
        textColumn.spacing = Spacing.xxs
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textColumn)

        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.sheetContent),
            coverView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: Self.coverSize),
            coverView.heightAnchor.constraint(equalToConstant: Self.coverSize),
            coverView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: Spacing.md),

            textColumn.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: Spacing.gap),
            textColumn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.sheetContent),
            textColumn.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: Spacing.row),
            textColumn.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Spacing.row),
            textColumn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
        ])
    }

    func configure(_ episode: HistoryEpisodeRow, now: Date = Date()) {
        let url = episode.imageUrl.flatMap(URL.init(string:))
        coverView.setArtwork(url, title: episode.channelTitle)
        titleLabel.text = episode.title ?? ""
        let subtitle = HistoryPresentation.subtitle(
            channel: episode.channelTitle, lastPlayedAt: episode.lastPlayedAt, now: now
        )
        channelLabel.text = subtitle
        channelLabel.isHidden = subtitle.isEmpty
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = "\(episode.title ?? ""), \(episode.channelTitle ?? "")"
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Delete") { [weak self] _ in
                self?.onDelete?()
                return true
            }
        ]
    }

    override func accessibilityActivate() -> Bool {
        onTap?()
        return true
    }
}
