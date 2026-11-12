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

    /// "2h ago · Night Kitchen". The time comes first so one-line truncation
    /// eats only the show name. A row with no stored play time (upgraded
    /// from schema 4) shows just the show name; either side is dropped when
    /// it is missing.
    static func subtitle(channel: String?, lastPlayedAt: Int64?, now: Date = Date()) -> String {
        var parts: [String] = []
        if let lastPlayedAt {
            parts.append(RelativeTimeFormatter.format(lastPlayedAt, now: now))
        }
        if let channel, !channel.isEmpty { parts.append(channel) }
        return parts.joined(separator: " · ")
    }

    /// VoiceOver: "Title, Show, 2h ago". The time is spoken only when known.
    static func accessibilityLabel(
        title: String?, channel: String?, lastPlayedAt: Int64?, now: Date = Date()
    ) -> String {
        var parts: [String] = []
        if let title, !title.isEmpty { parts.append(title) }
        if let channel, !channel.isEmpty { parts.append(channel) }
        if let lastPlayedAt {
            parts.append(RelativeTimeFormatter.format(lastPlayedAt, now: now))
        }
        return parts.joined(separator: ", ")
    }
}

/// History, opened from Settings (after that sheet dismisses) and from the
/// Inbox / Playlist tail or empty-state link. One `AppSheets` page sheet at
/// medium and large: a left-aligned "History" title (like Settings and
/// Shows) and day-grouped rows (44 pt cover, one-line title, "2h ago · Show"
/// meta). Day headers scroll with the list; they never pin. Tap opens
/// Detail; a Play from Detail reloads the list. Swipe deletes one row.
/// Clear All lives at the bottom as a hold-to-confirm button: the clear is
/// deferred for a 5 s Undo window and the DB is only written when it ends
/// (or the sheet disappears / the app backgrounds), so Undo is a plain
/// re-read. VoiceOver and Switch Control skip the hold for an inline
/// Cancel / Clear confirm. The empty state is the shared `EmptyStateView`
/// with an Explore button that closes the sheet and opens Discover.
@MainActor
final class HistoryDialogViewController: UIViewController {

    /// What the pinned footer shows.
    enum FooterState { case hidden, hold, undo, confirm }

    private let context: UIContext
    /// The context's database; tests inject a temporary one.
    private let database: AppDatabase
    private let undoWindow: Duration

    private(set) var episodes: [HistoryEpisodeRow] = []
    private(set) var footerState: FooterState = .hidden
    /// A Clear is waiting out its Undo window; the DB is untouched.
    private(set) var hasPendingClear = false
    private var isLoading = true
    /// A clear was begun in this presentation (pending or committed).
    private var didClear = false

    private var pendingURLs: [String] = []
    /// When the pending clear began: plays from then on survive its commit.
    private var pendingClearStartedAt: Int64 = 0
    private var commitTask: Task<Void, Never>?
    /// Block-API observer token — touched only on the main thread;
    /// `nonisolated(unsafe)` because deinit is nonisolated.
    private nonisolated(unsafe) var backgroundObserver: NSObjectProtocol?

    private var dataSource: UICollectionViewDiffableDataSource<HistoryDaySection, String>!

    private let titleLabel = UILabel()
    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let emptyView = EmptyStateView()
    private let exploreButton = UIButton(type: .system)
    private let bottomFade = ScrollEdgeFade(edge: .bottom, color: Theme.background)
    private let footerStack = UIStackView()
    private let holdButton = HoldToConfirmButton(
        title: "Hold to Clear History", holdingTitle: "Keep holding…", image: AppIcons.delete
    )
    private let undoButton = UIButton(type: .system)
    private let confirmStack = UIStackView()
    private let confirmLabel = UILabel()

    static func present(from presenter: UIViewController, context: UIContext) {
        let controller = HistoryDialogViewController(context: context)
        AppSheets.presentExpand(controller, from: presenter, detents: [.medium(), .large()])
    }

