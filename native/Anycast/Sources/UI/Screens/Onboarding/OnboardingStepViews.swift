import UIKit

/// One step's content, hosted by `OnboardingViewController` between the
/// progress bar and the buttons. Step views report taps through closures
/// and restyle only what was tapped; the container owns the state.
class OnboardingStepView: UIView {

    init() {
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Called once the step is on screen. `onSettled` runs when any
    /// entrance animation has finished (immediately when there is none) —
    /// the container posts the VoiceOver screen change there, so focus
    /// lands on visible content.
    func stepDidAppear(onSettled: (() -> Void)? = nil) {
        onSettled?()
    }
}

/// A step whose content is a thread: a scrolling column that only grows.
class OnboardingThreadStepView: OnboardingStepView {

    let thread = OnboardingThreadView()

    override init() {
        super.init()
        thread.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thread)
        NSLayoutConstraint.activate([
            thread.leadingAnchor.constraint(equalTo: leadingAnchor),
            thread.trailingAnchor.constraint(equalTo: trailingAnchor),
            thread.topAnchor.constraint(equalTo: topAnchor),
            thread.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func stepDidAppear(onSettled: (() -> Void)? = nil) {
        thread.playEntranceIfNeeded(onSettled: onSettled)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - 1. Welcome

final class OnboardingWelcomeStepView: OnboardingStepView {

    override init() {
        super.init()

        // Type only, resting just above the buttons where the thumb is; no
        // mark until the app icon is decided.
        let title = OnboardingUI.label(OnboardingCopy.welcomeTitle, style: TypographyV2.displaySmall)
        title.accessibilityTraits = .header
        let body = OnboardingUI.label(OnboardingCopy.welcomeBody, style: TypographyV2.meta)

        let column = UIStackView(arrangedSubviews: [title, body])
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = Spacing.gap
        column.translatesAutoresizingMaskIntoConstraints = false

        // Scrolls at the largest text sizes; anchored low when it fits.
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        content.addSubview(column)

        let fitsFrame = content.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        fitsFrame.priority = .defaultLow

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
            fitsFrame,

            column.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            column.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: Spacing.pageHeader),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Spacing.large),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - 2. Subscriptions

final class OnboardingSubscriptionsStepView: OnboardingThreadStepView {

    private let fetchSubscriptionCount: () async -> Int
    private let statusLabel = OnboardingUI.label("", style: TypographyV2.meta)
    private nonisolated(unsafe) var subscriptionObserver: NSObjectProtocol?
    private nonisolated(unsafe) var refreshTask: Task<Void, Never>?

    var statusText: String? {
        statusLabel.isHidden ? nil : statusLabel.text
    }

    init(
        fetchSubscriptionCount: @escaping () async -> Int,
        onImportFile: @escaping () -> Void,
        onPasteFeed: @escaping () -> Void
    ) {
        self.fetchSubscriptionCount = fetchSubscriptionCount
        super.init()

        let title = OnboardingUI.label(OnboardingCopy.subscriptionsTitle, style: TypographyV2.headlineMedium)
        title.accessibilityTraits = .header
        thread.append(title)

        let options: [(String, String, () -> Void)] = [
            (OnboardingCopy.importFromApp, OnboardingCopy.importFromAppDetail, onImportFile),
            (OnboardingCopy.pasteFeed, OnboardingCopy.pasteFeedDetail, onPasteFeed),
        ]
        let rows = options.map { option -> OnboardingOptionRow in
            let row = OnboardingOptionRow(title: option.0, detail: option.1)
            let handler = option.2
            row.addAction(UIAction { _ in handler() }, for: .touchUpInside)
            return row
        }
        thread.append(OnboardingGroupedPlate(rows: rows, separatorInset: Spacing.pageH), spacingBefore: Spacing.cardInner)

        statusLabel.isHidden = true
        statusLabel.accessibilityIdentifier = "onboarding-subscriptions-status"
        thread.append(statusLabel, spacingBefore: Spacing.md)

        subscriptionObserver = NotificationCenter.default.addObserver(
            forName: ShowsShelfLayout.subscriptionsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshSubscriptionCount()
            }
        }
        refreshSubscriptionCount()
    }

    isolated deinit {
        if let subscriptionObserver {
            NotificationCenter.default.removeObserver(subscriptionObserver)
        }
        refreshTask?.cancel()
    }

    func refreshSubscriptionCount() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let count = await self.fetchSubscriptionCount()
            guard !Task.isCancelled else { return }
            self.applySubscriptionCount(count)
        }
    }

    func applySubscriptionCount(_ count: Int) {
        let text = OnboardingCopy.subscriptionStatus(count: count)
        statusLabel.text = text ?? ""
        statusLabel.isHidden = text == nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - 3. Inbox

/// Lands the add-to-playlist flight on the lesson's own Playlist tray.
@MainActor
final class OnboardingTrayEndpointProvider: PlaylistFlyInEndpointProvider {

    weak var tray: UIView?
    private let fallback = WindowCenterBottomEndpointProvider()

    func playlistFlyInEndpoint(in window: UIWindow) -> CGPoint {
        guard let tray, tray.window === window else {
            return fallback.playlistFlyInEndpoint(in: window)
        }
        return tray.convert(CGPoint(x: tray.bounds.midX, y: tray.bounds.midY), to: nil)
    }
}

/// Claims rightward horizontal drags on an onboarding episode row while leaving
/// vertical scrolling to the enclosing `OnboardingThreadView`.
@MainActor
private final class OnboardingRightSwipeDelegate: NSObject, UIGestureRecognizerDelegate {

    weak var pan: UIPanGestureRecognizer?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan, gestureRecognizer === pan, let view = pan.view else { return false }
        let velocity = pan.velocity(in: view)
        return HorizontalDragClaim.shouldClaim(velocityX: velocity.x, velocityY: velocity.y) && velocity.x > 0
    }
}

/// One sample inbox row with a trailing add button and a right-swipe gesture
/// that reveals "Add to playlist" in `AnycastColor.grass9`.
private final class OnboardingSwipeEpisodeRow: UIView {

    private static let maxSwipeOffset: CGFloat = 96
    private static let triggerOffset: CGFloat = 56
    private static let peekOffset: CGFloat = 12

    var onButtonTap: (() -> Void)?
    var onSwipeAdd: (() -> Void)?

    private let revealView = UIView()
    private let revealIcon = UIImageView()
    private let revealLabel = OnboardingUI.label(
        OnboardingCopy.swipeAddToPlaylist, style: TypographyV2.emphasis, color: Theme.onPrimary
    )
    private let revealContent = UIStackView()
    private let surfaceView = UIView()
    private let button: AnycastIconButton
    private let panDelegate = OnboardingRightSwipeDelegate()
    private var pan: UIPanGestureRecognizer!
    private weak var installedWindow: UIWindow?
    private var isQueued: Bool

    init(episode: OnboardingSampleEpisode, isQueued: Bool, artworkSide: CGFloat) {
        self.isQueued = isQueued
        self.button = AnycastIconButton(
            style: isQueued ? .inverse : .tonal,
            icon: isQueued ? AppIcons.addedToList : AppIcons.addToList,
            accessibilityLabel: isQueued
                ? OnboardingCopy.removeFromPlaylist(episode.title)
                : OnboardingCopy.addToPlaylist(episode.title)
        )
        super.init(frame: .zero)
        clipsToBounds = true

        revealIcon.contentMode = .scaleAspectFit
        revealIcon.setContentHuggingPriority(.required, for: .horizontal)
        revealIcon.setContentCompressionResistancePriority(.required, for: .horizontal)

        revealLabel.numberOfLines = 1
        revealLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        revealContent.axis = .horizontal
        revealContent.alignment = .center
        revealContent.spacing = Spacing.md
        revealContent.addArrangedSubview(revealIcon)
        revealContent.addArrangedSubview(revealLabel)
        revealContent.alpha = 0
        revealContent.translatesAutoresizingMaskIntoConstraints = false

        revealView.isAccessibilityElement = false
        revealView.accessibilityElementsHidden = true
        revealView.translatesAutoresizingMaskIntoConstraints = false
        revealView.addSubview(revealContent)
        addSubview(revealView)

        surfaceView.backgroundColor = Theme.surface
        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surfaceView)

        let artwork = UIImageView(image: OnboardingArtworkTile.image(for: episode.show))
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = Radius.sm
        artwork.layer.cornerCurve = .continuous
        artwork.applyArtworkHairline()
        artwork.isAccessibilityElement = false
        artwork.translatesAutoresizingMaskIntoConstraints = false

        let title = OnboardingUI.label(episode.title, style: TypographyV2.emphasis)
        title.numberOfLines = 0
        title.lineBreakMode = .byWordWrapping
        let meta = OnboardingUI.label(
            "\(episode.show) · \(OnboardingCopy.minutes(episode.minutes))",
            style: TypographyV2.meta,
            monospacedDigits: true
        )
        meta.numberOfLines = 1
        meta.lineBreakMode = .byTruncatingTail
        let texts = UIStackView(arrangedSubviews: [title, meta])
        texts.axis = .vertical
        texts.spacing = Spacing.xxs

        button.addAction(UIAction { [weak self] _ in
            self?.onButtonTap?()
        }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [artwork, texts, button])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Spacing.gap
        row.translatesAutoresizingMaskIntoConstraints = false
        surfaceView.addSubview(row)

        NSLayoutConstraint.activate([
            revealView.leadingAnchor.constraint(equalTo: leadingAnchor),
            revealView.trailingAnchor.constraint(equalTo: trailingAnchor),
            revealView.topAnchor.constraint(equalTo: topAnchor),
            revealView.bottomAnchor.constraint(equalTo: bottomAnchor),

            revealContent.leadingAnchor.constraint(equalTo: revealView.leadingAnchor, constant: Spacing.pageH),
            revealContent.trailingAnchor.constraint(lessThanOrEqualTo: revealView.trailingAnchor, constant: -Spacing.pageH),
            revealContent.centerYAnchor.constraint(equalTo: revealView.centerYAnchor),

            surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
            surfaceView.topAnchor.constraint(equalTo: topAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),

            artwork.widthAnchor.constraint(equalToConstant: artworkSide),
            artwork.heightAnchor.constraint(equalToConstant: artworkSide),
            row.leadingAnchor.constraint(equalTo: surfaceView.leadingAnchor, constant: Spacing.pageH),
            row.trailingAnchor.constraint(equalTo: surfaceView.trailingAnchor, constant: -Spacing.pageH),
            row.topAnchor.constraint(equalTo: surfaceView.topAnchor, constant: Spacing.gap),
            row.bottomAnchor.constraint(equalTo: surfaceView.bottomAnchor, constant: -Spacing.gap),
        ])

        pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panDelegate.pan = pan
        pan.delegate = panDelegate
        surfaceView.addGestureRecognizer(pan)
        applyRevealAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window, installedWindow !== window else { return }
        installedWindow = window
        for scrollPan in HorizontalDragClaim.enclosingScrollPans(above: self) {
            scrollPan.require(toFail: pan)
        }
    }

    func setQueued(_ queued: Bool, title: String) {
        isQueued = queued
        button.setStyle(queued ? .inverse : .tonal)
        button.setIcon(queued ? AppIcons.addedToList : AppIcons.addToList)
        button.accessibilityLabel = queued
            ? OnboardingCopy.removeFromPlaylist(title)
            : OnboardingCopy.addToPlaylist(title)
        applyRevealAppearance()
    }

    func buttonCenter(in window: UIWindow) -> CGPoint {
        button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: window)
    }

