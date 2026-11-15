import UIKit
import AnycastKit

/// The first-launch onboarding: a short conversation (interests, moving
/// subscriptions, a first read of the listener) and two hands-on lessons
/// (the queue, the transcript). Presented full screen over the tab shell.
///
/// This container owns the step state (`OnboardingFlow`), the progress bar
/// and the two buttons; each step's content is an `OnboardingStepView`.
/// The lessons use sample data only: nothing here subscribes, queues or
/// calls the network, except the two import options, which hand over to
/// the app's existing import flows.
final class OnboardingViewController: UIViewController {

    private let context: UIContext
    private let gate: OnboardingGate
    private var flow = OnboardingFlow()

    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let contentContainer = UIView()
    private let primaryButton = AnycastButton.make(.primary, title: OnboardingCopy.start)
    private let skipButton = UIButton(type: .system)
    private var stepView: OnboardingStepView?
    /// True while a step change is animating. A double tap on the primary
    /// or skip button during that window would otherwise race the swap and
    /// advance a second step (or finish) off one gesture.
    private var isChangingStep = false

    private static let primaryHeight: CGFloat = 52
    private static let skipHeight: CGFloat = 44

    init(context: UIContext, gate: OnboardingGate = OnboardingGate()) {
        self.context = context
        self.gate = gate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        buildViews()
        showCurrentStep(animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        stepView?.stepDidAppear()
    }

    private func buildViews() {
        progressView.trackTintColor = AnycastColor.sandAlpha4
        progressView.progressTintColor = Theme.onSurface
        progressView.isAccessibilityElement = false
        progressView.accessibilityIdentifier = "onboarding-progress"

        primaryButton.accessibilityIdentifier = "onboarding-primary"
        primaryButton.addAction(UIAction { [weak self] _ in self?.primaryTapped() }, for: .touchUpInside)

        var skipConfiguration = UIButton.Configuration.plain()
        skipConfiguration.baseForegroundColor = Theme.onSurfaceVariant
        skipConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.meta.font()
            return outgoing
        }
        skipButton.configuration = skipConfiguration
        skipButton.titleLabel?.adjustsFontForContentSizeCategory = true
        skipButton.accessibilityIdentifier = "onboarding-skip"
        skipButton.addAction(UIAction { [weak self] _ in self?.skipTapped() }, for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [primaryButton, skipButton])
        buttons.axis = .vertical
        buttons.spacing = Spacing.xs

        for item in [progressView, contentContainer, buttons] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: Spacing.gap),
            progressView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: Spacing.pageH),
            progressView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -Spacing.pageH),
            progressView.heightAnchor.constraint(equalToConstant: Spacing.compactProgress),

            // The thread's own top inset (the fade length) makes up the rest
            // of the 32 pt between the bar and the first item.
            contentContainer.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: Spacing.pageH),
            contentContainer.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: Spacing.pageH),
            contentContainer.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -Spacing.pageH),
            contentContainer.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -Spacing.gap),

            buttons.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: Spacing.pageH),
            buttons.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -Spacing.pageH),
            buttons.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -Spacing.md),

            primaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.primaryHeight),
            skipButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.skipHeight),
        ])
    }

    // MARK: - Steps

    private func makeStepView(for step: OnboardingStep) -> OnboardingStepView {
        switch step {
        case .welcome:
            return OnboardingWelcomeStepView()
        case .interests:
            return OnboardingInterestsStepView(selected: flow.interests) { [weak self] name in
                guard let self else { return false }
                let isSelected = self.flow.toggleInterest(name)
                self.renderControls()
                return isSelected
            }
        case .subscriptions:
            return OnboardingSubscriptionsStepView(
                interests: flow.interests,
                onImportFile: { [weak self] in self?.importFile() },
                onPasteFeed: { [weak self] in self?.pasteFeedAddress() }
            )
        case .impression:
            return OnboardingImpressionStepView(interests: flow.interests)
        case .queueLesson:
            return OnboardingQueueLessonStepView(
                episodes: OnboardingSamples.episodes, queued: flow.queuedEpisodeIDs
            ) { [weak self] id in
                guard let self else { return [] }
                self.flow.toggleQueued(id)
                self.renderControls()
                return self.flow.queuedEpisodeIDs
            }
        case .transcriptLesson:
            return OnboardingTranscriptLessonStepView(
                lines: OnboardingSamples.transcript, hasAsked: flow.hasAskedEpisode
            ) { [weak self] in
                guard let self else { return }
                self.flow.markEpisodeAsked()
                self.renderControls()
            }
        case .done:
            return OnboardingDoneStepView()
        }
    }

    /// Swaps in the current step's view. Only a step change comes through
    /// here; taps inside a step never rebuild it.
    private func showCurrentStep(animated: Bool) {
        let incoming = makeStepView(for: flow.step)
        incoming.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(incoming)
        NSLayoutConstraint.activate([
            incoming.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            incoming.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            incoming.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            incoming.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        let outgoing = stepView
        stepView = incoming
        renderControls()
        progressView.setProgress(flow.progress, animated: animated && !Motion.reduceMotion)

        guard animated else {
            outgoing?.removeFromSuperview()
            return
        }
        contentContainer.layoutIfNeeded()
        // VoiceOver focus moves once the incoming step's entrance has
        // settled: posting during the fade lands the focus on views that
        // are still alpha 0. Reduce Motion settles immediately.
        incoming.stepDidAppear(onSettled: { [weak incoming] in
            UIAccessibility.post(notification: .screenChanged, argument: incoming)
        })

        guard let outgoing else { return }
        guard !Motion.reduceMotion else {
            outgoing.removeFromSuperview()
            return
        }
        outgoing.isUserInteractionEnabled = false
        isChangingStep = true
        Motion.animate(
            Motion.quick,
            { outgoing.alpha = 0 },
            completion: { [weak self] in
                self?.isChangingStep = false
                outgoing.removeFromSuperview()
            }
        )
    }

    /// Updates the two buttons from the flow. Called on every answer.
    private func renderControls() {
        let title: String
        switch flow.step {
        case .welcome: title = OnboardingCopy.start
        case .interests: title = OnboardingCopy.interestsDone(count: flow.interests.count)
        case .done: title = OnboardingCopy.enter
        case .subscriptions, .impression, .queueLesson, .transcriptLesson: title = OnboardingCopy.next
        }
        if primaryButton.configuration?.title != title {
            primaryButton.configuration?.title = title
        }
        primaryButton.isEnabled = flow.canContinue

        // The skip row is always reserved, so the primary button never
        // moves when the skip option comes or goes.
        let option = flow.skipOption
        switch option {
        case .none: break
        case .step: skipButton.configuration?.title = OnboardingCopy.skipStep
        case .all: skipButton.configuration?.title = OnboardingCopy.skipAll
        }
        let isSkipVisible = option != .none
        skipButton.alpha = isSkipVisible ? 1 : 0
        skipButton.isUserInteractionEnabled = isSkipVisible
        skipButton.accessibilityElementsHidden = !isSkipVisible
    }

    // MARK: - Actions

    private func primaryTapped() {
        guard !isChangingStep, flow.advance() else { return }
        stepChanged()
    }

    private func skipTapped() {
        guard !isChangingStep else { return }
        switch flow.skipOption {
        case .none: return
        case .step: flow.skipStep()
        case .all: flow.skipAll()
        }
        stepChanged()
    }

    private func stepChanged() {
        if flow.isFinished {
            finish()
        } else {
            showCurrentStep(animated: true)
        }
    }

    /// Finishing and skipping end the same way: remember it, land on the
    /// Playlist tab, and leave.
    private func finish() {
        gate.markCompleted()
        // Tab 1 is Playlist (MainTabBarController.selectTab).
        context.tabs.select(1)
        dismiss(animated: true)
    }

    // MARK: - Moving subscriptions (the app's existing import flows)

    /// The same door as Settings' "Import subscriptions": the file picker,
    /// then the import sheet.
    private func importFile() {
        ImportFlow.chooseFile(from: self, context: context)
    }

    /// Asks for a feed address, then shows the same feed row Search shows
    /// for a pasted address (title, host, Follow).
    private func pasteFeedAddress() {
        let alert = UIAlertController(title: OnboardingCopy.pasteFeed, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = OnboardingCopy.pasteFeedPlaceholder
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: OnboardingCopy.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: OnboardingCopy.pasteFeedConfirm, style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let text = alert?.textFields?.first?.text ?? ""
            guard let address = FeedAddress.parse(text) else {
                if let window = self.view.window {
                    ToastPresenter.shared.show(OnboardingCopy.notAFeedAddress, in: window, duration: 3)
                }
                return
            }
            let sheet = OnboardingFeedAddressSheetViewController(context: self.context, address: address)
            AppSheets.presentForm(sheet, from: self)
        })
        present(alert, animated: true)
    }
}