    init(context: UIContext, database: AppDatabase? = nil, undoWindow: Duration = .seconds(5)) {
        self.context = context
        self.database = database ?? context.database
        self.undoWindow = undoWindow
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        buildSheet()
        configureDataSource()
        // A pending clear must not outlive the app being suspended.
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.commitPendingClear()
        }
        Task { await reload() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ScrollEdgeChrome.clearTop(of: collectionView, to: titleLabel.frame.maxY + Spacing.gap)
        // Let the last row scroll clear of the pinned footer and its fade.
        let inset = footerStack.isHidden
            ? view.safeAreaInsets.bottom
            : max(0, view.bounds.height - footerStack.frame.minY) + ScrollEdgeFade.fadeLength
        if abs(collectionView.contentInset.bottom - inset) > 0.5 {
            collectionView.contentInset.bottom = inset
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        commitPendingClear()
    }

    // MARK: - Build

    private func buildSheet() {
        titleLabel.text = "History"
        titleLabel.font = TypographyV2.headlineMedium.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        spinner.color = Theme.primary
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        // Same primary Explore capsule as the Playlist empty state.
        exploreButton.configuration = AnycastButton.configuration(.primary, title: "Explore", image: AppIcons.explore)
        exploreButton.addPressFeedback(scale: Motion.pressScaleSubtle)
        exploreButton.accessibilityLabel = "Explore"
        exploreButton.accessibilityIdentifier = "history-explore"
        exploreButton.addAction(UIAction { [weak self] _ in self?.exploreTapped() }, for: .touchUpInside)

        emptyView.isHidden = true
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyView)

        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        buildFooter()

        let footerBottom = footerStack.bottomAnchor.constraint(
            equalTo: view.bottomAnchor, constant: -Spacing.sheetContent
        )
        footerBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Spacing.sheetContent),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.sheetContent),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.sheetContent),

            // Runs under the title row (content fades out behind it);
            // `viewDidLayoutSubviews` keeps the resting first row in place.
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            emptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            // 28 from the view's bottom edge, but never closer than md to the
            // safe-area bottom (home-indicator devices keep the 28).
            footerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.sheetContent),
            footerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.sheetContent),
            footerStack.bottomAnchor.constraint(
                lessThanOrEqualTo: view.bottomAnchor, constant: -Spacing.sheetContent
            ),
            footerStack.bottomAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Spacing.md
            ),
            footerBottom,

            bottomFade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomFade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomFade.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomFade.topAnchor.constraint(
                equalTo: footerStack.topAnchor, constant: -ScrollEdgeFade.fadeLength
            ),
        ])
        ScrollEdgeChrome.attachTopBand(
            to: collectionView, in: view, below: titleLabel.bottomAnchor, restingGap: Spacing.gap
        )
        ScrollEdgeChrome.attachBottomEdge(to: collectionView, in: view)
        view.bringSubviewToFront(titleLabel)
        renderEmptyState()
    }

    /// The pinned footer: one stack holding the three mutually exclusive
    /// controls (hold / undo / confirm); `renderStates` shows exactly one.
    private func buildFooter() {
        holdButton.onConfirm = { [weak self] in self?.beginPendingClear() }
        holdButton.onConfirmRequested = { [weak self] in
            guard self?.footerState == .hold else { return }
            self?.setFooterState(.confirm)
        }

        var undoConfiguration = UIButton.Configuration.filled()
        undoConfiguration.title = "Undo"
        undoConfiguration.baseBackgroundColor = AnycastColor.sandAlpha4
        undoConfiguration.baseForegroundColor = Theme.onSurface
        undoConfiguration.cornerStyle = .capsule
        undoConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: Spacing.gap, leading: Spacing.cardInner, bottom: Spacing.gap, trailing: Spacing.cardInner
        )
        undoConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.emphasis.font()
            return outgoing
        }
        undoButton.configuration = undoConfiguration
        undoButton.titleLabel?.adjustsFontForContentSizeCategory = true
        undoButton.accessibilityIdentifier = "history-undo"
        undoButton.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)

        // Assistive-tech path: an inline confirm instead of the hold gesture.
        confirmLabel.font = TypographyV2.body.font()
        confirmLabel.textColor = Theme.onSurface
        confirmLabel.textAlignment = .center
        confirmLabel.numberOfLines = 0
        confirmLabel.adjustsFontForContentSizeCategory = true

        let cancel = AnycastButton.make(.secondary, title: "Cancel")
        cancel.addAction(UIAction { [weak self] _ in self?.setFooterState(.hold) }, for: .touchUpInside)
        let clear = AnycastButton.make(.destructive, title: "Clear")
        clear.addAction(UIAction { [weak self] _ in self?.beginPendingClear() }, for: .touchUpInside)
        let buttonRow = UIStackView(arrangedSubviews: [cancel, clear])
        buttonRow.axis = .horizontal
        buttonRow.spacing = Spacing.md
        buttonRow.distribution = .fillEqually

        confirmStack.axis = .vertical
        confirmStack.spacing = Spacing.gap
        confirmStack.addArrangedSubview(confirmLabel)
        confirmStack.addArrangedSubview(buttonRow)

        for button in [undoButton, cancel, clear] {
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        }

        footerStack.axis = .vertical
        for arranged in [holdButton, undoButton, confirmStack] {
            footerStack.addArrangedSubview(arranged)
        }
        footerStack.isHidden = true
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        bottomFade.isHidden = true
        view.addSubview(bottomFade)
        view.addSubview(footerStack)
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
    /// starting at the text column. Day headers are display-only and scroll
    /// with the rows: the plain list style pins them, so each section's
    /// header is unpinned here.
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
        return UICollectionViewCompositionalLayout { _, environment in
            let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
            for supplementary in section.boundarySupplementaryItems {
                supplementary.pinToVisibleBounds = false
            }
            return section
        }
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
        // Rows are keyed by enclosure URL; a replay keeps the key but changes
        // the play time, so existing cells must be reconfigured, not reused.
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
        renderStates()
    }

    private func renderStates() {
        spinner.isHidden = !isLoading
        if isLoading { spinner.startAnimating() } else { spinner.stopAnimating() }
        let isEmpty = !isLoading && episodes.isEmpty
        renderEmptyState()
        emptyView.isHidden = !isEmpty
        collectionView.isHidden = isLoading || isEmpty
        syncFooterState()
    }

    /// "History cleared" while a clear is pending or has committed in this
    /// presentation; otherwise the shared empty block with Explore.
    private func renderEmptyState() {
        if didClear {
            emptyView.configure(.init(
                icon: AppIcons.check,
                title: "History cleared",
                message: "Episodes you play show up here."
            ))
        } else {
            emptyView.configure(.init(
                icon: UIImage(systemName: "clock.arrow.circlepath"),
                title: "Play an episode and it shows up here.",
                actions: [exploreButton]
            ))
        }
    }

    // MARK: - Footer

    /// The footer follows the data: Undo while a clear is pending, nothing
    /// while loading or empty, otherwise Hold (or the inline confirm).
    private func syncFooterState() {
        let next: FooterState
        if hasPendingClear {
            next = .undo
        } else if isLoading || episodes.isEmpty {
            next = .hidden
        } else if footerState == .confirm {
            next = .confirm
        } else {
            next = .hold
        }
        setFooterState(next)
    }

    private func setFooterState(_ state: FooterState) {
        let previous = footerState
        footerState = state
        footerStack.isHidden = state == .hidden
        bottomFade.isHidden = state == .hidden
        holdButton.isHidden = state != .hold
        undoButton.isHidden = state != .undo
        confirmStack.isHidden = state != .confirm
        if state == .hold && previous != .hold { holdButton.reset() }
        if state == .confirm {
            let count = episodes.count
            confirmLabel.text = "Clear \(count) \(count == 1 ? "episode" : "episodes") from History?"
            if previous != .confirm {
                UIAccessibility.post(notification: .layoutChanged, argument: confirmLabel)
            }
        }
        view.setNeedsLayout()
    }

    // MARK: - Data

    /// Re-reads the list. A pending clear owns the (empty) list until it
    /// is undone or committed.
    private func reload() async {
        guard !hasPendingClear else { return }
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

    // MARK: - Clear All (deferred delete + Undo)

    /// Empties the list but leaves the DB alone; the delete runs when the
    /// Undo window ends, or earlier on dismissal / backgrounding.
    func beginPendingClear() {
        guard !hasPendingClear, !episodes.isEmpty else { return }
        pendingURLs = episodes.compactMap(\.enclosureUrl)
        pendingClearStartedAt = Int64(Date().timeIntervalSince1970 * 1000)
        hasPendingClear = true
        didClear = true
        episodes = []
        applySnapshot()
        commitTask = Task { [weak self, undoWindow] in
            try? await Task.sleep(for: undoWindow)
            guard !Task.isCancelled else { return }
            self?.commitPendingClear()
        }
    }

    /// Cancels the pending delete and re-reads the (never touched) DB.
    func undoPendingClear() async {
        guard hasPendingClear else { return }
        commitTask?.cancel()
        commitTask = nil
        pendingURLs = []
        hasPendingClear = false
        didClear = false
        holdButton.reset()
        await reload()
    }

    /// Writes the pending delete. State is cleared first so a second call
    /// (timer, disappearance, backgrounding) cannot commit twice; the write
    /// captures the repository, not self, so it finishes after dismissal.
    func commitPendingClear() {
        guard hasPendingClear else { return }
        let urls = pendingURLs
        let startedAt = pendingClearStartedAt
        pendingURLs = []
        hasPendingClear = false
        commitTask?.cancel()
        commitTask = nil
        syncFooterState()
        let repository = database.historyRepository()
        Task { [weak self] in
            do {
                try await repository.deleteMany(urls, notPlayedSince: startedAt)
            } catch {
                self?.didClear = false
                await self?.reload()
            }
        }
    }

    // MARK: - Actions

    @objc private func undoTapped() {
        Task { await undoPendingClear() }
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
        HistoryEpisodeActions.presentDetail(
            episode, from: self, context: context,
            // `playByEpisode` awaits the history write before it returns,
            // so the replayed row is on top at reload.
            didPlay: { [weak self] in await self?.reload() },
            remove: { [weak self] url in self?.deleteEpisode(url: url) }
        )
    }
}

