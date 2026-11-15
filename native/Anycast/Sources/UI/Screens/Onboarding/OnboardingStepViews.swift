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

    /// Called once the step is on screen.
    func stepDidAppear() {}
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

    override func stepDidAppear() {
        thread.playEntranceIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - 1. Welcome

final class OnboardingWelcomeStepView: OnboardingStepView {

    override init() {
        super.init()

        // The brand mark again, large and faint, behind the copy.
        let watermark = UILabel()
        watermark.text = OnboardingCopy.brandMark
        watermark.font = .systemFont(ofSize: 300, weight: .ultraLight)
        watermark.textColor = AnycastColor.sandAlpha3
        watermark.transform = CGAffineTransform(rotationAngle: -15 * .pi / 180)
        watermark.isAccessibilityElement = false
        watermark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(watermark)
        clipsToBounds = true

        let mark = UILabel()
        mark.text = OnboardingCopy.brandMark
        mark.font = TypographyV2.displayLarge.font()
        mark.textColor = Theme.onSurface
        mark.adjustsFontForContentSizeCategory = true
        mark.isAccessibilityElement = false

        let waveform = OnboardingWaveformView()

        let title = OnboardingUI.label(OnboardingCopy.welcomeTitle, style: TypographyV2.displaySmall)
        title.accessibilityTraits = .header
        let body = OnboardingUI.label(OnboardingCopy.welcomeBody, style: TypographyV2.emphasis, color: Theme.onSurfaceVariant)

        let column = UIStackView(arrangedSubviews: [mark, waveform, title, body])
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = Spacing.gap
        column.setCustomSpacing(Spacing.pageHeader, after: mark)
        column.setCustomSpacing(Spacing.sectionGap, after: waveform)
        column.translatesAutoresizingMaskIntoConstraints = false

        // Scrolls at the largest text sizes; centered when it fits.
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
            watermark.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 100),
            watermark.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 120),

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
            column.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            column.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: Spacing.pageHeader),
            column.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -Spacing.pageHeader),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - 2. Interests

final class OnboardingInterestsStepView: OnboardingThreadStepView {

