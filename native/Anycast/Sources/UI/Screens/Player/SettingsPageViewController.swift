import UIKit
import AnycastKit

/// Player page 0 (PlayerSettings, player.dart:118-144 + the Settings widget
/// 1148-1372, 03 §2.10): the episode's HTML description fills a scroll area
/// (empty payload collapses it), with the settings card pinned at the
/// bottom in the Anycast 2.0 audio-settings form — playback speed and sleep
/// timer rows with − / + steppers over the same stops the Dart sliders had
/// (SPEED 0.5–2.0 ×0.25, COUNTDOWN 0–60 ×10), and the CONTINUOUS PLAY
/// switch, its explanation shown as the row subtitle. SKIP SILENCE is
/// deliberately absent (decision K2 — no iOS public API).
final class SettingsPageViewController: UIViewController {

    private let context: UIContext
    private let observation = ObservationLoop()

    private let descriptionTextView = HTMLContentRenderer.makeTextView(
        linkTarget: HTMLContentRenderer.playerShared
    )
    private let scrollView = UIScrollView()
    private var renderedCacheKey: String?

    private static let speedStops = PlayerSliderMath.stops(min: 0.5, max: 2.0, divisions: 6)
    private static let countdownStops = SleepTimerController.sliderMinutes

    private let speedValueLabel = UILabel()
    private let countdownValueLabel = UILabel()
    private lazy var speedStepper = Self.makeStepper(
        minusLabel: "Decrease playback speed", plusLabel: "Increase playback speed",
        onMinus: { [weak self] in self?.stepSpeed(by: -1) },
        onPlus: { [weak self] in self?.stepSpeed(by: 1) }
    )
    private lazy var countdownStepper = Self.makeStepper(
        minusLabel: "Shorten sleep timer", plusLabel: "Extend sleep timer",
        onMinus: { [weak self] in self?.stepCountdown(by: -1) },
        onPlus: { [weak self] in self?.stepCountdown(by: 1) }
    )
    private let continuousSwitch = UISwitch()
    private var countdownTicker: Timer?