// MARK: - Row cell

/// One history row: 44 pt rounded cover, one-line title, "2h ago · Show" meta.
final class HistoryRowCell: UICollectionViewListCell {

    static let reuseIdentifier = "HistoryRowCell"

    static let coverSize: CGFloat = 44
    /// Where the text column (and the row separator) starts.
    static let textColumnLeading = textColumnLeading(inset: Spacing.sheetContent)

    /// Where the text column starts when the row's content is inset
    /// `inset` from the cell edge.
    static func textColumnLeading(inset: CGFloat) -> CGFloat {
        inset + coverSize + Spacing.gap
    }

    /// Cover and text sit this far inside the cell. The History sheet's
    /// rows run edge to edge (28); the Library's sit on a plate (16).
    var horizontalInset: CGFloat = Spacing.sheetContent {
        didSet {
            coverLeading?.constant = horizontalInset
            textTrailing?.constant = -horizontalInset
        }
    }
    private var coverLeading: NSLayoutConstraint?
    private var textTrailing: NSLayoutConstraint?

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
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.adjustsFontForContentSizeCategory = true

        channelLabel.font = TypographyV2.meta.font()
        channelLabel.textColor = Theme.onSurfaceVariant
        channelLabel.lineBreakMode = .byTruncatingTail
        channelLabel.adjustsFontForContentSizeCategory = true