    func rowCenter(in window: UIWindow) -> CGPoint {
        convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window)
    }

    func playSwipePeekHintIfNeeded() {
        guard !isQueued, !Motion.reduceMotion else { return }
        UIView.animate(
            withDuration: 0.22,
            delay: 0.12,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.surfaceView.transform = CGAffineTransform(translationX: Self.peekOffset, y: 0)
                self.revealContent.alpha = 0.55
            },
            completion: { _ in
                UIView.animate(
                    withDuration: 0.24,
                    delay: 0,
                    usingSpringWithDamping: 0.85,
                    initialSpringVelocity: 0,
                    options: [.allowUserInteraction],
                    animations: {
                        self.surfaceView.transform = .identity
                        self.revealContent.alpha = 0
                    }
                )
            }
        )
    }

    private func applyRevealAppearance() {
        revealView.backgroundColor = isQueued ? Theme.surfaceContainerHigh : AnycastColor.grass9
        let foreground = isQueued ? Theme.onSurfaceVariant : Theme.onPrimary
        revealIcon.image = isQueued ? AppIcons.addedToList : AppIcons.addToList
        revealIcon.tintColor = foreground
        revealLabel.text = isQueued ? OnboardingCopy.swipeInPlaylist : OnboardingCopy.swipeAddToPlaylist
        revealLabel.textColor = foreground
    }

    // MARK: - Swipe gesture

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let raw = gesture.translation(in: self).x
        let clamped: CGFloat
        if raw <= 0 {
            clamped = 0
        } else if raw <= Self.triggerOffset {
            clamped = raw
        } else {
            clamped = min(Self.maxSwipeOffset, Self.triggerOffset + (raw - Self.triggerOffset) * 0.35)
        }

        switch gesture.state {
        case .began, .changed:
            surfaceView.transform = CGAffineTransform(translationX: clamped, y: 0)
            revealContent.alpha = min(1, clamped / 44)
        case .ended:
            let velocityX = gesture.velocity(in: self).x
            let triggered = clamped >= Self.triggerOffset || (clamped >= 28 && velocityX > 400)
            if triggered, !isQueued {
                onSwipeAdd?()
            }
            snapBack()
        case .cancelled, .failed:
            snapBack()
        default:
            break
        }
    }

    private func snapBack() {
        let duration = Motion.reduceMotion ? Motion.quick : Motion.standard
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.surfaceView.transform = .identity
            self.revealContent.alpha = 0
        }
    }
}