/// Hosts Search's feed-address page in a sheet, so a pasted address can be
/// followed from the onboarding with the same row and the same writes.
final class OnboardingFeedAddressSheetViewController: UIViewController {

    private let page: SearchFeedAddressViewController
    private let address: String

    init(context: UIContext, address: String) {
        self.page = SearchFeedAddressViewController(context: context)
        self.address = address
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)

        let titleLabel = OnboardingUI.label(OnboardingCopy.pasteFeed, style: TypographyV2.emphasis)
        titleLabel.accessibilityTraits = .header
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        addChild(page)
        page.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(page.view)
        page.didMove(toParent: self)

        // The grabber closes the sheet, so there is no Done button. The
        // title sits on the sheet content edge, which is also the leading
        // edge of the feed row's cover (page padding + row padding).
        let titleLeading = Spacing.sheetContent
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Spacing.sheetContent),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: titleLeading),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),

            page.view.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            page.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            page.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            page.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        page.load(address: address)
    }
}

/// Decides, once the tab shell is up, whether to show the onboarding.
@MainActor
enum OnboardingLauncher {

    /// Hosted unit and snapshot tests launch the real app; the onboarding
    /// must not cover the shell they exercise.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Presents the onboarding over `root` on a first launch. Someone with
    /// any existing data — subscriptions, playlist episodes, history or
    /// inbox episodes — upgraded from an earlier version and is marked as
    /// done instead. If something else is already presented (a login sheet,
    /// a share handoff), it waits for the next launch.
    static func presentIfNeeded(
        from root: UIViewController, context: UIContext, gate: OnboardingGate = OnboardingGate()
    ) {
        guard !gate.hasCompleted, !isRunningTests else { return }
        Task { [weak root] in
            let hasExistingData = try? await Self.listenerHasExistingData(context.database)
            switch OnboardingGate.decision(hasCompleted: gate.hasCompleted, hasExistingData: hasExistingData) {
            case .skip:
                return
            case .markCompleted:
                gate.markCompleted()
            case .present:
                guard let root, root.view.window != nil, root.presentedViewController == nil else { return }
                let controller = OnboardingViewController(context: context, gate: gate)
                controller.modalPresentationStyle = .fullScreen
                controller.modalTransitionStyle = .crossDissolve
                root.present(controller, animated: true)
            }
        }
    }

    /// Whether the listener already has data of their own in any store.
    /// COUNT probes only — nothing is decoded just to be counted. A throw
    /// from any store reads as "could not decide", handled by the gate.
    static func listenerHasExistingData(_ database: AppDatabase) async throws -> Bool {
        if try await database.subscriptionRepository().count() > 0 { return true }
        if try await database.playlistRepository().episodeCount() > 0 { return true }
        if try await database.historyRepository().count() > 0 { return true }
        return try await database.feedRepository().count() > 0
    }
}
