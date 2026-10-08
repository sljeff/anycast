import UIKit
import AnycastKit

/// Pure page-selection state for the player's three-page pager
/// (lib/pages/player.dart:45-50, 03 §2.10): bounded 0…pageCount-1, STARTS
/// on index 1 (main controls) and RESETS to 1 when the sheet closes — the
/// PopScope quirk. Unit-tested.
@MainActor
final class PlayerPageSelection {

    let pageCount: Int
    let initialIndex: Int
    private(set) var selectedIndex: Int

    init(pageCount: Int, initialIndex: Int = 1) {
        self.pageCount = max(pageCount, 1)
        self.initialIndex = min(max(initialIndex, 0), max(pageCount - 1, 0))
        self.selectedIndex = self.initialIndex
    }

    /// From a capsule tap or a swipe; returns true when the index moved.
    @discardableResult
    func select(_ index: Int) -> Bool {
        let clamped = min(max(index, 0), pageCount - 1)
        guard clamped != selectedIndex else { return false }
        selectedIndex = clamped
        return true
    }

    /// The PopScope reset (player.dart:45-50): back to the initial page.
    func reset() {
        selectedIndex = initialIndex
    }
}

/// The bottom capsule selector (lib/pages/player.dart:89-116, widget #7):
/// 56 pt tall pill (Dart radius 36 on a 56-high pill == capsule), 1 pt
/// 0x4B5563 border, 0x19-alpha 0x232830 background, three 48×48 buttons
/// (settings / podcasts / AI topology brand icon); the selected button is
/// white with a black icon.
@MainActor
final class PlayerPageTabView: UIView {

    struct Item {
        let icon: UIImage
        let accessibilityLabel: String
    }

    var onSelect: ((Int) -> Void)?

    private var buttons: [UIButton] = []
    private var iconViews: [UIImageView] = []
    private(set) var selectedIndex = 0

    init(items: [Item]) {
        super.init(frame: CGRect(x: 0, y: 0, width: items.count * 48 + (items.count - 1) * 24, height: 56))

        backgroundColor = Theme.cardBackground.withAlphaComponent(0x19 / 255.0)
        layer.borderColor = Theme.hintGray.cgColor
        layer.borderWidth = 1
        // Dart BorderRadius.circular(36) on a 56 pt pill → capsule.
        layer.cornerRadius = 28
        layer.cornerCurve = .continuous

        let stack = UIStackView()
        stack.axis = .horizontal
        // The Dart Row packs 48 pt buttons with no spacing (player.dart:171-178).
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for (index, item) in items.enumerated() {
            let button = UIButton(type: .custom)
            // Brand SVGs load as 1 pt vector images (width="1em" in the
            // source), so icon sizing is explicit, not image-size driven.
            let iconView = UIImageView(image: item.icon)
            iconView.contentMode = .scaleAspectFit
            iconView.isUserInteractionEnabled = false
            iconView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(iconView)
            button.isAccessibilityElement = true
            button.accessibilityLabel = item.accessibilityLabel
            button.accessibilityIdentifier = "player-page-tab-\(index)"
            button.tag = index
            button.addAction(
                UIAction { [weak self] _ in self?.tapped(index: index) },
                for: .touchUpInside
            )
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 24),
                iconView.heightAnchor.constraint(equalToConstant: 24),
            ])
            button.widthAnchor.constraint(equalToConstant: 48).isActive = true
            button.heightAnchor.constraint(equalToConstant: 48).isActive = true
            stack.addArrangedSubview(button)
            buttons.append(button)
            iconViews.append(iconView)
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            // Capsule wraps the buttons (mainAxisSize.min).
            widthAnchor.constraint(equalTo: stack.widthAnchor, constant: 8),
        ])

        applySelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func select(_ index: Int) {
        guard buttons.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        applySelection()
    }

    private func tapped(index: Int) {
        guard index != selectedIndex else { return }
        selectedIndex = index
        applySelection()
        onSelect?(index)
    }

    private func applySelection() {
        for (index, button) in buttons.enumerated() {
            let isSelected = index == selectedIndex
            iconViews[index].tintColor = isSelected ? .black : Theme.primaryLightMax
            button.backgroundColor = isSelected
                ? Theme.primaryLightMax
                : .clear
            button.layer.cornerRadius = 24
            button.layer.cornerCurve = .continuous
            button.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        }
    }
}