final class OnboardingInboxStepView: OnboardingThreadStepView {

    private static let artworkSide: CGFloat = InboxEpisodeCardCell.artworkSide

    private let episodes: [OnboardingSampleEpisode]
    private let onToggle: (String) -> [String]
    private let tray = OnboardingPlaylistTrayView()
    private let endpointProvider: OnboardingTrayEndpointProvider
    private let flyInAnimator: PlaylistFlyInAnimator
    private var currentQueuedIDs: [String]
    private var pendingFlyInIDs: Set<String> = []
    private var rows: [OnboardingSwipeEpisodeRow] = []
    private var hasPlayedPeekHint = false

    /// `onToggle` adds or removes the sample episode in the flow and returns
    /// the queued ids, in order.
    init(episodes: [OnboardingSampleEpisode], queued: [String], onToggle: @escaping (String) -> [String]) {
        self.episodes = episodes
        self.currentQueuedIDs = queued
        self.onToggle = onToggle
        let endpointProvider = OnboardingTrayEndpointProvider()
        self.endpointProvider = endpointProvider
        self.flyInAnimator = PlaylistFlyInAnimator(endpointProvider: endpointProvider)
        super.init()
        endpointProvider.tray = tray

        let title = OnboardingUI.label(OnboardingCopy.inboxTitle, style: TypographyV2.headlineMedium)
        title.accessibilityTraits = .header
        thread.append(title)
        thread.append(OnboardingUI.label(OnboardingCopy.inboxHint, style: TypographyV2.meta), spacingBefore: Spacing.md)

        let builtRows = episodes.map { makeRow($0, isQueued: queued.contains($0.id)) }
        self.rows = builtRows
        // The rows' text column starts after the page padding, the cover
        // and the gap.
        let textColumnInset = Spacing.pageH + Self.artworkSide + Spacing.gap
        thread.append(OnboardingGroupedPlate(rows: builtRows, separatorInset: textColumnInset), spacingBefore: Spacing.cardInner)

        tray.setEpisodes(queuedEpisodes(queued), animated: false)
        thread.append(tray, spacingBefore: Spacing.cardInner)
    }