        applyLineLimit()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (cell: HistoryRowCell, _) in
            cell.applyLineLimit()
        }

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, channelLabel])
        textColumn.axis = .vertical
        textColumn.spacing = Spacing.xxs
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textColumn)

        let coverLeading = coverView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor, constant: horizontalInset
        )
        let textTrailing = textColumn.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor, constant: -horizontalInset
        )
        self.coverLeading = coverLeading
        self.textTrailing = textTrailing
        NSLayoutConstraint.activate([
            coverLeading,
            textTrailing,
            coverView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: Self.coverSize),
            coverView.heightAnchor.constraint(equalToConstant: Self.coverSize),

            textColumn.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: Spacing.gap),
            textColumn.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: Spacing.row),
            textColumn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])
    }

    /// One line each by default. At accessibility text sizes a single line
    /// leaves only a word or two, so the text wraps instead.
    private func applyLineLimit() {
        let lines = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 0 : 1
        titleLabel.numberOfLines = lines
        channelLabel.numberOfLines = lines
    }

    func configure(_ episode: HistoryEpisodeRow, now: Date = Date()) {
        let url = episode.imageUrl.flatMap(URL.init(string:))
        coverView.setArtwork(url, title: episode.channelTitle, side: Self.coverSize)
        titleLabel.text = episode.title ?? ""
        let subtitle = HistoryPresentation.subtitle(
            channel: episode.channelTitle, lastPlayedAt: episode.lastPlayedAt, now: now
        )
        channelLabel.text = subtitle
        channelLabel.isHidden = subtitle.isEmpty
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = HistoryPresentation.accessibilityLabel(
            title: episode.title, channel: episode.channelTitle,
            lastPlayedAt: episode.lastPlayedAt, now: now
        )
        // Swipe-to-delete has a VoiceOver twin.
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