    /// Toggles the named interest in the flow; returns whether it is now
    /// selected.
    init(selected: [String], onToggle: @escaping (String) -> Bool) {
        super.init()

        thread.append(OnboardingBubbleView(.anycast, text: OnboardingCopy.interestsQuestion))
        thread.append(OnboardingUI.label(OnboardingCopy.interestsHint, style: TypographyV2.meta), spacingBefore: Spacing.md)

        let chips = OnboardingCopy.interests.map { name -> OnboardingChipButton in
            let chip = OnboardingChipButton(title: name)
            chip.isSelected = selected.contains(name)
            chip.addAction(UIAction { [weak chip] _ in
                // Only the tapped chip changes.
                chip?.isSelected = onToggle(name)
                Haptics.selection()
            }, for: .touchUpInside)
            return chip
        }
        thread.append(OnboardingFlowLayoutView(items: chips), spacingBefore: Spacing.cardInner)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - 3. Move subscriptions

final class OnboardingSubscriptionsStepView: OnboardingThreadStepView {

    init(
        interests: [String],
        onImportFile: @escaping () -> Void,
        onPasteFeed: @escaping () -> Void,
        onStartFromPicks: @escaping () -> Void
    ) {
        super.init()

        // The answer to the previous question, echoed as the listener's line.
        if !interests.isEmpty {
            thread.append(OnboardingBubbleView(.listener, text: interests.joined(separator: ", ")))
        }
        thread.append(OnboardingBubbleView(.anycast, text: OnboardingCopy.subscriptionsQuestion))

        let options: [(String, String, () -> Void)] = [
            (OnboardingCopy.importFromApp, OnboardingCopy.importFromAppDetail, onImportFile),
            (OnboardingCopy.pasteFeed, OnboardingCopy.pasteFeedDetail, onPasteFeed),
            (OnboardingCopy.startFromPicks, OnboardingCopy.startFromPicksDetail, onStartFromPicks),
        ]
        for (index, option) in options.enumerated() {
            let row = OnboardingOptionRow(title: option.0, detail: option.1)
            let handler = option.2
            row.addAction(UIAction { _ in handler() }, for: .touchUpInside)
            thread.append(row, spacingBefore: index == 0 ? Spacing.cardInner : Spacing.md)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - 4. Read of you

final class OnboardingImpressionStepView: OnboardingThreadStepView {

    private var replyTask: Task<Void, Never>?

    init(interests: [String]) {
        super.init()

        thread.append(OnboardingBubbleView(.anycast, text: OnboardingCopy.impression(interests: interests)))
        thread.append(Self.makeHelpCard())
        thread.append(OnboardingBubbleView(.anycast, text: OnboardingCopy.impressionFeedback))

        let right = OnboardingChipButton(title: OnboardingCopy.impressionRight)
        let wrong = OnboardingChipButton(title: OnboardingCopy.impressionWrong)
        let answers: [(OnboardingChipButton, String)] = [
            (right, OnboardingCopy.impressionRightReply),
            (wrong, OnboardingCopy.impressionWrongReply),
        ]
        for (chip, reply) in answers {
            chip.addAction(UIAction { [weak self, weak chip, weak right, weak wrong] _ in
                guard let self, let chip else { return }
                // One answer: the tapped chip stays lit, both stop responding.
                chip.isSelected = true
                right?.isUserInteractionEnabled = false
                wrong?.isUserInteractionEnabled = false
                Haptics.selection()
                self.answer(chip.configuration?.title ?? "", reply: reply)
            }, for: .touchUpInside)
        }
        thread.append(OnboardingFlowLayoutView(items: [right, wrong]))
    }

    private func answer(_ text: String, reply: String) {
        thread.append(OnboardingBubbleView(.listener, text: text))
        replyTask?.cancel()
        replyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            self.thread.append(OnboardingBubbleView(.anycast, text: reply))
        }
    }

    private static func makeHelpCard() -> UIView {
        let title = OnboardingUI.label(OnboardingCopy.helpTitle, style: TypographyV2.emphasis)
        title.accessibilityTraits = .header
        let column = UIStackView(arrangedSubviews: [title])
        column.axis = .vertical
        column.spacing = Spacing.md
        for line in OnboardingCopy.helpLines {
            let bullet = OnboardingUI.label("·", style: TypographyV2.body, color: Theme.onSurfaceVariant)
            bullet.isAccessibilityElement = false
            bullet.setContentHuggingPriority(.required, for: .horizontal)
            bullet.setContentCompressionResistancePriority(.required, for: .horizontal)
            let text = OnboardingUI.label(line, style: TypographyV2.body)
            let row = UIStackView(arrangedSubviews: [bullet, text])
            row.axis = .horizontal
            row.alignment = .firstBaseline
            row.spacing = Spacing.md
            column.addArrangedSubview(row)
        }
        column.translatesAutoresizingMaskIntoConstraints = false

        let plate = CardSurfaceView(radius: Radius.card)
        plate.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: Spacing.pageH),
            column.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -Spacing.pageH),
            column.topAnchor.constraint(equalTo: plate.topAnchor, constant: Spacing.chip),
            column.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -Spacing.chip),
        ])
        return plate
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - 5. Queue lesson

/// Lands the add-to-queue flight on the lesson's own Up Next tray.
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

final class OnboardingQueueLessonStepView: OnboardingThreadStepView {

    private let episodes: [OnboardingSampleEpisode]
    private let onToggle: (String) -> [String]
    private let tray = OnboardingUpNextTrayView()
    private let endpointProvider: OnboardingTrayEndpointProvider
    private let flyInAnimator: PlaylistFlyInAnimator

    /// `onToggle` adds or removes the sample episode in the flow and returns
    /// the queued ids, in order.
    init(episodes: [OnboardingSampleEpisode], queued: [String], onToggle: @escaping (String) -> [String]) {
        self.episodes = episodes
        self.onToggle = onToggle
        let endpointProvider = OnboardingTrayEndpointProvider()
        self.endpointProvider = endpointProvider
        self.flyInAnimator = PlaylistFlyInAnimator(endpointProvider: endpointProvider)
        super.init()
        endpointProvider.tray = tray

        let title = OnboardingUI.label(OnboardingCopy.queueTitle, style: TypographyV2.headlineMedium)
        title.accessibilityTraits = .header
        thread.append(title)
        thread.append(OnboardingUI.label(OnboardingCopy.queueHint, style: TypographyV2.meta), spacingBefore: Spacing.md)
        thread.append(OnboardingUI.label(OnboardingCopy.sampleCaption, style: TypographyV2.meta), spacingBefore: Spacing.cardInner)

        for episode in episodes {
            thread.append(makeRow(episode, isQueued: queued.contains(episode.id)), spacingBefore: Spacing.md)
        }

        tray.setEpisodes(queuedEpisodes(queued), animated: false)
        thread.append(tray, spacingBefore: Spacing.cardInner)
    }