    override func stepDidAppear(onSettled: (() -> Void)? = nil) {
        super.stepDidAppear { [weak self] in
            onSettled?()
            guard let self, !self.hasPlayedPeekHint else { return }
            self.hasPlayedPeekHint = true
            self.rows.first?.playSwipePeekHintIfNeeded()
        }
    }

    private func queuedEpisodes(_ ids: [String]) -> [OnboardingSampleEpisode] {
        ids.compactMap { id in episodes.first { $0.id == id } }
    }

    private func makeRow(_ episode: OnboardingSampleEpisode, isQueued: Bool) -> OnboardingSwipeEpisodeRow {
        let row = OnboardingSwipeEpisodeRow(episode: episode, isQueued: isQueued, artworkSide: Self.artworkSide)
        row.onButtonTap = { [weak self, weak row] in
            guard let self, let row else { return }
            self.toggle(episode, row: row, fromSwipe: false)
        }
        row.onSwipeAdd = { [weak self, weak row] in
            guard let self, let row, !self.currentQueuedIDs.contains(episode.id) else { return }
            self.toggle(episode, row: row, fromSwipe: true)
        }
        return row
    }

    private func toggle(_ episode: OnboardingSampleEpisode, row: OnboardingSwipeEpisodeRow, fromSwipe: Bool) {
        let queued = onToggle(episode.id)
        currentQueuedIDs = queued
        let isQueued = queued.contains(episode.id)
        row.setQueued(isQueued, title: episode.title)

        if isQueued {
            if let window = self.window {
                pendingFlyInIDs.insert(episode.id)
                let startPoint = fromSwipe ? row.rowCenter(in: window) : row.buttonCenter(in: window)
                // The animator plays the add haptic itself; the tray row
                // inserts once the flight reaches it.
                flyInAnimator.fly(from: startPoint, in: window) { [weak self] in
                    guard let self else { return }
                    self.pendingFlyInIDs.remove(episode.id)
                    self.syncTray(animated: true)
                }
            } else {
                Haptics.queueAdded()
                syncTray(animated: false)
            }
        } else {
            pendingFlyInIDs.remove(episode.id)
            syncTray(animated: true)
            thread.scrollToShow(tray)
            Haptics.queueRemoved()
        }
    }

