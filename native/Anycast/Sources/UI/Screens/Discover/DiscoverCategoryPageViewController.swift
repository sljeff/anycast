import UIKit
import AnycastKit

/// One Discover category page (discover.dart:56-103): the per-category
/// `listChannelsByCategoryId` PodcastCard list with a loading spinner and
/// the centered empty / failed state. No pull-to-refresh (03 §3.3).
@MainActor
final class DiscoverCategoryPageViewController: UIViewController, UICollectionViewDataSource, ScrollEdgePage {

    private let context: UIContext
    private let model: DiscoverCategoryPageModel

    private let collectionView: UICollectionView
    /// Genuinely empty ("No shows here for …") or failed ("Couldn’t load Discover." + Retry).
    private let errorState = EmptyStateView()
    /// "Couldn't update" + Retry, shown over kept content after a failed refresh.
    private let retryBar = UIStackView()
    private let skeletonDelay = LoadingDelay()
    private var showsSkeleton = false
    static let skeletonRowCount = 7
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
        didSet { applyTopInset() }
    }
    private var retryBarShown = false
    private static let retryBarHeight: CGFloat = 40

    private func applyTopInset(followsTop: Bool = false) {
        let wasAtTop = collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + 0.5
        collectionView.contentInset.top = topChromeInset + (retryBarShown ? Self.retryBarHeight : 0)
        retryBarTop?.constant = topChromeInset
        // A list resting at its top follows the new inset (the rows slide
        // down under the "Couldn't update" line instead of sitting behind it).
        if followsTop, wasAtTop {
            collectionView.contentOffset.y = -collectionView.adjustedContentInset.top
        }
    }
    private var retryBarTop: NSLayoutConstraint?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        build()

        observation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.model.isLoading
                _ = self.model.isFetching
                _ = self.model.updateFailed
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

        buildRetryBar()

        errorState.isHidden = true
        errorState.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(errorState)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorState.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func buildRetryBar() {
        let label = UILabel()
        label.text = "Couldn’t update"
        label.font = TypographyV2.meta.font()
        label.textColor = Theme.onSurfaceVariant
        label.adjustsFontForContentSizeCategory = true
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Retry"
        configuration.baseForegroundColor = Theme.onSurface
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.emphasis.font()
            return outgoing
        }
        let retry = UIButton(configuration: configuration)
        retry.tintColor = Theme.onSurface
        retry.accessibilityIdentifier = "discover-retry"
        retry.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.model.load(country: self.context.settingsBox.current.countryCode)
        }, for: .touchUpInside)
        retryBar.axis = .horizontal
        retryBar.alignment = .center
        retryBar.spacing = Spacing.sm
        retryBar.isLayoutMarginsRelativeArrangement = true
        retryBar.layoutMargins = UIEdgeInsets(top: 0, left: Spacing.pageH, bottom: 0, right: Spacing.xs)
        retryBar.addArrangedSubview(label)
        retryBar.addArrangedSubview(retry)
        retryBar.accessibilityIdentifier = "discover-update-failed"
        retryBar.isHidden = true
        retryBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(retryBar)
        let top = retryBar.topAnchor.constraint(equalTo: view.topAnchor, constant: topChromeInset)
        retryBarTop = top
        NSLayoutConstraint.activate([
            top,
            retryBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            retryBar.heightAnchor.constraint(equalToConstant: Self.retryBarHeight),
        ])
    }

    /// A failed load and a genuinely empty category read differently; only
    /// the failure offers Retry.
    private func configureErrorState() {
        if model.failed {
            let retry = AnycastButton.make(
                .secondary, title: "Retry", image: UIImage(systemName: "arrow.clockwise")
            )
            retry.accessibilityIdentifier = "discover-load-retry"
            retry.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.model.load(country: self.context.settingsBox.current.countryCode)
            }, for: .touchUpInside)
            errorState.configure(.init(title: "Couldn’t load Discover.", actions: [retry]))
        } else {
            let code = context.settingsBox.current.countryCode
            let region = Locale.current.localizedString(forRegionCode: code) ?? code
            errorState.configure(.init(title: "No shows here for \(region)."))
        }
    }

    // MARK: - Rendering (plain no-animation rebuild, 08 §7.2)

    private func render() {
        // The skeleton clock runs only while there is nothing to show and a
        // fetch is in flight.
        let waitingEmpty = model.isFetching && model.channels.isEmpty
        if waitingEmpty {
            skeletonDelay.start { [weak self] in self?.render() }
        } else {
            skeletonDelay.cancel()
        }
        let display = model.display(skeletonDue: skeletonDelay.isDue)

        errorState.isHidden = display != .emptyError
        if display == .emptyError { configureErrorState() }
        let shouldShowRetry = display == .contentWithRetry
        if shouldShowRetry != retryBarShown {
            retryBarShown = shouldShowRetry
            retryBar.isHidden = !shouldShowRetry
            applyTopInset(followsTop: true)
        }

        let skeleton = display == .skeleton
        let signature = model.channels.map(\.rssFeedUrl)
        let hadContent = !lastChannelSignature.isEmpty
        if signature != lastChannelSignature || skeleton != showsSkeleton {
            lastChannelSignature = signature
            let startsSkeleton = skeleton && !showsSkeleton
            showsSkeleton = skeleton
            UIView.performWithoutAnimation {
                collectionView.reloadData()
            }
            if startsSkeleton, !Motion.reduceMotion {
                collectionView.alpha = 0
                UIView.animate(withDuration: Motion.quick) { self.collectionView.alpha = 1 }
            } else {
                collectionView.alpha = 1
            }
            // The first channel arrival rises in after the reload; later
            // reloads stay plain.
            if !hadContent && !signature.isEmpty, view.window != nil {
                let cards = collectionView.visibleCells.filter { $0 is PodcastCardCell }
                MotionArrival.reveal(in: collectionView, cells: cards, staggered: true)
            }
        }
    }

    // MARK: - UICollectionViewDataSource

    func collectionView(
        _ collectionView: UICollectionView, numberOfItemsInSection section: Int
    ) -> Int {
        showsSkeleton ? Self.skeletonRowCount : model.channels.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PodcastCardCell.reuseIdentifier, for: indexPath
        ) as! PodcastCardCell
        if showsSkeleton {
            cell.setPosition(isFirst: indexPath.item == 0, isLast: indexPath.item == Self.skeletonRowCount - 1)
            cell.configureSkeleton()
            return cell
        }
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
