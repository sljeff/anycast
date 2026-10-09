import UIKit
import AnycastKit

/// One Discover category page (discover.dart:56-103): the per-category
/// `listChannelsByCategoryId` PodcastCard list with a loading spinner and
/// the centered "Network Error" state. No pull-to-refresh (03 §3.3).
@MainActor
final class DiscoverCategoryPageViewController: UIViewController, UICollectionViewDataSource {

    private let context: UIContext
    private let model: DiscoverCategoryPageModel

    private let collectionView: UICollectionView
    private let spinner = UIActivityIndicatorView(style: .large)
    private let errorLabel = UILabel()
    private let observation = ObservationLoop()
    private var lastChannelSignature: [String?] = []

    init(context: UIContext, model: DiscoverCategoryPageModel) {
        self.context = context
        self.model = model

        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(PodcastCardCell.cardHeight)
                )
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: item.layoutSize, subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            // ListView.separated + PodcastCard margins (discover.dart:87-99):
            // pageH 16 sides, gap 12 top, pageBottomSafe 88 bottom.
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 12, leading: 16, bottom: 88, trailing: 16
            )
            section.interGroupSpacing = PodcastCardCell.spacing
            return section
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        build()

        observation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.model.isLoading
                _ = self.model.failed
                _ = self.model.channels
            },
            onChange: { [weak self] in self?.render() }
        )
        render()
        // NOTE: the fetch is NOT started here — the tab drives it through
        // DiscoverViewModel.selectCategory (the PageView first-display
        // equivalent); UIKit appearance would also fire for offscreen
        // installed neighbor pages.
    }

    // MARK: - Build

    private func build() {
        collectionView.backgroundColor = .clear
        collectionView.keyboardDismissMode = .interactive
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.dataSource = self
        collectionView.register(
            PodcastCardCell.self, forCellWithReuseIdentifier: PodcastCardCell.reuseIdentifier
        )
        view.addSubview(collectionView)

        spinner.color = Theme.primary
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        // Centered white "Network Error" (discover.dart:73-78).
        errorLabel.text = "Network Error"
        errorLabel.textColor = Theme.secondaryText
        errorLabel.font = Typography.secondaryTitle.font()
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.textAlignment = .center
        errorLabel.isHidden = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Rendering (plain no-animation rebuild, 08 §7.2)

    private func render() {
        switch model.phase {
        case .loading:
            spinner.startAnimating()
            errorLabel.isHidden = true
        case .networkError:
            spinner.stopAnimating()
            errorLabel.isHidden = false
        case .loaded:
            spinner.stopAnimating()
            errorLabel.isHidden = true
        }

        let signature = model.channels.map(\.rssFeedUrl)
        if signature != lastChannelSignature {
            lastChannelSignature = signature
            UIView.performWithoutAnimation {
                collectionView.reloadData()
            }
        }
    }

    // MARK: - UICollectionViewDataSource

    func collectionView(
        _ collectionView: UICollectionView, numberOfItemsInSection section: Int
    ) -> Int {
        model.channels.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PodcastCardCell.reuseIdentifier, for: indexPath
        ) as! PodcastCardCell
        if model.channels.indices.contains(indexPath.item) {
            let channel = model.channels[indexPath.item]
            cell.configure(
                PodcastCardContent(
                    rssFeedURL: channel.rssFeedUrl ?? "",
                    title: channel.title ?? "",
                    description: channel.description ?? "",
                    imageURL: channel.imageUrl
                )
            )
            // PodcastCard tap → Channel sheet (card.dart:330-342); the card
            // row seeds the channel header immediately.
            cell.onTap = { [weak self] content in
                guard let self else { return }
                let seed = SubscriptionRow(
                    rssFeedUrl: content.rssFeedURL,
                    title: content.title,
                    description: content.description,
                    imageUrl: content.imageURL
                )
                ChannelViewController.present(
                    from: self,
                    context: self.context,
                    rssFeedURL: content.rssFeedURL,
                    seed: seed
                )
            }
        }
        return cell
    }
}