    private func queuedEpisodes(_ ids: [String]) -> [OnboardingSampleEpisode] {
        ids.compactMap { id in episodes.first { $0.id == id } }
    }

    private func makeRow(_ episode: OnboardingSampleEpisode, isQueued: Bool) -> UIView {
        let artwork = UIImageView(image: ArtworkPlaceholder.image(for: episode.show))
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = Radius.artwork
        artwork.layer.cornerCurve = .continuous
        artwork.isAccessibilityElement = false
        artwork.translatesAutoresizingMaskIntoConstraints = false

        let title = OnboardingUI.label(episode.title, style: TypographyV2.emphasis)
        let meta = OnboardingUI.label(
            "\(episode.show) · \(OnboardingCopy.minutes(episode.minutes))", style: TypographyV2.meta
        )
        let texts = UIStackView(arrangedSubviews: [title, meta])
        texts.axis = .vertical
        texts.spacing = Spacing.xxs

        let button = AnycastIconButton(
            style: .tonal,
            icon: isQueued ? AppIcons.check : AppIcons.add,
            accessibilityLabel: isQueued
                ? OnboardingCopy.removeFromUpNext(episode.title)
                : OnboardingCopy.addToUpNext(episode.title)
        )
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let self, let button else { return }
            self.toggle(episode, button: button)
        }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [artwork, texts, button])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Spacing.gap
        row.translatesAutoresizingMaskIntoConstraints = false

        let plate = UIView()
        plate.backgroundColor = Theme.surface
        plate.layer.cornerRadius = Radius.card
        plate.layer.cornerCurve = .continuous
        plate.addSubview(row)
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: Spacing.xxl),
            artwork.heightAnchor.constraint(equalToConstant: Spacing.xxl),
            row.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: Spacing.gap),
            row.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -Spacing.gap),
            row.topAnchor.constraint(equalTo: plate.topAnchor, constant: Spacing.gap),
            row.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -Spacing.gap),
        ])
        return plate
    }

    private func toggle(_ episode: OnboardingSampleEpisode, button: AnycastIconButton) {
        let queued = onToggle(episode.id)
        let isQueued = queued.contains(episode.id)
        // Only the tapped row's button changes; the tray appends or drops
        // that one episode.
        button.setIcon(isQueued ? AppIcons.check : AppIcons.add)
        button.accessibilityLabel = isQueued
            ? OnboardingCopy.removeFromUpNext(episode.title)
            : OnboardingCopy.addToUpNext(episode.title)
        tray.setEpisodes(queuedEpisodes(queued), animated: true)

        if isQueued {
            if let window = self.window {
                // The animator plays the add haptic itself.
                flyInAnimator.fly(from: button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil), in: window)
            } else {
                Haptics.queueAdded()
            }
        } else {
            Haptics.queueRemoved()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - 6. Transcript lesson

/// One sample transcript line: the time, the sentence and its translation.
final class OnboardingTranscriptLineControl: UIControl {

    private let originalLabel: UILabel
    private let lineDescription: String

    init(line: OnboardingSampleLine) {
        originalLabel = OnboardingUI.label(line.original, style: TypographyV2.body)
        lineDescription = "\(line.timestamp), \(line.original), \(line.translation)"
        super.init(frame: .zero)

        layer.cornerRadius = Radius.md
        layer.cornerCurve = .continuous

        let time = OnboardingUI.label(line.timestamp, style: TypographyV2.meta)
        time.font = TypographyV2.meta.font().monospacedDigits()
        time.numberOfLines = 1
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)

        let translation = OnboardingUI.label(line.translation, style: TypographyV2.meta)
        let texts = UIStackView(arrangedSubviews: [originalLabel, translation])
        texts.axis = .vertical
        texts.spacing = Spacing.xxs

        let row = UIStackView(arrangedSubviews: [time, texts])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = Spacing.gap
        // Touches fall through to the control.
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.gap),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.gap),
            row.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.row),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.row),
        ])

        isAccessibilityElement = true
        accessibilityLabel = lineDescription
        applySelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isSelected: Bool {
        didSet { applySelection() }
    }

    private func applySelection() {
        backgroundColor = isSelected ? AnycastColor.sandAlpha4 : .clear
        originalLabel.textColor = isSelected ? Theme.onSurface : Theme.onSurfaceVariant
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}

