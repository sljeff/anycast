import UIKit
import AnycastKit

/// One Discover category page (discover.dart:56-103): the per-category
/// `listChannelsByCategoryId` PodcastCard list with a loading spinner and
/// the centered "Network Error" state. No pull-to-refresh (03 §3.3).
@MainActor
final class DiscoverCategoryPageViewController: UIViewController, UICollectionViewDataSource, ScrollEdgePage {

    private let context: UIContext
    private let model: DiscoverCategoryPageModel

    private let collectionView: UICollectionView
    private let spinner = UIActivityIndicatorView(style: .large)
    private let subtleSpinner = UIActivityIndicatorView(style: .medium)
    private let skeleton = SkeletonListView(style: .channelRows)
    private var skeletonTop: NSLayoutConstraint?
    private let errorLabel = UILabel()
    private let observation = ObservationLoop()
    private var lastChannelSignature: [String?] = []

    init(context: UIContext, model: DiscoverCategoryPageModel) {
        self.context = context
        self.model = model

        // One grouped plate (discover.dart:87-99 margins: pageH 16 sides,
        // gap 12 top, pageBottomSafe 88 bottom).
        collectionView = UICollectionView(
            frame: .zero, collectionViewLayout: PodcastCardCell.makeGroupedLayout()
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var edgeScrollView: UIScrollView { collectionView }
    var topChromeInset: CGFloat = 0 {
        didSet { collectionView.contentInset.top = topChromeInset }
    }

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

        subtleSpinner.color = Theme.primary
        subtleSpinner.hidesWhenStopped = true
        subtleSpinner.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        subtleSpinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtleSpinner)

        skeleton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(skeleton)
        let skeletonTop = skeleton.topAnchor.constraint(equalTo: view.topAnchor)
        self.skeletonTop = skeletonTop

        // Centered white "Network Error" (discover.dart:73-78).
        errorLabel.text = "Network Error"
        errorLabel.textColor = Theme.onSurfaceVariant
        errorLabel.font = TypographyV2.emphasis.font()
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
            subtleSpinner.topAnchor.constraint(equalTo: skeleton.topAnchor),
            subtleSpinner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            skeletonTop,
            skeleton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skeleton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skeleton.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let top = collectionView.contentInset.top + Spacing.gap
        if skeletonTop?.constant != top { skeletonTop?.constant = top }
    }

    // MARK: - Rendering (plain no-animation rebuild, 08 §7.2)

    private func render() {
        let hasContent = !model.channels.isEmpty
        let loading = model.phase == .loading
        let chrome = MotionLoading.chrome(isLoading: loading, hasContent: hasContent)
        spinner.stopAnimating()
        if chrome.showSubtleIndicator { subtleSpinner.startAnimating() } else { subtleSpinner.stopAnimating() }
        switch model.phase {
        case .loading:
            errorLabel.isHidden = true
        case .networkError:
            errorLabel.isHidden = false
        case .loaded:
            errorLabel.isHidden = true
        }

        let hadContent = !lastChannelSignature.isEmpty
        let signature = model.channels.map(\.rssFeedUrl)
        let signatureChanged = signature != lastChannelSignature
        if signatureChanged {
            lastChannelSignature = signature
            UIView.performWithoutAnimation {
                collectionView.reloadData()
            }
        }
        let reveal = signatureChanged && !hadContent && !signature.isEmpty
        if reveal {
            MotionArrival.reveal(
                in: collectionView,
                cells: [],
                skeleton: skeleton,
                staggered: true
            )
        } else if chrome.showSkeleton {
            skeleton.setShown(true)
        } else if !skeleton.isDismissing {
            skeleton.setShown(false)
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
            cell.setPosition(
                isFirst: indexPath.item == 0, isLast: indexPath.item == model.channels.count - 1
            )
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
