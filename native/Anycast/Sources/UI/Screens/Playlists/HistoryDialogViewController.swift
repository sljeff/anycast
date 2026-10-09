import UIKit
import Kingfisher
import MarqueeLabel
import AnycastKit

/// The history dialog (playlists.dart:240-421 `HistoryBlock`, opened from
/// Settings via Get.dialog): a centered 300×400 dark card over a dimmed
/// barrier. Rows carry a 48×48 cover, an ALWAYS-scrolling marquee title
/// (startAfter 1 s — K33's always-scroll ruling for the history list), a
/// green channel name, and a white circular delete button; the bottom is a
/// red "Clear All" (the Dart source has NO confirmation step). Empty state
/// is the "No history" alert-style card; loading is a centered spinner.
/// The Settings screen presents this controller BY NAME via
/// `HistoryDialogViewController(context:)`.
@MainActor
final class HistoryDialogViewController: UIViewController {

    private let context: UIContext

    private(set) var episodes: [HistoryEpisodeRow] = []
    private var isLoading = true

    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!

    private let dimmingView = UIControl()
    private let cardView = UIView()
    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let emptyLabel = UILabel()
    private let clearAllButton = UIButton(type: .system)

    private var cardHeightConstraint: NSLayoutConstraint!
    private var cardWidthConstraint: NSLayoutConstraint!

