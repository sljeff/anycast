import UIKit

/// Podcast destination with the Flutter Inbox / Subscriptions inner flow.
@MainActor
final class PodcastHomeViewController: UIViewController {

    private let context: UIContext
    private let header = HeaderView()
    private let sectionBar = PodcastSectionBar()
    private var sectionControllers: [UIViewController] = []
    private var childPins: [[NSLayoutConstraint]] = []
    private var selectedSection = 0
    private var inboxStatus = ""
    private var subscriptionsStatus = ""

    init(context: UIContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)

        header.configure(HeaderView.Configuration(title: "Podcast"))
        header.onSearch = { [weak self] query in
            guard let self else { return }
            SearchPageViewController.present(
                from: self.topMostPresented(), context: self.context, searchText: query
            )
        }
        header.onSettings = { [weak self] in self?.openSettings() }
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        sectionBar.translatesAutoresizingMaskIntoConstraints = false
        sectionBar.onSelect = { [weak self] index in self?.showSection(index) }
        view.addSubview(sectionBar)

        let inbox = InboxPageViewController(context: context, showsHeader: false)
        inbox.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.inboxStatus = status
            if self.selectedSection == 0 { self.updateHeaderStatus(status) }
        }
        let subscriptions = LibraryViewController(context: context, showsHeader: false)
        subscriptions.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.subscriptionsStatus = status
            if self.selectedSection == 1 { self.updateHeaderStatus(status) }
        }
        sectionControllers = [inbox, subscriptions]

        for child in sectionControllers {
            addChild(child)
            child.view.translatesAutoresizingMaskIntoConstraints = false
            childPins.append([
                child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                child.view.topAnchor.constraint(equalTo: sectionBar.bottomAnchor, constant: Spacing.md),
                child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            child.didMove(toParent: self)
            child.loadViewIfNeeded()
        }

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            sectionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            sectionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            sectionBar.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Spacing.xs),
            sectionBar.heightAnchor.constraint(equalToConstant: 60),
        ])

        showSection(0, animated: false)
        propagateBottomAvoidance()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        propagateBottomAvoidance()
    }

    private func showSection(_ index: Int, animated: Bool = true) {
        guard sectionControllers.indices.contains(index) else { return }
        let oldIndex = selectedSection
        selectedSection = index
        let inWindow = view.window != nil

        for (position, child) in sectionControllers.enumerated() {
            if position == index {
                if child.view.superview == nil {
                    view.insertSubview(child.view, at: 0)
                    NSLayoutConstraint.activate(childPins[position])
                    if inWindow {
                        child.beginAppearanceTransition(true, animated: animated)
                        child.endAppearanceTransition()
                    }
                }
            } else if child.view.superview != nil {
                if inWindow {
                    child.beginAppearanceTransition(false, animated: animated)
                }
                NSLayoutConstraint.deactivate(childPins[position])
                child.view.removeFromSuperview()
                if inWindow {
                    child.endAppearanceTransition()
                }
            }
        }

        if oldIndex != index { sectionBar.select(index, animated: animated) }
        updateHeaderStatus(index == 0 ? inboxStatus : subscriptionsStatus)
    }

    private func updateHeaderStatus(_ status: String) {
        header.configure(HeaderView.Configuration(title: "Podcast", statusText: status.isEmpty ? nil : status))
    }

    private func propagateBottomAvoidance() {
        let bottom = additionalSafeAreaInsets.bottom
        sectionControllers.forEach { $0.additionalSafeAreaInsets.bottom = bottom }
    }

    private func openSettings() {
        AppSheets.presentExpand(
            SettingsViewController(context: context),
            from: topMostPresented()
        )
    }
}