    private func syncTray(animated: Bool) {
        let visibleIDs = currentQueuedIDs.filter { !pendingFlyInIDs.contains($0) }
        tray.setEpisodes(queuedEpisodes(visibleIDs), animated: animated)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - 4. Transcript

/// One sample transcript line: the time, the sentence and its translation.
/// No background box: active lines render at full opacity and inactive lines
/// dim to 0.42 alpha.
final class OnboardingTranscriptLineControl: UIControl {

    static let inactiveAlpha: CGFloat = 0.42

    private let row = UIStackView()

    init(line: OnboardingSampleLine) {
        super.init(frame: .zero)
        backgroundColor = .clear

        let time = OnboardingUI.label(line.timestamp, style: TypographyV2.meta, monospacedDigits: true)
        time.numberOfLines = 1
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)

        let originalLabel = OnboardingUI.label(line.original, style: TypographyV2.emphasis, color: Theme.onSurface)
        let translation = OnboardingUI.label(line.translation, style: TypographyV2.meta)
        let texts = UIStackView(arrangedSubviews: [originalLabel, translation])
        texts.axis = .vertical
        texts.spacing = Spacing.xxs

        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = Spacing.gap
        row.addArrangedSubview(time)
        row.addArrangedSubview(texts)
        // Touches fall through to the control.
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.xs),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.xs),
        ])

        isAccessibilityElement = true
        accessibilityLabel = "\(line.timestamp), \(line.original), \(line.translation)"
        applySelection(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            applySelection(animated: window != nil && !Motion.reduceMotion)
        }
    }

    private func applySelection(animated: Bool) {
        backgroundColor = .clear
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        let targetAlpha: CGFloat = isSelected ? 1 : Self.inactiveAlpha
        if animated {
            Motion.animate(Motion.quick) {
                self.row.alpha = targetAlpha
            }
        } else {
            row.alpha = targetAlpha
        }
    }

    /// Exposed for tests verifying active vs. inactive line emphasis.
    var contentAlpha: CGFloat { row.alpha }
}

final class OnboardingTranscriptStepView: OnboardingThreadStepView {

    private static let cardArtworkSide: CGFloat = 28

    private let lines: [OnboardingSampleLine]
    private var lineControls: [OnboardingTranscriptLineControl] = []
    private var timestampPills: [OnboardingTimestampPillButton] = []
    private var headerMetaLabel: UILabel!
    private var transcriptCard: UIView!
    private(set) var selectedIndex: Int
    private nonisolated(unsafe) var replyTask: Task<Void, Never>?