final class OnboardingTranscriptLessonStepView: OnboardingThreadStepView {

    private let onAsk: () -> Void
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private var lineControls: [OnboardingTranscriptLineControl] = []
    private var selectedIndex: Int?

    /// `onAsk` records in the flow that the sample question was asked.
    init(lines: [OnboardingSampleLine], hasAsked: Bool, onAsk: @escaping () -> Void) {
        self.onAsk = onAsk
        super.init()

        let title = OnboardingUI.label(OnboardingCopy.transcriptTitle, style: TypographyV2.headlineMedium)
        title.accessibilityTraits = .header
        thread.append(title)
        thread.append(OnboardingUI.label(OnboardingCopy.transcriptHint, style: TypographyV2.meta), spacingBefore: Spacing.md)
        thread.append(makeTranscriptCard(lines), spacingBefore: Spacing.cardInner)

        let ask = OnboardingChipButton(title: OnboardingCopy.askEpisode)
        ask.addAction(UIAction { [weak self, weak ask] _ in
            guard let self, let ask else { return }
            // Asked once: the chip stays lit and the answer is appended.
            ask.isSelected = true
            ask.isUserInteractionEnabled = false
            Haptics.selection()
            self.onAsk()
            self.thread.append(OnboardingBubbleView(.anycast, text: OnboardingCopy.askEpisodeAnswer))
        }, for: .touchUpInside)
        thread.append(OnboardingFlowLayoutView(items: [ask]))

        if hasAsked {
            ask.isSelected = true
            ask.isUserInteractionEnabled = false
            thread.append(OnboardingBubbleView(.anycast, text: OnboardingCopy.askEpisodeAnswer))
        }
    }

    private func makeTranscriptCard(_ lines: [OnboardingSampleLine]) -> UIView {
        let caption = OnboardingUI.label(OnboardingCopy.sampleTranscriptCaption, style: TypographyV2.meta)

        progressView.trackTintColor = AnycastColor.sandAlpha4
        progressView.progressTintColor = Theme.onSurface
        progressView.isAccessibilityElement = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.heightAnchor.constraint(equalToConstant: Spacing.compactProgress).isActive = true

        let column = UIStackView(arrangedSubviews: [caption, progressView])
        column.axis = .vertical
        column.spacing = Spacing.md
        column.setCustomSpacing(Spacing.gap, after: progressView)

        for (index, line) in lines.enumerated() {
            let control = OnboardingTranscriptLineControl(line: line)
            control.addAction(UIAction { [weak self] _ in self?.select(index) }, for: .touchUpInside)
            lineControls.append(control)
            column.addArrangedSubview(control)
        }
        column.translatesAutoresizingMaskIntoConstraints = false

        let plate = CardSurfaceView(radius: Radius.card)
        plate.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: Spacing.md),
            column.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -Spacing.md),
            column.topAnchor.constraint(equalTo: plate.topAnchor, constant: Spacing.chip),
            column.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -Spacing.md),
        ])
        return plate
    }

    private func select(_ index: Int) {
        guard index != selectedIndex, lineControls.indices.contains(index) else { return }
        // Only the previous and the tapped line restyle.
        if let selectedIndex { lineControls[selectedIndex].isSelected = false }
        lineControls[index].isSelected = true
        selectedIndex = index
        Haptics.selection()
        progressView.setProgress(Float(index + 1) / Float(lineControls.count), animated: !Motion.reduceMotion)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - 7. Done

final class OnboardingDoneStepView: OnboardingThreadStepView {

    override init() {
        super.init()
        thread.append(OnboardingBubbleView(.anycast, text: OnboardingCopy.done))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