    init(context: UIContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        build()
        bindActions()
        renderSpeed()
        renderCountdown()
        renderContinuous()
        renderDescription()

        observation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.context.playback.currentEpisode
                _ = self.context.playback.speed
            },
            onChange: { [weak self] in
                self?.renderDescription()
                self?.renderSpeed()
            }
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startCountdownTicker()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        countdownTicker?.invalidate()
        countdownTicker = nil
    }

    // MARK: - Build

    private func build() {
        descriptionTextView.font = Typography.htmlBody.font()
        descriptionTextView.textColor = Typography.htmlBody.color
        descriptionTextView.adjustsFontForContentSizeCategory = true
        descriptionTextView.isAccessibilityElement = true
        descriptionTextView.accessibilityLabel = "Episode description"

        let contentStack = UIStackView(arrangedSubviews: [descriptionTextView])
        contentStack.axis = .vertical
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        let root = UIStackView(arrangedSubviews: [scrollView, buildSettingsCard()])
        root.axis = .vertical
        root.spacing = Spacing.pageH
        root.isLayoutMarginsRelativeArrangement = true
        root.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Spacing.pageH, leading: Spacing.pageHeader, bottom: Spacing.pageH, trailing: Spacing.pageHeader
        )
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// UI kit audio-settings rows on a tinted card, hairline-divided.
    private func buildSettingsCard() -> UIView {
        for label in [speedValueLabel, countdownValueLabel] {
            label.font = TypographyV2.bodyLarge.font().monospacedDigits()
            label.textColor = Theme.playerSecondary
            label.adjustsFontForContentSizeCategory = true
            label.setContentHuggingPriority(.required, for: .horizontal)
        }

        continuousSwitch.onTintColor = Theme.primary
        continuousSwitch.accessibilityLabel = "Continuous play"

        let rows = UIStackView(arrangedSubviews: [
            Self.makeRow(title: "Playback speed", subtitle: nil, trailing: [speedValueLabel, speedStepper]),
            Self.makeDivider(),
            Self.makeRow(title: "Sleep timer", subtitle: nil, trailing: [countdownValueLabel, countdownStepper]),
            Self.makeDivider(),
            Self.makeRow(
                title: "Continuous play",
                subtitle: "Auto play next episode after the current one ends.",
                trailing: [continuousSwitch]
            ),
        ])
        rows.axis = .vertical
        rows.isLayoutMarginsRelativeArrangement = true
        rows.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Spacing.xs, leading: Spacing.cardInner, bottom: Spacing.xs, trailing: Spacing.pageH
        )
        rows.backgroundColor = AnycastColor.sandAlpha3
        rows.layer.cornerRadius = Radius.card
        rows.layer.cornerCurve = .continuous
        return rows
    }

    private static func makeStepper(
        minusLabel: String, plusLabel: String, onMinus: @escaping () -> Void, onPlus: @escaping () -> Void
    ) -> AnycastStepperView {
        AnycastStepperView(
            background: AnycastColor.sandAlpha4,
            tint: Theme.playerText,
            minusLabel: minusLabel,
            plusLabel: plusLabel,
            onMinus: onMinus,
            onPlus: onPlus
        )
    }

    private static func makeRow(title: String, subtitle: String?, trailing: [UIView]) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = TypographyV2.bodyLarge.font()
        titleLabel.textColor = Theme.playerText
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        let texts = UIStackView(arrangedSubviews: [titleLabel])
        texts.axis = .vertical
        texts.spacing = Spacing.xxs
        if let subtitle {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.font = TypographyV2.caption.font()
            subtitleLabel.textColor = Theme.playerSecondary
            subtitleLabel.adjustsFontForContentSizeCategory = true
            subtitleLabel.numberOfLines = 0
            texts.addArrangedSubview(subtitleLabel)
        }

        let row = UIStackView(arrangedSubviews: [texts] + trailing)
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Spacing.gap
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: Spacing.rowH - Spacing.md).isActive = true
        return row
    }

    private static func makeDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = AnycastColor.sandAlpha3
        divider.heightAnchor.constraint(equalToConstant: Spacing.hairline).isActive = true
        return divider
    }

    private func bindActions() {
        continuousSwitch.addAction(
            UIAction { [weak self] action in
                guard let self else { return }
                let sender = action.sender as? UISwitch ?? self.continuousSwitch
                self.context.playback.setContinuousPlaying(sender.isOn)
            },
            for: .valueChanged
        )
    }

    // MARK: - Steps

    private var speedIndex: Int {
        PlayerSliderMath.nearestIndex(for: Double(context.playback.speed), in: Self.speedStops)
    }

    private func stepSpeed(by delta: Int) {
        let target = speedIndex + delta
        guard Self.speedStops.indices.contains(target) else { return }
        context.playback.setSpeed(Float(Self.speedStops[target]))
        renderSpeed()
    }

    /// Dart parity (player.dart:1526-1537): the countdown stop is the
    /// NEAREST stop to the remaining minutes — not floor(ceil(minutes) / 10),
    /// which sits a full stop low through the back half of every window.
    private var countdownIndex: Int {
        let remainingMinutes: Double
        if let remaining = context.sleepTimer.remainingMilliseconds, remaining > 0 {
            remainingMinutes = Double(remaining) / 60_000
        } else {
            remainingMinutes = 0
        }
        let nearest = Int((remainingMinutes / 10).rounded())
        return min(max(nearest, 0), Self.countdownStops.count - 1)
    }

    /// K38 semantics live in the controller: index 0 (OFF) clears the
    /// countdown without touching playback; any other index restarts it.
    private func stepCountdown(by delta: Int) {
        let target = countdownIndex + delta
        guard Self.countdownStops.indices.contains(target) else { return }
        context.sleepTimer.selectSliderIndex(target)
        Haptics.timerSet()
        renderCountdown()
    }

    // MARK: - Rendering

    /// renderHtml semantics (formatters.dart:152-180): empty payload → the
    /// scroll area collapses; plain strings render as text; HTML routes
    /// through the shared renderer with the enclosure-URL cache key.
    private func renderDescription() {
        let episode = context.playback.currentEpisode
        let html = episode?.description ?? ""
        let cacheKey = episode?.enclosureUrl ?? "player-settings-none"
        guard cacheKey != renderedCacheKey else { return }
        renderedCacheKey = cacheKey

        if case .empty = HtmlText.displayPayload(for: html) {
            descriptionTextView.attributedText = nil
            return
        }
        let textView = descriptionTextView
        let key = cacheKey
        Task {
            await HTMLContentRenderer.playerShared.render(html, cacheKey: key, into: textView)
        }
    }

    private func renderSpeed() {
        let index = speedIndex
        speedValueLabel.text = PlayerSliderMath.speedText(Self.speedStops[index])
        speedStepper.setEnabled(minus: index > 0, plus: index < Self.speedStops.count - 1)
    }

    /// The remaining time ("40:00" / "1h"), refreshed every second by the
    /// ticker; "Off" when no countdown runs.
    private func renderCountdown() {
        let remaining = context.sleepTimer.remainingMilliseconds ?? -1
        countdownValueLabel.text = remaining > 0 ? TimeFormats.formatCountdown(remaining) : "Off"
        let index = countdownIndex
        countdownStepper.setEnabled(minus: remaining > 0, plus: index < Self.countdownStops.count - 1)
    }

    private func renderContinuous() {
        continuousSwitch.isOn = context.settingsBox.current.continuousPlaying
    }

    /// The Dart 1 s Timer.periodic that decrements the countdown only while
    /// playing lives in SleepTimerController; this ticker just re-reads it
    /// so the value label ticks down live (player.dart:1542-1543).
    private func startCountdownTicker() {
        guard countdownTicker == nil else { return }
        countdownTicker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.renderCountdown() }
        }
    }
}

/// Stop math for the speed and sleep-timer steppers (the Dart sliders'
/// SPEED 0.5–2.0 ×0.25 and COUNTDOWN 0–60 ×10 — `Slider(min:max:divisions:
/// 6)`, seven stops each). Kept free of UIKit so the AnycastAppTests suite
/// can pin the arithmetic.
enum PlayerSliderMath {

    /// `divisions` splits the range into divisions+1 stops
    /// (divisions 6 → 7 stops).
    static func stops(min: Double, max: Double, divisions: Int) -> [Double] {
        guard divisions > 0, max > min else { return [min] }
        return (0...divisions).map { min + (max - min) * Double($0) / Double(divisions) }
    }

    /// The stop a raw value snaps to (Material slider snap; ties go to the
    /// nearer lower-middle by distance compare).
    static func nearestIndex(for value: Double, in stops: [Double]) -> Int {
        guard stops.count > 1 else { return 0 }
        var best = 0
        var bestDistance = abs(value - stops[0])
        for (index, stop) in stops.enumerated().dropFirst() {
            let distance = abs(value - stop)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    /// Speed value text: "1×", "1.25×", "0.5×" (trailing zeros dropped).
    static func speedText(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "\(text)×"
    }
}