    init(lines: [OnboardingSampleLine]) {
        self.lines = lines
        self.selectedIndex = lines.indices.contains(1) ? 1 : 0
        super.init()

        let title = OnboardingUI.label(OnboardingCopy.transcriptTitle, style: TypographyV2.headlineMedium)
        title.accessibilityTraits = .header
        thread.append(title)
        thread.append(OnboardingUI.label(OnboardingCopy.transcriptHint, style: TypographyV2.meta), spacingBefore: Spacing.md)

        let card = makeTranscriptCard(lines)
        self.transcriptCard = card
        thread.append(card, spacingBefore: Spacing.cardInner)

        let ask = OnboardingChipButton(title: OnboardingCopy.askEpisode)
        let chips = OnboardingFlowLayoutView(items: [ask])
        ask.addAction(UIAction { [weak self, weak ask, weak chips] _ in
            guard let self, let ask, let chips else { return }
            // Asked once: the chip gives way to the question as the
            // listener's line, then the answer and timestamp pills follow.
            ask.isSelected = true
            ask.disableAnswering()
            Haptics.selection()
            self.thread.collapse(chips) { [weak self] in
                guard let self else { return }
                self.thread.append(OnboardingBubbleView(.listener, text: OnboardingCopy.askEpisode))
                self.replyTask?.cancel()
                self.replyTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled, let self else { return }
                    self.thread.append(self.makeAnswerBlock())
                }
            }
        }, for: .touchUpInside)
        thread.append(chips)
    }

    isolated deinit {
        replyTask?.cancel()
    }

    private func makeTranscriptCard(_ lines: [OnboardingSampleLine]) -> UIView {
        let cover = UIImageView(image: OnboardingArtworkTile.image(for: OnboardingCopy.transcriptShow))
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = Radius.sm
        cover.layer.cornerCurve = .continuous
        cover.applyArtworkHairline()
        cover.isAccessibilityElement = false
        cover.translatesAutoresizingMaskIntoConstraints = false

        let initialTime = lines.indices.contains(selectedIndex) ? lines[selectedIndex].timestamp : ""
        let headerMeta = OnboardingUI.label(
            Self.headerText(timestamp: initialTime),
            style: TypographyV2.meta,
            monospacedDigits: true
        )
        headerMeta.numberOfLines = 1
        headerMeta.lineBreakMode = .byTruncatingTail
        self.headerMetaLabel = headerMeta

        let headerRow = UIStackView(arrangedSubviews: [cover, headerMeta])
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = Spacing.row

        let column = UIStackView(arrangedSubviews: [headerRow])
        column.axis = .vertical
        column.spacing = Spacing.chip

        for (index, line) in lines.enumerated() {
            let control = OnboardingTranscriptLineControl(line: line)
            control.isSelected = index == selectedIndex
            control.addAction(UIAction { [weak self] _ in
                self?.select(index, scrollToCard: false)
            }, for: .touchUpInside)
            lineControls.append(control)
            column.addArrangedSubview(control)
        }
        column.translatesAutoresizingMaskIntoConstraints = false

        let plate = CardSurfaceView(radius: Radius.card)
        plate.addSubview(column)
        NSLayoutConstraint.activate([
            cover.widthAnchor.constraint(equalToConstant: Self.cardArtworkSide),
            cover.heightAnchor.constraint(equalToConstant: Self.cardArtworkSide),

            column.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: Spacing.pageH),
            column.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -Spacing.pageH),
            column.topAnchor.constraint(equalTo: plate.topAnchor, constant: Spacing.chip),
            column.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -Spacing.chip),
        ])
        return plate
    }

    private func makeAnswerBlock() -> UIView {
        let answerBubble = OnboardingBubbleView(
            .anycast,
            text: OnboardingCopy.askEpisodePoints.joined(separator: "\n")
        )
        let pills = lines.enumerated().map { index, line -> OnboardingTimestampPillButton in
            let pill = OnboardingTimestampPillButton(timestamp: line.timestamp)
            pill.isSelected = index == selectedIndex
            pill.addAction(UIAction { [weak self] _ in
                self?.select(index, scrollToCard: true)
            }, for: .touchUpInside)
            return pill
        }
        timestampPills = pills
        let pillsRow = OnboardingFlowLayoutView(items: pills)

        let stack = UIStackView(arrangedSubviews: [answerBubble, pillsRow])
        stack.axis = .vertical
        stack.spacing = Spacing.gap
        return stack
    }

    /// Selects the transcript line at `index` (used by line taps and answer
    /// timestamp pills).
    func select(_ index: Int, scrollToCard: Bool = false) {
        guard lineControls.indices.contains(index) else { return }
        if index != selectedIndex {
            if lineControls.indices.contains(selectedIndex) {
                lineControls[selectedIndex].isSelected = false
            }
            lineControls[index].isSelected = true
            selectedIndex = index
            headerMetaLabel.text = Self.headerText(timestamp: lines[index].timestamp)
            for (pillIndex, pill) in timestampPills.enumerated() {
                pill.isSelected = pillIndex == index
            }
            Haptics.selection()
        }
        if scrollToCard {
            thread.scrollToShow(transcriptCard)
        }
    }

    /// Exposed for unit tests to inspect line controls.
    var lineCount: Int { lineControls.count }

    func isLineSelected(at index: Int) -> Bool {
        lineControls.indices.contains(index) && lineControls[index].isSelected
    }

    func makeAnswerBlockForTesting() -> UIView {
        makeAnswerBlock()
    }

    private static func headerText(timestamp: String) -> String {
        timestamp.isEmpty
            ? OnboardingCopy.transcriptShow
            : "\(OnboardingCopy.transcriptShow) · \(timestamp)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
