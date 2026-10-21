import UIKit
import Kingfisher
import AnycastKit

/// History (playlists.dart:240-421 `HistoryBlock`, opened from Settings and
/// the Inbox tail) as a system page sheet in the Anycast 2.0 list language
/// (09 §7a-C4: the Get.dialog card becomes a sheet): a centred "History"
/// title and flat rows — 44 pt cover, one-line title, show name — that swipe
/// to delete; tap opens Detail. Clear All lives at the bottom as a
/// hold-to-confirm button (the Dart source cleared without asking): the clear
/// is deferred for a 5 s Undo window and the DB is only written when it ends
/// (or the sheet disappears / the app backgrounds), so Undo is a plain
/// re-read. VoiceOver and Switch Control skip the hold for an inline
/// Cancel / Clear confirm. Empty state is the shared empty block; loading a
/// spinner. Settings presents this controller BY NAME via
/// `HistoryDialogViewController(context:)`.
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
    private var commitTask: Task<Void, Never>?
    /// Block-API observer token — touched only on the main thread;
    /// `nonisolated(unsafe)` because deinit is nonisolated.
    private nonisolated(unsafe) var backgroundObserver: NSObjectProtocol?

    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!

    private let titleLabel = UILabel()
    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let emptyView = EmptyStateView()
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
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(controller, animated: true)
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
        titleLabel.font = TypographyV2.headlineSmall.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        spinner.color = Theme.primary
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

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
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Spacing.pageHeader),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.sheetContent),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.sheetContent),

            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Spacing.gap),
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
        renderEmptyState()
    }

    /// The pinned footer: one stack holding the three mutually exclusive
    /// controls (hold / undo / confirm); `render` shows exactly one.
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
            outgoing.font = TypographyV2.headlineSmall.font()
            return outgoing
        }
        undoButton.configuration = undoConfiguration
        undoButton.titleLabel?.adjustsFontForContentSizeCategory = true
        undoButton.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)

        // Assistive-tech path: an inline confirm instead of the hold gesture.
        confirmLabel.font = TypographyV2.bodyMedium.font()
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
        dataSource = UICollectionViewDiffableDataSource<Int, String>(
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
                self?.delete(url: enclosureURL)
            }
            cell.onTap = { [weak self] in
                self?.presentDetail(episode)
            }
            return cell
        }
    }

    /// A plain list section: rows swipe to delete, hairlines only between
    /// rows, starting at the text column.
    private func makeLayout() -> UICollectionViewCompositionalLayout {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = true
        configuration.backgroundColor = .clear
        configuration.itemSeparatorHandler = { [weak self] indexPath, sectionSeparator in
            var separator = sectionSeparator
            separator.topSeparatorVisibility = .hidden
            let isLast = indexPath.item >= (self?.episodes.count ?? 0) - 1
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
                self?.delete(url: url)
                completion(true)
            }
            delete.image = AppIcons.delete
            return UISwipeActionsConfiguration(actions: [delete])
        }
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(episodes.compactMap(\.enclosureUrl))
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
    /// presentation; otherwise the plain "No history" block.
    private func renderEmptyState() {
        emptyView.configure(.init(
            icon: didClear ? AppIcons.check : UIImage(systemName: "clock.arrow.circlepath"),
            title: didClear ? "History cleared" : "No history",
            message: "Episodes you play show up here."
        ))
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

    // MARK: - Data (HistoryRepository — "latest" is ORDER BY id DESC, K12)

    private func reload() async {
        episodes = (try? await database.historyRepository().listAll()) ?? []
        isLoading = false
        applySnapshot()
    }

    private func delete(url: String) {
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
        pendingURLs = []
        hasPendingClear = false
        commitTask?.cancel()
        commitTask = nil
        syncFooterState()
        let repository = database.historyRepository()
        Task { [weak self] in
            do {
                try await repository.deleteMany(urls)
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
}

// MARK: - Row tap → Detail (playlists.dart:260-288)

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
                    // toFeedEpisode → addToTop(1, ep) → playByEpisode
                    // (playlists.dart:270-279).
                    Task { await self?.playFromHistory(episode) }
                },
                EpisodeCardAction(
                    icon: AppIcons.remove,
                    accessibilityLabel: "Remove"
                ) { [weak self] in
                    guard let url = episode.enclosureUrl else { return }
                    self?.delete(url: url)
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

// MARK: - Row cell (playlists.dart:248-355)

/// One history row: 44 pt rounded cover, one-line title, show name.
final class HistoryRowCell: UICollectionViewListCell {

    static let reuseIdentifier = "HistoryRowCell"

    private static let coverSize: CGFloat = 44
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

        titleLabel.font = TypographyV2.headlineSmall.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.adjustsFontForContentSizeCategory = true

        channelLabel.font = TypographyV2.bodyMedium.font()
        channelLabel.textColor = Theme.onSurfaceVariant
        channelLabel.numberOfLines = 1
        channelLabel.lineBreakMode = .byTruncatingTail
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

            textColumn.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: Spacing.gap),
            textColumn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.sheetContent),
            textColumn.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: Spacing.row),
            textColumn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])
    }

    func configure(_ episode: HistoryEpisodeRow) {
        let url = episode.imageUrl.flatMap(URL.init(string:))
        coverView.setArtwork(url, title: episode.channelTitle)
        titleLabel.text = episode.title ?? ""
        channelLabel.text = episode.channelTitle ?? ""
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = "\(episode.title ?? ""), \(episode.channelTitle ?? "")"
        // Swipe-to-delete has a VoiceOver twin.
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Delete") { [weak self] _ in
                self?.onDelete?()
                return true
            }
        ]
    }

    override func accessibilityActivate() -> Bool {
        // Row tap opens the Detail sheet (playlists.dart:260-288).
        onTap?()
        return true
    }
}
