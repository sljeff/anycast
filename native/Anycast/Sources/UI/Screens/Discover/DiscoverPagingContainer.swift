import UIKit

/// Resident child pages in a horizontal paging scroll view — the
/// DefaultTabController TabBarView equivalent for the Discover category
/// pages and the SearchPage tabs (03 §2.6/§3.5): all page slots exist up
/// front, view controllers install lazily and never leave (KeepAliveWrapper
/// parity), taps call `select`, swipes sync through `onSwipeSelect`, and a
/// drag toward a not-yet-installed page reports through `onScrub` so the
/// owner can materialize it mid-gesture (the Flutter PageView builds the
/// adjacent page while it is being dragged in).
@MainActor
final class DiscoverPagingContainer: UIViewController, UIScrollViewDelegate {

    /// A swipe settled on (or a drag is heading toward) this index.
    var onSwipeSelect: ((Int) -> Void)?
    /// The nearest page changed while the user is dragging toward it.
    var onScrub: ((Int) -> Void)?

    private let scrollView = UIScrollView()
    private var slots: [UIView] = []
    private var installedPages: [Int: UIViewController] = [:]
    private(set) var selectedIndex = 0
    private var isProgrammaticScroll = false
    private var lastScrubIndex = -1

    init(pageCount: Int) {
        super.init(nibName: nil, bundle: nil)
        precondition(pageCount >= 1, "DiscoverPagingContainer needs at least one page")

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        for _ in 0..<pageCount {
            let slot = UIView()
            slot.backgroundColor = .clear
            slot.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(slot)
            slots.append(slot)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        for (index, slot) in slots.enumerated() {
            NSLayoutConstraint.activate([
                slot.leadingAnchor.constraint(
                    equalTo: index == 0
                        ? scrollView.contentLayoutGuide.leadingAnchor
                        : slots[index - 1].trailingAnchor
                ),
                slot.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
                // Vertical size must come from the FRAME guide. Pinning to the
                // content guide's top/bottom leaves the slot's height
                // unconstrained, and the page collapses to zero height (the
                // M3 snapshot pass caught the resulting blank tab).
                slot.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor),
                slot.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            ])
        }
        slots.last?.trailingAnchor.constraint(
            equalTo: scrollView.contentLayoutGuide.trailingAnchor
        ).isActive = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Keep the selected page correct through window resizing without
        // signaling a user swipe.
        if !scrollView.isTracking && !scrollView.isDragging && !scrollView.isDecelerating {
            let target = CGFloat(selectedIndex) * scrollView.bounds.width
            if scrollView.bounds.width > 0, abs(scrollView.contentOffset.x - target) > 0.5 {
                scrollView.setContentOffset(CGPoint(x: target, y: 0), animated: false)
            }
        }
    }

    // MARK: - Page management

    /// Installs a page permanently (KeepAliveWrapper: pages never uninstall).
    func install(_ page: UIViewController, at index: Int) {
        guard slots.indices.contains(index), installedPages[index] == nil else { return }
        installedPages[index] = page
        addChild(page)
        let slot = slots[index]
        slot.addSubview(page.view)
        page.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            page.view.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
            page.view.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
            page.view.topAnchor.constraint(equalTo: slot.topAnchor),
            page.view.bottomAnchor.constraint(equalTo: slot.bottomAnchor),
        ])
        page.didMove(toParent: self)
    }

    func select(_ index: Int, animated: Bool) {
        guard slots.indices.contains(index) else { return }
        selectedIndex = index
        lastScrubIndex = index
        guard scrollView.bounds.width > 0 else { return }
        let target = CGPoint(x: CGFloat(index) * scrollView.bounds.width, y: 0)
        isProgrammaticScroll = true
        scrollView.setContentOffset(target, animated: animated)
        if !animated {
            isProgrammaticScroll = false
        }
    }

    // MARK: - UIScrollViewDelegate (swipe sync + drag scrubbing)

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // A touch interrupting a programmatic setContentOffset animation
        // stops it without scrollViewDidEndScrollingAnimation ever firing;
        // without this reset the flag sticks true and swipe sync (scrub +
        // settle events) stays dead until the next strip tap.
        isProgrammaticScroll = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isProgrammaticScroll,
              scrollView.isTracking || scrollView.isDragging,
              scrollView.bounds.width > 0
        else { return }
        let index = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        guard slots.indices.contains(index), index != lastScrubIndex else { return }
        lastScrubIndex = index
        onScrub?(index)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        syncFromScroll()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        // A drag released with ~zero velocity exactly at a page boundary
        // never decelerates — without this settle the selected index stays
        // stale and the next layout pass snaps the scroll view back.
        if !willDecelerate {
            syncFromScroll()
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isProgrammaticScroll = false
    }

    private func syncFromScroll() {
        guard !isProgrammaticScroll, scrollView.bounds.width > 0 else { return }
        let index = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        guard slots.indices.contains(index) else { return }
        // Always report: a drag that scrubbed a strip update and returned
        // still owes a settle event so the strip lands on the real page.
        selectedIndex = index
        lastScrubIndex = index
        onSwipeSelect?(index)
    }
}
