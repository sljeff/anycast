import UIKit
import Kingfisher
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

/// The bottom page selector (lib/pages/player.dart:89-116, widget #7) in the
/// Anycast 2.0 button-group form: a tinted capsule of 44 pt icon buttons
/// (settings / main / AI transcript); the selected page's button carries a
/// lighter capsule and full-strength icon.
@MainActor
final class PlayerPageTabView: UIView {

    struct Item {
        let icon: UIImage
        let accessibilityLabel: String
    }

    var onSelect: ((Int) -> Void)?

    private var buttons: [UIButton] = []
    private(set) var selectedIndex = 0

    init(items: [Item]) {
        super.init(frame: .zero)

        for (index, item) in items.enumerated() {
            let button = UIButton(type: .custom)
            // Brand SVGs load as 1 pt vector images (width="1em" in the
            // source), so the glyph box is explicit, not image-size driven.
            let iconView = UIImageView(image: item.icon.withRenderingMode(.alwaysTemplate))
            iconView.contentMode = .scaleAspectFit
            iconView.preferredSymbolConfiguration = IconStyle.groupAction.configuration
            iconView.isUserInteractionEnabled = false
            iconView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(iconView)
            button.isAccessibilityElement = true
            button.accessibilityLabel = item.accessibilityLabel
            button.accessibilityIdentifier = "player-page-tab-\(index)"
            button.layer.cornerRadius = AnycastIconButton.standardDiameter / 2
            button.layer.cornerCurve = .continuous
            button.addAction(
                UIAction { [weak self] _ in self?.tapped(index: index) },
                for: .touchUpInside
            )
            button.addPressFeedback()
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: IconStyle.groupAction.pointSize + Spacing.xs),
                iconView.heightAnchor.constraint(equalToConstant: IconStyle.groupAction.pointSize + Spacing.xs),
                button.widthAnchor.constraint(equalToConstant: AnycastIconButton.standardDiameter),
                button.heightAnchor.constraint(equalToConstant: AnycastIconButton.standardDiameter),
            ])
            buttons.append(button)
        }

        let group = AnycastButtonGroup(
            buttons: buttons,
            background: AnycastColor.sandAlpha3,
            spacing: Spacing.gap,
            insets: .init(top: Spacing.xs, leading: Spacing.xs, bottom: Spacing.xs, trailing: Spacing.xs)
        )
        group.translatesAutoresizingMaskIntoConstraints = false
        addSubview(group)
        NSLayoutConstraint.activate([
            group.topAnchor.constraint(equalTo: topAnchor),
            group.bottomAnchor.constraint(equalTo: bottomAnchor),
            group.leadingAnchor.constraint(equalTo: leadingAnchor),
            group.trailingAnchor.constraint(equalTo: trailingAnchor),
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
        Haptics.selection()
        selectedIndex = index
        applySelection()
        onSelect?(index)
    }

    private func applySelection() {
        for (index, button) in buttons.enumerated() {
            let isSelected = index == selectedIndex
            button.tintColor = isSelected ? Theme.playerText : Theme.playerSecondary.withAlphaComponent(0.7)
            button.backgroundColor = isSelected ? AnycastColor.sandAlpha4 : .clear
            button.subviews.forEach { $0.tintColor = button.tintColor }
            button.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        }
    }
}

/// The full-screen player sheet (lib/pages/player.dart:40-87, 03 §2.10):
/// presented as a full-height page sheet with system chrome (A2: system
/// grabber, no custom handler), containing the three-page pager and the
/// page selector. Closing resets to page 1 (PopScope).
///
/// Background (Anycast 2.0 UI kit player): the episode artwork, blurred
/// under a dark material and a five-stop black scrim; the warm-dark player
/// base shows when there is no artwork.
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
    private let backdropImageView = UIImageView()
    private let backdropObservation = ObservationLoop()
    private var backdropImageURL: String?

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
        Theme.installPlayerBase(on: view)
        installBackdrop()

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
            pageTab.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Spacing.md
            ),
        ])

        // Open on the main page AND highlight it: the capsule defaults to
        // index 0, so without this the sheet opens with the settings icon
        // selected while the main page is on screen.
        pageTab.select(selection.selectedIndex)
        showPage(selection.selectedIndex, animated: false)

        backdropObservation.track(
            read: { [weak self] in _ = self?.context.playback.currentEpisode?.imageUrl },
            onChange: { [weak self] in self?.updateBackdrop() }
        )
        updateBackdrop()
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

    // MARK: - Backdrop

    private func installBackdrop() {
        backdropImageView.contentMode = .scaleAspectFill
        backdropImageView.clipsToBounds = true
        // The material is explicitly dark: blur ignores trait overrides
        // (09 §9a), and the player is warm-dark by design.
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        let scrim = PlayerBackdropScrimView()
        for layer in [backdropImageView, blur, scrim] {
            layer.isUserInteractionEnabled = false
            layer.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(layer)
            NSLayoutConstraint.activate([
                layer.topAnchor.constraint(equalTo: view.topAnchor),
                layer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                layer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                layer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }
    }

    private func updateBackdrop() {
        let urlString = context.playback.currentEpisode?.imageUrl
        guard urlString != backdropImageURL else { return }
        backdropImageURL = urlString
        backdropImageView.kf.cancelDownloadTask()
        backdropImageView.image = nil
        guard let urlString, let url = URL(string: urlString) else { return }
        backdropImageView.kf.setImage(with: url)
    }
}

/// The player backdrop's five-stop black scrim (UI kit `PlayerBackgroundGradientView`).
private final class PlayerBackdropScrimView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let gradient = layer as! CAGradientLayer
        gradient.colors = [0.2, 0.25, 0.376, 0.4, 0.5].map {
            UIColor.black.withAlphaComponent($0).cgColor
        }
        gradient.locations = [0, 0.25, 0.5, 0.745, 1]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