    /// Get.dialog presentation: dimmed over-current-context, centered card.
    static func present(from presenter: UIViewController, context: UIContext) {
        let controller = HistoryDialogViewController(context: context)
        controller.modalPresentationStyle = .overCurrentContext
        controller.modalTransitionStyle = .crossDissolve
        controller.modalPresentationCapturesStatusBarAppearance = false
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
        buildDialog()
        configureDataSource()
        Task { await reload() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 300×400 scaled to survive any window geometry (07 §4: bounds
        // math, never screen-width calculations). Floor at 0: a transient
        // layout pass with bounds < 32 must not produce negative
        // constraints.
        let width = max(0, min(300, view.bounds.width - 32))
        let height = max(0, min(400, view.bounds.height - 32))
        cardWidthConstraint.constant = width
        cardHeightConstraint.constant = height
    }

    // MARK: - Build

    private func buildDialog() {
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.54)
        dimmingView.addTarget(self, action: #selector(dismissDialog), for: .touchUpInside)
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimmingView)

        cardView.backgroundColor = Theme.primaryBackgroundDark
        cardView.layer.cornerRadius = 12
        cardView.layer.cornerCurve = .continuous
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        spinner.color = Theme.primary
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(spinner)

        // The empty branch is the Dart `AlertDialog(title: Text('No history'))`.
        emptyLabel.text = "No history"
        emptyLabel.font = Typography.secondaryTitle.font()
        emptyLabel.textColor = Theme.primary
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 1
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(emptyLabel)

        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(collectionView)

        var clearConfiguration = UIButton.Configuration.filled()
        clearConfiguration.attributedTitle = AttributedString(
            "Clear All", attributes: AttributeContainer([
                .font: Typography.defaultText.font(),
                .foregroundColor: UIColor.white,
            ])
        )
        clearConfiguration.baseBackgroundColor = UIColor(red: 0xEF / 255, green: 0x53 / 255, blue: 0x50 / 255, alpha: 1)
        clearConfiguration.background.cornerRadius = 12
        clearAllButton.configuration = clearConfiguration
        clearAllButton.addTarget(self, action: #selector(clearAllTapped), for: .touchUpInside)
        clearAllButton.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(clearAllButton)

        cardWidthConstraint = cardView.widthAnchor.constraint(equalToConstant: 300)
        cardHeightConstraint = cardView.heightAnchor.constraint(equalToConstant: 400)

        NSLayoutConstraint.activate([
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardWidthConstraint,
            cardHeightConstraint,

            collectionView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            collectionView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            collectionView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            collectionView.bottomAnchor.constraint(equalTo: clearAllButton.topAnchor, constant: -12),

            clearAllButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            clearAllButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            clearAllButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
            clearAllButton.heightAnchor.constraint(equalToConstant: 40),

            spinner.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
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
            cell.onDeleteTap = { [weak self] in
                self?.delete(url: enclosureURL)
            }
            cell.onTap = { [weak self] in
                self?.presentDetail(episode)
            }
            return cell
        }
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(HistoryRowCell.rowHeight)
                )
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: item.layoutSize, subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 12
            return section
        }
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
        emptyLabel.isHidden = !isEmpty
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

    @objc private func dismissDialog() {
        dismiss(animated: true)
    }

    /// The Dart source clears with NO confirmation (controller.deleteAll()).
    @objc private func clearAllTapped() {
        let urls = episodes.compactMap(\.enclosureUrl)
        episodes = []
        applySnapshot()
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

/// One history row: 48×48 rounded-8 cover, always-scrolling marquee title,
/// green channel name, white circular delete.
final class HistoryRowCell: UICollectionViewCell {

    static let reuseIdentifier = "HistoryRowCell"
    static let rowHeight: CGFloat = 72   // 48pt cover + 12pt padding ×2

    var onDeleteTap: (() -> Void)?
    var onTap: (() -> Void)?

    private let container = UIView()
    private let coverView = UIImageView()
    private let titleLabel = MarqueeLabelFactory.makeHistoryTitle(
        font: Typography.cardTitleBold.font(), textColor: Theme.primaryLightMax
    )
    private let channelLabel = UILabel()
    private let deleteButton = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onDeleteTap = nil
        onTap = nil
        coverView.kf.cancelDownloadTask()
    }

    private func build() {
        contentView.backgroundColor = .clear

        container.backgroundColor = Theme.cardBackground
        container.layer.borderColor = Theme.cardOutline.cgColor
        container.layer.borderWidth = 1
        container.layer.cornerRadius = 12
        container.layer.cornerCurve = .continuous
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 8
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.primaryBackground
        coverView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(coverView)

        channelLabel.font = Typography.defaultText.font()
        channelLabel.textColor = Theme.primary
        channelLabel.numberOfLines = 1
        channelLabel.adjustsFontForContentSizeCategory = true

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, channelLabel])
        textColumn.axis = .vertical
        textColumn.alignment = .fill
        textColumn.spacing = 4
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textColumn)

        deleteButton.setImage(AppIcons.close, for: .normal)
        deleteButton.tintColor = Theme.primaryBackgroundDark
        deleteButton.backgroundColor = Theme.primaryLightMax
        deleteButton.layer.cornerRadius = 20
        deleteButton.layer.cornerCurve = .continuous
        deleteButton.isAccessibilityElement = true
        deleteButton.accessibilityLabel = "Delete"
        deleteButton.addAction(
            UIAction { [weak self] _ in self?.onDeleteTap?() },
            for: .touchUpInside
        )
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            coverView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            coverView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            coverView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            coverView.widthAnchor.constraint(equalToConstant: 48),
            coverView.heightAnchor.constraint(equalToConstant: 48),

            textColumn.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 12),
            textColumn.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -12),
            textColumn.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            deleteButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            deleteButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 40),
            deleteButton.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    func configure(_ episode: HistoryEpisodeRow) {
        let url = episode.imageUrl.flatMap(URL.init(string:))
        coverView.kf.setImage(with: url, options: [.transition(.none)])
        titleLabel.text = episode.title ?? ""
        channelLabel.text = episode.channelTitle ?? ""
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = "\(episode.title ?? ""), \(episode.channelTitle ?? "")"
        // The cell is the row's single accessibility element, so the
        // 40 pt delete button folded into it is unreachable by VoiceOver —
        // expose it as a custom action (the reorder rows use the same
        // pattern).
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Delete") { [weak self] _ in
                self?.onDeleteTap?()
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
