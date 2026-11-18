import UIKit
import AnycastKit

/// The first-launch onboarding: a welcome screen, moving existing
/// subscriptions, and two hands-on lessons (adding to Playlist and reading
/// and asking an AI transcript). Presented full screen over the tab shell.
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
    /// True while a step change (or finish) is in flight. A double tap on
    /// the primary or skip button during that window would otherwise race
    /// the swap and advance a second step (or finish) off one gesture.
    private var isChangingStep = false
    private var stepTransitionToken = 0
    private var isStepFadeFinished = true
    private var isStepEntranceSettled = true

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
        progressView.progressTintColor = Theme.primary
        progressView.clipsToBounds = true
        progressView.layer.cornerRadius = Spacing.compactProgress / 2
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
        case .subscriptions:
            let database = context.database
            return OnboardingSubscriptionsStepView(
                fetchSubscriptionCount: {
                    (try? await database.subscriptionRepository().count()) ?? 0
                },
                onImportFile: { [weak self] in self?.importFile() },
                onPasteFeed: { [weak self] in self?.pasteFeedAddress() }
            )
        case .inbox:
            return OnboardingInboxStepView(
                episodes: OnboardingSamples.episodes,
                queued: flow.queuedEpisodeIDs
            ) { [weak self] id in
                guard let self else { return [] }
                self.flow.toggleQueued(id)
                return self.flow.queuedEpisodeIDs
            }
        case .transcript:
            return OnboardingTranscriptStepView(lines: OnboardingSamples.transcript)
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
        stepTransitionToken &+= 1
        let token = stepTransitionToken

        renderControls(animated: animated)
        progressView.setProgress(flow.progress, animated: animated && !Motion.reduceMotion)

        guard animated else {
            isStepFadeFinished = true
            isStepEntranceSettled = true
            outgoing?.removeFromSuperview()
            return
        }

        guard !Motion.reduceMotion else {
            isStepFadeFinished = true
            isStepEntranceSettled = false
            contentContainer.layoutIfNeeded()
            outgoing?.removeFromSuperview()
            incoming.stepDidAppear(onSettled: { [weak self, weak incoming] in
                guard let self, self.stepTransitionToken == token else { return }
                self.isStepEntranceSettled = true
                self.postScreenChangedIfReady(incoming)
            })
            return
        }

        incoming.alpha = 0
        contentContainer.layoutIfNeeded()
        outgoing?.isUserInteractionEnabled = false
        isChangingStep = true
        isStepFadeFinished = false
        isStepEntranceSettled = false
        Motion.animate(
            Motion.quick,
            {
                outgoing?.alpha = 0
                incoming.alpha = 1
            },
            completion: { [weak self, weak incoming] in
                outgoing?.removeFromSuperview()
                guard let self, self.stepTransitionToken == token else { return }
                self.isChangingStep = false
                self.isStepFadeFinished = true
                self.postScreenChangedIfReady(incoming)
            }
        )
        // VoiceOver focus moves once both the crossfade and the incoming
        // step's entrance have settled so focus lands on visible content.
        incoming.stepDidAppear(onSettled: { [weak self, weak incoming] in
            guard let self, self.stepTransitionToken == token else { return }
            self.isStepEntranceSettled = true
            self.postScreenChangedIfReady(incoming)
        })
    }

    private func postScreenChangedIfReady(_ target: OnboardingStepView?) {
        guard isStepFadeFinished, isStepEntranceSettled, let target else { return }
        UIAccessibility.post(notification: .screenChanged, argument: target)
    }

    /// Updates the two buttons and progress visibility from the flow.
    private func renderControls(animated: Bool = false) {
        let title: String
        switch flow.step {
        case .welcome: title = OnboardingCopy.start
        case .subscriptions, .inbox: title = OnboardingCopy.next
        case .transcript: title = OnboardingCopy.openAnycast
        }
        if primaryButton.configuration?.title != title {
            primaryButton.configuration?.title = title
        }
        primaryButton.isEnabled = flow.canContinue

        // The skip row is always reserved so the primary button never
        // jumps when the skip option fades out.
        let option = flow.skipOption
        if option == .all, skipButton.configuration?.title != OnboardingCopy.skip {
            skipButton.configuration?.title = OnboardingCopy.skip
        }
        let isSkipVisible = option != .none
        skipButton.isUserInteractionEnabled = isSkipVisible
        skipButton.accessibilityElementsHidden = !isSkipVisible

        let targetSkipAlpha: CGFloat = isSkipVisible ? 1 : 0
        let targetProgressAlpha: CGFloat = flow.step == .welcome ? 0 : 1
        if animated, !Motion.reduceMotion {
            Motion.animate(Motion.quick) {
                self.skipButton.alpha = targetSkipAlpha
                self.progressView.alpha = targetProgressAlpha
            }
        } else {
            skipButton.alpha = targetSkipAlpha
            progressView.alpha = targetProgressAlpha
        }
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

    /// Finishing and skipping end the same way: mark completion, route to
    /// Inbox (when subscribed) or Discover (when not), and dismiss.
    private func finish() {
        guard !isChangingStep else { return }
        isChangingStep = true
        view.isUserInteractionEnabled = false
        gate.markCompleted()
        let database = context.database
        Task { [weak self] in
            let count = (try? await database.subscriptionRepository().count()) ?? 0
            let destination = OnboardingFlow.exitTabIndex(subscriptionCount: count)
            guard let self else { return }
            self.context.tabs.select(destination)
            self.dismiss(animated: true)
        }
    }

    // MARK: - Moving subscriptions (the app's existing import flows)

    /// Mirrors `InboxPageViewController`'s empty-state import: present
    /// instructions first, then hand over to the file picker and import sheet.
    private func importFile() {
        ImportInstructionsViewController.present(from: self) { [weak self] instructions in
            guard let self else { return }
            ImportFlow.chooseFile(from: instructions, context: self.context) { [weak instructions] in
                // Done closes the sheet and the instructions under it.
                instructions?.presentingViewController?.dismiss(animated: true)
            }
        }
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

    /// Debug builds only: launching with `-onboarding.preview YES` shows the
    /// onboarding on every launch, even on an install that already follows
    /// shows, so it can be reviewed on a device with real data.
    private static var isPreviewRequested: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "onboarding.preview")
        #else
        false
        #endif
    }

    /// Presents the onboarding over `root` on a first launch. Someone with
    /// any existing data — subscriptions, playlist episodes, history or
    /// inbox episodes — upgraded from an earlier version and is marked as
    /// done instead. If something else is already presented (a login sheet,
    /// a share handoff), it waits for the next launch.
    static func presentIfNeeded(
        from root: UIViewController, context: UIContext, gate: OnboardingGate = OnboardingGate()
    ) {
        guard !gate.hasCompleted || isPreviewRequested, !isRunningTests else { return }
        Task { [weak root] in
            let hasExistingData = try? await Self.listenerHasExistingData(context.database)
            let decision = isPreviewRequested
                ? .present
                : OnboardingGate.decision(hasCompleted: gate.hasCompleted, hasExistingData: hasExistingData)
            switch decision {
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
