import UIKit
import Kingfisher
import AnycastKit

/// History (playlists.dart:240-421 `HistoryBlock`, opened from Settings and
/// the Inbox tail) as a system page sheet in the Anycast 2.0 list language
/// (09 §7a-C4: the Get.dialog card becomes a sheet): a "History" header
/// with Clear All (now behind a confirmation), and flat rows — 48 pt cover,
/// two-line title, show name — that swipe to delete; tap opens Detail.
/// Empty state is the shared empty block; loading a spinner. Settings
/// presents this controller BY NAME via `HistoryDialogViewController(context:)`.
@MainActor
final class HistoryDialogViewController: UIViewController {

    private let context: UIContext

    private(set) var episodes: [HistoryEpisodeRow] = []
    private var isLoading = true

    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!

    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let emptyView = EmptyStateView()
    private let clearAllButton = UIButton(type: .system)

    static func present(from presenter: UIViewController, context: UIContext) {
        let controller = HistoryDialogViewController(context: context)
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(controller, animated: true)
    }

    init(context: UIContext) {
        self.context = context
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

    // MARK: - Build

    private func buildSheet() {
        let titleLabel = UILabel()
        titleLabel.text = "History"
        titleLabel.font = TypographyV2.headlineMedium.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.adjustsFontForContentSizeCategory = true

        var clearConfiguration = UIButton.Configuration.plain()
        clearConfiguration.title = "Clear All"
        clearConfiguration.baseForegroundColor = Theme.error
        clearConfiguration.contentInsets = .zero
        clearAllButton.configuration = clearConfiguration
        clearAllButton.addTarget(self, action: #selector(clearAllTapped), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), clearAllButton])
        header.axis = .horizontal
        header.alignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        spinner.color = Theme.primary
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        emptyView.configure(.init(
            icon: UIImage(systemName: "clock.arrow.circlepath"),
            title: "No history",
            message: "Episodes you play show up here."
        ))
        emptyView.isHidden = true
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyView)

        collectionView.backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: Spacing.pageHeader),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: AnycastIconButton.standardDiameter),

            collectionView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Spacing.md),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyView.topAnchor.constraint(equalTo: header.bottomAnchor),
            emptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
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

    /// A plain list section: rows swipe to delete.
    private func makeLayout() -> UICollectionViewCompositionalLayout {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false
        configuration.backgroundColor = .clear
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
        emptyView.isHidden = !isEmpty
        collectionView.isHidden = isLoading || isEmpty
        clearAllButton.isHidden = isLoading || isEmpty
    }

    // MARK: - Data (HistoryRepository — "latest" is ORDER BY id DESC, K12)

    private func reload() async {
        episodes = (try? await context.database.historyRepository().listAll()) ?? []
        isLoading = false
        applySnapshot()
    }

    private func delete(url: String) {
        episodes.removeAll { $0.enclosureUrl == url }
        applySnapshot()
        Task { [weak self] in
            do {
                try await self?.context.database.historyRepository().deleteMany([url])
            } catch {
                // The DB is the source of truth: a failed write reverts the
                // optimistic row removal instead of silently diverging.
                await self?.reload()
            }
        }
    }

    // MARK: - Actions

    /// Clear All asks first (destructive account-level action; the Dart
    /// source cleared without asking).
    @objc private func clearAllTapped() {
        let alert = UIAlertController(
            title: "Clear all history?", message: "This removes every episode from your history.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { [weak self] _ in
            self?.clearAll()
        })
        present(alert, animated: true)
    }

    private func clearAll() {
        let urls = episodes.compactMap(\.enclosureUrl)
        episodes = []
        applySnapshot()
        Haptics.queueRemoved()
        Task { [weak self] in
            do {
                try await self?.context.database.historyRepository().deleteMany(urls)
            } catch {
                await self?.reload()
            }
        }
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

/// One history row: 48 pt rounded cover, two-line title, show name.
final class HistoryRowCell: UICollectionViewListCell {

    static let reuseIdentifier = "HistoryRowCell"

    var onDelete: (() -> Void)?
    var onTap: (() -> Void)?

    private let coverView = UIImageView()
    private let titleLabel = UILabel()
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
        coverView.layer.cornerRadius = Radius.md
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.surfaceContainerHigh
        coverView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(coverView)

        titleLabel.font = TypographyV2.cardTitle.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true

        channelLabel.font = TypographyV2.caption.font()
        channelLabel.textColor = Theme.onSurfaceVariant
        channelLabel.numberOfLines = 1
        channelLabel.adjustsFontForContentSizeCategory = true

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, channelLabel])
        textColumn.axis = .vertical
        textColumn.spacing = Spacing.xs
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textColumn)

        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.pageH),
            coverView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: 48),
            coverView.heightAnchor.constraint(equalToConstant: 48),
            coverView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: Spacing.md),

            textColumn.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: Spacing.gap),
            textColumn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.pageH),
            textColumn.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: Spacing.md),
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
