import UIKit
import AnycastKit

/// Tab 0 (lib/pages/podcasts.dart + widgets/appbar.dart, 03 §2.1/§2.2):
/// the AppBar (gradient PODCAST title, embedded search field, gear button)
/// over the Inbox/Subscriptions secondary tabs whose child controllers
/// stay resident (KeepAliveWrapper equivalent) and switch by tap or swipe.
@MainActor
final class PodcastsTabContainer: UIViewController {

    private let context: UIContext

    private let inbox: InboxPageViewController
    private let subscriptions: SubscriptionsPageViewController
    private var pagingContainer: PagingTabsContainer!
    private var tabStrip: PodcastsTabStrip!

    private let searchField = UITextField()
    private let cancelButton = UIButton(type: .system)

    init(context: UIContext) {
        self.context = context
        self.inbox = InboxPageViewController(context: context)
        self.subscriptions = SubscriptionsPageViewController(context: context)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)
        buildHeader()
        buildTabsAndPages()
    }

    // MARK: - AppBar (03 §2.2)

    private func buildHeader() {
        let title = GradientTextLabel()
        title.text = "PODCAST"

        let gear = UIButton(type: .custom)
        gear.setImage(AppIcons.settings, for: .normal)
        gear.tintColor = Theme.secondaryText
        gear.backgroundColor = Theme.cardBackground
        gear.layer.cornerRadius = 18
        gear.layer.cornerCurve = .continuous
        gear.isAccessibilityElement = true
        gear.accessibilityLabel = "Settings"
        gear.addAction(
            UIAction { [weak self] _ in self?.openSettings() },
            for: .touchUpInside
        )
        gear.widthAnchor.constraint(equalToConstant: 36).isActive = true
        gear.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let titleRow = UIStackView(arrangedSubviews: [title, gear])
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 12

        buildSearchRow()

        // The green Cancel sits BESIDE the field and collapses until text
        // exists (appbar.dart:120-143).
        cancelButton.isHidden = true
        let searchRow = UIStackView(arrangedSubviews: [searchField, cancelButton])
        searchRow.axis = .horizontal
        searchRow.alignment = .center
        searchRow.spacing = 12

        let header = UIStackView(arrangedSubviews: [titleRow, searchRow])
        header.axis = .vertical
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
    }

    private func buildSearchRow() {
        let icon = UIImageView(image: AppIcons.search)
        icon.tintColor = Theme.secondaryText
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        let iconBox = UIView()
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(icon)
        NSLayoutConstraint.activate([
            // The box needs its own explicit size: UITextField measures the
            // leftView through systemLayoutSizeFitting — with only inner
            // constraints the box resolves to 0×0 and the icon floats at
            // the field's top edge while the placeholder loses its inset.
            iconBox.widthAnchor.constraint(equalToConstant: 44),
            iconBox.heightAnchor.constraint(equalToConstant: 24),

            icon.leadingAnchor.constraint(equalTo: iconBox.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
        ])

        searchField.leftView = iconBox
        searchField.leftViewMode = .always
        searchField.placeholder = "Shows, episodes, and more"
        searchField.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 16)
        )
        searchField.adjustsFontForContentSizeCategory = true
        searchField.textColor = Theme.primaryLightMax
        searchField.attributedPlaceholder = NSAttributedString(
            string: searchField.placeholder ?? "",
            attributes: [.foregroundColor: Theme.hintGray]
        )
        searchField.backgroundColor = Theme.cardBackground
        searchField.layer.cornerRadius = 12
        searchField.layer.cornerCurve = .continuous
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.clearButtonMode = .whileEditing
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.heightAnchor.constraint(equalToConstant: 56).isActive = true
        searchField.addTarget(self, action: #selector(searchEditingChanged), for: .editingChanged)
        searchField.addTarget(self, action: #selector(searchSubmitted), for: .primaryActionTriggered)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(Theme.primary, for: .normal)
        cancelButton.titleLabel?.font = Typography.mainText.font()
        cancelButton.addAction(
            UIAction { [weak self] _ in self?.cancelSearch() },
            for: .touchUpInside
        )
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    @objc private func searchEditingChanged() {
        let hasText = !(searchField.text ?? "").isEmpty
        cancelButton.isHidden = !hasText
    }

    /// Non-empty submit opens the SearchPage sheet (appbar.dart:97-107;
    /// its 0.8 close threshold is an A3-accepted system default now).
    @objc private func searchSubmitted() {
        let text = (searchField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        AppSheets.presentExpand(
            SearchPageViewController(context: context, searchText: text),
            from: topMostPresented()
        )
    }

    /// Clears and unfocuses (appbar.dart:129-133).
    private func cancelSearch() {
        searchField.text = nil
        searchEditingChanged()
        searchField.resignFirstResponder()
    }

    private func openSettings() {
        AppSheets.presentExpand(SettingsViewController(context: context), from: topMostPresented())
    }

    // MARK: - Secondary tabs (03 §2.1)

    private func buildTabsAndPages() {
        tabStrip = PodcastsTabStrip(items: [
            PodcastsTabStrip.Item(title: "Inbox", icon: AppIcons.inbox),
            PodcastsTabStrip.Item(title: "Subscriptions", icon: AppIcons.subscriptions),
        ])
        tabStrip.translatesAutoresizingMaskIntoConstraints = false
        tabStrip.onSelect = { [weak self] index in
            self?.pagingContainer.select(index, animated: true)
        }
        view.addSubview(tabStrip)

        pagingContainer = PagingTabsContainer(children: [inbox, subscriptions])
        pagingContainer.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(pagingContainer)
        view.addSubview(pagingContainer.view)
        pagingContainer.didMove(toParent: self)
        pagingContainer.onSwipeSelect = { [weak self] index in
            self?.tabStrip.select(index, animated: true)
        }

        NSLayoutConstraint.activate([
            tabStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabStrip.topAnchor.constraint(
                equalTo: searchField.bottomAnchor, constant: 12
            ),
            tabStrip.heightAnchor.constraint(equalToConstant: 52),

            pagingContainer.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagingContainer.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagingContainer.view.topAnchor.constraint(equalTo: tabStrip.bottomAnchor),
            pagingContainer.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

/// The Inbox/Subscriptions strip: the main.dart TabBar theme — comfortaa
/// 12 pt labels, selected 0x6EE7B7, indicator under the LABEL's width
/// (indicatorSize: label), each tab icon-over-label. This is deliberately
/// NOT T0a's UnderlineTabBarView (OrderChooser visual: 24 pt white text,
/// fixed 48×4 indicator) — the two Dart strips differ, and the shared
/// component cannot be configured into this variant.
@MainActor
final class PodcastsTabStrip: UIView {

    struct Item {
        let title: String
        let icon: UIImage
    }

    var onSelect: ((Int) -> Void)?

    private let titles: [String]
    private var buttons: [UIButton] = []
    private let indicator = UIView()
    /// Constraint-driven placement: the width is the measured attributed
    /// title, the center follows the selected button — resolved by the
    /// layout engine, so it never depends on layoutSubviews ordering
    /// (frame-poking read the buttons before the stack had arranged them).
    private var indicatorWidth: NSLayoutConstraint!
    private var indicatorCenterX: NSLayoutConstraint?
    private(set) var selectedIndex = 0

    init(items: [Item]) {
        self.titles = items.map(\.title)
        super.init(frame: .zero)

        backgroundColor = .clear

        indicator.backgroundColor = Theme.tabSelectedGreen
        indicator.layer.cornerRadius = 1.5
        indicator.isUserInteractionEnabled = false
        indicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicator)
        indicatorWidth = indicator.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            indicatorWidth,
            indicator.heightAnchor.constraint(equalToConstant: 3),
            indicator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for (index, item) in items.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index

            var configuration = UIButton.Configuration.plain()
            var attributed = AttributedString(item.title)
            attributed.font = Typography.tabLabel.font()
            configuration.attributedTitle = attributed
            configuration.image = item.icon
            configuration.imagePadding = 4
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16)
            configuration.imagePlacement = .top
            button.configuration = configuration
            button.addAction(
                UIAction { [weak self] _ in self?.tapped(index: index) },
                for: .touchUpInside
            )
            stack.addArrangedSubview(button)
            buttons.append(button)
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        applySelection(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func select(_ index: Int, animated: Bool) {
        guard buttons.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        applySelection(animated: animated)
    }

    private func tapped(index: Int) {
        guard index != selectedIndex else { return }
        selectedIndex = index
        applySelection(animated: true)
        onSelect?(index)
    }

    private func applySelection(animated: Bool) {
        for (index, button) in buttons.enumerated() {
            let isSelected = index == selectedIndex
            var configuration = button.configuration ?? .plain()
            var attributed = AttributedString(titles[index])
            // configuration.attributedTitle is a whole-string replacement —
            // without re-attaching the font here the first selection change
            // drops Comfortaa and falls back to the system face.
            attributed.font = Typography.tabLabel.font()
            attributed.foregroundColor = isSelected
                ? Theme.tabSelectedGreen
                : Theme.secondaryLabelGray
            configuration.attributedTitle = attributed
            // baseForegroundColor tints the icon (the attributed title
            // overrides it for text).
            configuration.baseForegroundColor = isSelected
                ? Theme.tabSelectedGreen
                : Theme.secondaryLabelGray
            button.configuration = configuration
            button.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        }
        placeIndicator(animated: animated)
    }

    /// Indicator width == the selected button's title width, centered
    /// under it (main.dart TabBar theme: indicatorSize label). Constraints
    /// track rotations, Dynamic Type, and window resizing on their own.
    private func placeIndicator(animated: Bool) {
        guard buttons.indices.contains(selectedIndex) else { return }
        // The titles live in UIButton.Configuration.attributedTitle —
        // legacy titleLabel stays empty for configuration-based buttons,
        // so the width is measured from the attributed string itself.
        let attributed = NSAttributedString(
            string: titles[selectedIndex],
            attributes: [.font: Typography.tabLabel.font()]
        )
        let measured = attributed.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).width
        guard measured > 0 else { return }
        indicatorWidth.constant = measured
        indicatorCenterX?.isActive = false
        indicatorCenterX = indicator.centerXAnchor.constraint(
            equalTo: buttons[selectedIndex].centerXAnchor
        )
        indicatorCenterX?.isActive = true
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut]) {
                self.layoutIfNeeded()
            }
        } else {
            setNeedsLayout()
            layoutIfNeeded()
        }
    }
}

/// Resident child pages in a horizontal paging scroll view — the
/// TabBarView + KeepAliveWrapper equivalent (03 §2.1): both children stay
/// alive; taps call `select`, swipes sync through `onSwipeSelect`.
@MainActor
final class PagingTabsContainer: UIViewController, UIScrollViewDelegate {

    var onSwipeSelect: ((Int) -> Void)?

    private let pages: [UIViewController]
    private let scrollView = UIScrollView()
    private var pageViews: [UIView] = []
    private(set) var selectedIndex = 0
    private var isProgrammaticScroll = false

    init(children: [UIViewController]) {
        precondition(children.count >= 2, "PagingTabsContainer needs at least two pages")
        self.pages = children
        super.init(nibName: nil, bundle: nil)

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)
        view.addSubview(scrollView)

        for page in pages {
            addChild(page)
            scrollView.addSubview(page.view)
            page.didMove(toParent: self)
            page.view.translatesAutoresizingMaskIntoConstraints = false
            pageViews.append(page.view)
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        for (index, pageView) in pageViews.enumerated() {
            NSLayoutConstraint.activate([
                pageView.leadingAnchor.constraint(
                    equalTo: index == 0
                        ? scrollView.contentLayoutGuide.leadingAnchor
                        : pageViews[index - 1].trailingAnchor
                ),
                pageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
                // Vertical size must come from the FRAME guide. Pinning to the
                // content guide's top/bottom leaves the page's height
                // unconstrained, and the page collapses to zero height (the
                // M3 snapshot pass caught the resulting blank Inbox).
                pageView.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor),
                pageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            ])
        }
        pageViews.last?.trailingAnchor.constraint(
            equalTo: scrollView.contentLayoutGuide.trailingAnchor
        ).isActive = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Keep the selected page correct through window resizing without
        // signaling a user swipe.
        if !scrollView.isTracking && !scrollView.isDragging && !scrollView.isDecelerating {
            let target = CGFloat(selectedIndex) * scrollView.bounds.width
            if abs(scrollView.contentOffset.x - target) > 0.5 {
                scrollView.setContentOffset(CGPoint(x: target, y: 0), animated: false)
            }
        }
    }

    func select(_ index: Int, animated: Bool) {
        guard pages.indices.contains(index) else { return }
        selectedIndex = index
        let target = CGFloat(index) * scrollView.bounds.width
        guard scrollView.bounds.width > 0 else { return }
        isProgrammaticScroll = true
        scrollView.setContentOffset(CGPoint(x: target, y: 0), animated: animated)
        if !animated {
            isProgrammaticScroll = false
        }
    }

    // MARK: - UIScrollViewDelegate (swipe sync)

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // A finger stopping the programmatic animation pre-empts
        // scrollViewDidEndScrollingAnimation, which would leave the flag
        // stuck true and swallow every later swipe sync — reset it here.
        isProgrammaticScroll = false
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        syncFromScroll()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        // A drag released with ~zero velocity exactly at a page boundary
        // never decelerates — settle here or the selected index stays
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
        guard pages.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        onSwipeSelect?(index)
    }
}