/// The full-screen player sheet (lib/pages/player.dart:40-87, 03 §2.10):
/// presented as a full-height page sheet with system chrome (A2: system
/// grabber, no custom handler), over a three-stop vertical gradient
/// (palette dominant → 0x111316 → 0x111316), containing the three-page
/// pager and the PageTab capsule. Closing resets to page 1 (PopScope).
///
/// Pages 0/1/2 are stubs at this stage; their real tasks replace the page
/// controllers, not this container.
@MainActor
final class PlayerPageContainer: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    private let context: UIContext
    let selection = PlayerPageSelection(pageCount: 3, initialIndex: 1)

    private let pages: [UIViewController]
    private let pageController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal
    )
    private let pageTab: PlayerPageTabView
    private let gradientLayer = CAGradientLayer()
    private let paletteObservation = ObservationLoop()
    private var gradientImageURL: String?

    static func present(from presenter: UIViewController, context: UIContext) {
        let controller = PlayerPageContainer(context: context)
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.large()]
            // A2 adaptation: system grabber + system chrome; the Flutter
            // expand-sheet handler is deliberately not recreated here.
            sheet.prefersGrabberVisible = true
        }
        presenter.present(controller, animated: true)
    }

    init(context: UIContext) {
        self.context = context
        self.pages = [
            SettingsPageViewController(context: context),
            PlayerMainPageViewController(context: context),
            SubtitlesPageViewController(context: context),
        ]
        self.pageTab = PlayerPageTabView(items: [
            .init(icon: AppIcons.playerSettings, accessibilityLabel: "Player settings"),
            .init(icon: AppIcons.playerMain, accessibilityLabel: "Player main"),
            .init(icon: AppIcons.topology ?? UIImage(), accessibilityLabel: "Player AI transcript"),
        ])
        super.init(nibName: nil, bundle: nil)
        pageTab.onSelect = { [weak self] index in
            self?.pageTabSelected(index)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)

        let gradientTraits = UITraitCollection(userInterfaceStyle: .dark)
        gradientLayer.colors = [
            Theme.paletteFallback.cgColor,
            Theme.primaryBackgroundDark.resolvedColor(with: gradientTraits).cgColor,
            Theme.primaryBackgroundDark.resolvedColor(with: gradientTraits).cgColor,
        ]
        gradientLayer.locations = [0, 0.5, 1]
        view.layer.insertSublayer(gradientLayer, at: 0)

        addChild(pageController)
        view.addSubview(pageController.view)
        pageController.view.backgroundColor = .clear
        pageController.view.translatesAutoresizingMaskIntoConstraints = false
        pageController.didMove(toParent: self)
        pageController.dataSource = self
        pageController.delegate = self

        pageTab.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageTab)

        NSLayoutConstraint.activate([
            pageController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageController.view.bottomAnchor.constraint(equalTo: pageTab.topAnchor),

            pageTab.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageTab.heightAnchor.constraint(equalToConstant: 56),
            pageTab.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16
            ),
        ])

        // Open on the main page AND highlight it: the capsule defaults to
        // index 0, so without this the sheet opens with the settings icon
        // selected while the main page is on screen.
        pageTab.select(selection.selectedIndex)
        showPage(selection.selectedIndex, animated: false)

        paletteObservation.track(
            read: { [weak self] in _ = self?.context.playback.currentEpisode?.imageUrl },
            onChange: { [weak self] in self?.updateGradient() }
        )
        updateGradient()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // CALayer autoresizing is macOS-only; track bounds manually so any
        // window size keeps the gradient pinned (07 §4).
        gradientLayer.frame = view.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // PopScope quirk (player.dart:45-50): closing resets to page 1 so
        // the next open lands on the main controls page. A reused container
        // reopens correctly; a fresh one starts there anyway.
        if isBeingDismissed {
            selection.reset()
            pageTab.select(selection.selectedIndex)
            showPage(selection.selectedIndex, animated: false)
        }
    }

    // MARK: - Pager

    private func showPage(_ index: Int, animated: Bool) {
        guard pages.indices.contains(index) else { return }
        pageController.setViewControllers(
            [pages[index]],
            direction: .forward,
            animated: animated,
            completion: nil
        )
    }

    /// Capsule tap: page change animates 300 ms easeInOut in the Dart
    /// source (player.dart:1009-1021); UIPageViewController's own slide
    /// is the system equivalent (curve not controllable — accepted).
    private func pageTabSelected(_ index: Int) {
        let direction: UIPageViewController.NavigationDirection =
            index > selection.selectedIndex ? .forward : .reverse
        guard selection.select(index) else { return }
        pageTab.select(index)
        pageController.setViewControllers([pages[index]], direction: direction, animated: true) { [weak self] _ in
            // Sync done; no-op placeholder for later tasks.
            _ = self?.selection.selectedIndex
        }
    }

    // MARK: - UIPageViewControllerDataSource / Delegate (swipe sync)

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let index = pages.firstIndex(of: viewController), index > 0 else { return nil }
        return pages[index - 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let index = pages.firstIndex(of: viewController), index < pages.count - 1 else { return nil }
        return pages[index + 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let current = pageViewController.viewControllers?.first,
              let index = pages.firstIndex(of: current)
        else { return }
        selection.select(index)
        pageTab.select(index)
    }

    // MARK: - Gradient background (03 §5.4)

    private func updateGradient() {
        let urlString = context.playback.currentEpisode?.imageUrl
        guard urlString != gradientImageURL else { return }
        gradientImageURL = urlString

        guard let urlString else {
            applyGradient(Theme.paletteFallback)
            return
        }
        if let cached = PaletteService.shared.cachedDominantColor(for: urlString) {
            applyGradient(cached)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let color = await PaletteService.shared.dominantColor(from: urlString)
            guard self.gradientImageURL == urlString else { return }
            self.applyGradient(color)
        }
    }

    private func applyGradient(_ dominant: UIColor) {
        // The trailing stops use a DYNAMIC semantic token: resolving with
        // explicit dark traits avoids the CGColor freeze where the Task
        // context resolves the Light variant (#F9F9F8) and washes the
        // player's dark text out (09 §9a; the player stack is pinned
        // warm-dark by design, 09 §2.1). PlayerProgressBar follows the
        // same pattern.
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        gradientLayer.colors = [
            dominant.cgColor,
            Theme.primaryBackgroundDark.resolvedColor(with: dark).cgColor,
            Theme.primaryBackgroundDark.resolvedColor(with: dark).cgColor,
        ]
    }
}
