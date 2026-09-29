import UIKit
import AnycastKit

/// Tab2 Discover (lib/pages/discover.dart:19-111, 03 §2.6): the shared
/// AppBar (gradient DISCOVER title, embedded search field, gear) over a
/// horizontally scrolling category strip and swipeable per-category channel
/// lists. The category fetch starts in viewDidLoad — the shell prewarms the
/// tab at launch, which is the IndexedStack parity (07 §2.1 note). A
/// country change reloads every page that has ever displayed (the Dart Obx
/// on countryCode rebuilds all alive FutureBuilders).
@MainActor
final class DiscoverViewController: UIViewController {

    private let context: UIContext
    private var viewModel: DiscoverViewModel!

    // AppBar (03 §2.2)
    private let searchField = UITextField()
    private let cancelButton = UIButton(type: .system)

    // Body
    private var categoryStrip: UnderlineTabBarView?
    private var pagingContainer: DiscoverPagingContainer?
    private let bodySpinner = UIActivityIndicatorView(style: .large)
    private let networkErrorLabel = UILabel()

    private let observation = ObservationLoop()
    /// Block-API observer token — touched only on the main thread
    /// (registered in viewDidLoad, removed in deinit); `nonisolated(unsafe)`
    /// because deinit is nonisolated under strict concurrency.
    private nonisolated(unsafe) var countryObserver: NSObjectProtocol?

    // MARK: - Construction

    init(context: UIContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let countryObserver {
            NotificationCenter.default.removeObserver(countryObserver)
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)

        viewModel = DiscoverViewModel(
            api: context.api,
            countryProvider: { [settingsBox = context.settingsBox] in
                settingsBox.current.countryCode
            }
        )

        buildHeader()
        buildBodyOverlay()

        observation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.viewModel.categoriesLoading
                _ = self.viewModel.categoriesFailed
                _ = self.viewModel.categories
            },
            onChange: { [weak self] in self?.renderCategories() }
        )

        // The launch-time prefetch (IndexedStack parity — the shell's
        // loadViewIfNeeded prewarm lands here).
        renderCategories()
        viewModel.loadCategories()

        // Dart Obx on SettingsController.countryCode (discover.dart:63).
        countryObserver = NotificationCenter.default.addObserver(
            forName: SettingsCoordinator.countryCodeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.viewModel.countryDidChange()
        }
    }

    // MARK: - AppBar (MyAppBar title DISCOVER, appbar.dart)

    private func buildHeader() {
        let title = GradientTextLabel()
        title.text = "DISCOVER"

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
            header.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8
            ),
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
        cancelButton.isHidden = (searchField.text ?? "").isEmpty
    }

    /// Non-empty submit opens the SearchPage sheet (appbar.dart:97-107).
    @objc private func searchSubmitted() {
        let text = searchField.text ?? ""
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

    // MARK: - Body

    private func buildBodyOverlay() {
        bodySpinner.color = Theme.primary
        bodySpinner.hidesWhenStopped = true
        bodySpinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bodySpinner)

        // Centered white "Network Error" for a failed/empty category list
        // (discover.dart:73-78 applied at page level).
        networkErrorLabel.text = "Network Error"
        networkErrorLabel.textColor = Theme.secondaryText
        networkErrorLabel.font = Typography.secondaryTitle.font()
        networkErrorLabel.adjustsFontForContentSizeCategory = true
        networkErrorLabel.textAlignment = .center
        networkErrorLabel.isHidden = true
        networkErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(networkErrorLabel)

        NSLayoutConstraint.activate([
            bodySpinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bodySpinner.centerYAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -160
            ),
            networkErrorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            networkErrorLabel.centerYAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -160
            ),
        ])
    }

    /// The strip + paging area anchors under the AppBar search field; the
    /// safe-area bottom keeps clear of the shell's floating mini player
    /// through the shell's additionalSafeAreaInsets (iOS 18 fallback).
    private func buildTabsAndPages(names: [String]) {
        let strip = UnderlineTabBarView(
            titles: names,
            selectedFont: Self.categoryFont(),
            unselectedFont: Self.categoryFont()
        )
        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.onSelect = { [weak self] index in
            self?.selectCategory(index, animatedPages: true)
        }
        view.addSubview(strip)

        let container = DiscoverPagingContainer(pageCount: names.count)
        container.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(container)
        view.addSubview(container.view)
        container.didMove(toParent: self)
        container.onSwipeSelect = { [weak self] index in
            self?.selectCategory(index, animatedPages: false)
        }
        container.onScrub = { [weak self] index in
            // Mid-drag materialization — the PageView builds the page it is
            // being dragged toward; the strip indicator tracks the drag
            // (DefaultTabController links bar and view).
            self?.materializeAround(index: index)
            self?.categoryStrip?.select(index, animated: false)
        }

        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            strip.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            strip.heightAnchor.constraint(equalToConstant: 44),

            container.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.view.topAnchor.constraint(equalTo: strip.bottomAnchor),
            container.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        categoryStrip = strip
        pagingContainer = container
        materializeAround(index: 0)
    }

    /// Secondary-tab label font — Dart labelLarge: 17 pt w600 system
    /// (anycast_theme.dart:327-331); the pill-box indicator becomes the
    /// shared thin underline (07 §2.1 secondary-tab mapping).
    private static func categoryFont() -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17, weight: .semibold)
        )
    }

    private func selectCategory(_ index: Int, animatedPages: Bool) {
        materializeAround(index: index)
        categoryStrip?.select(index, animated: true)
        pagingContainer?.select(index, animated: animatedPages)
    }

    /// Installs page controllers for the materialized model indices near the
    /// selection. `selectCategory` only returns NEW models — but pages can
    /// pre-exist (buildPagesIfNeeded materializes 0/1 before the container
    /// exists), so install every live model in range; `install` is a no-op
    /// for slots that already hold a page.
    private func materializeAround(index: Int) {
        _ = viewModel.selectCategory(index)
        for i in index - 1 ... index + 1 {
            guard let model = viewModel.pages[i] else { continue }
            pagingContainer?.install(
                DiscoverCategoryPageViewController(context: context, model: model),
                at: i
            )
        }
    }

    private func renderCategories() {
        switch viewModel.categoriesPhase {
        case .loading:
            bodySpinner.startAnimating()
            networkErrorLabel.isHidden = true
        case .networkError:
            bodySpinner.stopAnimating()
            networkErrorLabel.isHidden = false
        case .loaded(let names):
            bodySpinner.stopAnimating()
            networkErrorLabel.isHidden = true
            if categoryStrip == nil {
                buildTabsAndPages(names: names)
            }
        }
    }
}
