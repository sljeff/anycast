import UIKit
import AnycastKit

/// Player page 0 (PlayerSettings, player.dart:118-144 + the Settings widget
/// 1148-1372, 03 §2.10): the episode's HTML description fills a scroll area
/// (empty payload collapses it), with the settings block pinned at the
/// bottom — SPEED and COUNTDOWN thumb-value sliders (widget #5) and the
/// CONTINUOUS PLAY switch with its tap tooltip. SKIP SILENCE is deliberately
/// absent (decision K2 — no iOS public API; only CONTINUOUS PLAY remains).
final class SettingsPageViewController: UIViewController {

    private let context: UIContext
    private let observation = ObservationLoop()

    private let descriptionTextView = HTMLContentRenderer.makeTextView(
        linkTarget: HTMLContentRenderer.playerShared
    )
    private let scrollView = UIScrollView()
    private var renderedCacheKey: String?

    private let speedSlider = PlayerValueSlider(
        spec: .init(
            values: PlayerSliderMath.stops(min: 0.5, max: 2.0, divisions: 6),
            tickStyle: .allWhite
        ),
        initialIndex: 0,
        thumbText: PlayerSliderMath.speedThumbText
    )
    private let countdownSlider = PlayerValueSlider(
        spec: .init(
            values: SleepTimerController.sliderMinutes.map(Double.init),
            tickStyle: .whiteUpToActive
        ),
        initialIndex: 0,
        thumbText: { PlayerSliderMath.countdownThumbText(remainingMilliseconds: Int64($0)) }
    )
    private let continuousSwitch = UISwitch()
    private let tooltipButton = UIButton(type: .custom)
    private var tooltip: InlineTooltip?
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
        tooltip?.dismiss()
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

        let root = UIStackView(arrangedSubviews: [scrollView, buildSettingsBlock()])
        root.axis = .vertical
        root.spacing = 16
        root.isLayoutMarginsRelativeArrangement = true
        root.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Section labels are 12 pt comfortaa w700 white (player.dart:1156-1162);
    /// sliders get 8 pt vertical padding like the Dart Padding wrappers.
    private func buildSettingsBlock() -> UIView {
        func sectionLabel(_ text: String) -> UILabel {
            let label = UILabel()
            label.text = text
            label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
                for: UIFont(name: "Comfortaa-Bold", size: 12) ?? .systemFont(ofSize: 12, weight: .bold)
            )
            label.textColor = Theme.primaryLightMax
            label.adjustsFontForContentSizeCategory = true
            return label
        }

        let speedBlock = UIStackView(arrangedSubviews: [sectionLabel("SPEED"), speedSlider])
        speedBlock.axis = .vertical
        speedBlock.spacing = 8

        let countdownBlock = UIStackView(arrangedSubviews: [sectionLabel("COUNTDOWN"), countdownSlider])
        countdownBlock.axis = .vertical
        countdownBlock.spacing = 8

        tooltipButton.setImage(AppIcons.info, for: .normal)
        tooltipButton.tintColor = Theme.secondaryLabelGray
        tooltipButton.isAccessibilityElement = true
        tooltipButton.accessibilityLabel = "About continuous play"

        continuousSwitch.onTintColor = Theme.brandGreen
        continuousSwitch.isAccessibilityElement = true
        continuousSwitch.accessibilityLabel = "Continuous play"

        let continuousBlock = UIStackView(arrangedSubviews: [sectionLabel("CONTINUOUS PLAY"), continuousSwitch])
        continuousBlock.axis = .vertical
        continuousBlock.spacing = 8

        let switchRow = UIStackView(arrangedSubviews: [continuousBlock, tooltipButton])
        switchRow.axis = .horizontal
        switchRow.alignment = .top
        switchRow.distribution = .equalSpacing

        let settings = UIStackView(arrangedSubviews: [speedBlock, countdownBlock, switchRow])
        settings.axis = .vertical
        settings.spacing = 16
        return settings
    }

    private func bindActions() {
        speedSlider.onValueChanged = { [weak self] _, value in
            self?.context.playback.setSpeed(Float(value))
        }
        // K38 semantics live in the controller: index 0 (OFF) clears the
        // countdown without touching playback; any other index restarts it.
        countdownSlider.onValueChanged = { [weak self] index, _ in
            self?.context.sleepTimer.selectSliderIndex(index)
            self?.renderCountdown()
        }
        continuousSwitch.addAction(
            UIAction { [weak self] action in
                guard let self else { return }
                let sender = action.sender as? UISwitch ?? self.continuousSwitch
                self.context.playback.setContinuousPlaying(sender.isOn)
            },
            for: .valueChanged
        )
        tooltipButton.addAction(
            UIAction { [weak self] _ in self?.showTooltip() },
            for: .touchUpInside
        )
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
        let index = PlayerSliderMath.nearestIndex(
            for: Double(context.playback.speed), in: speedSlider.spec.values
        )
        speedSlider.select(index: index)
        speedSlider.refreshThumbText(remainingValue: speedSlider.value(at: index) ?? 1.0)
        speedSlider.accessibilityLabel = "Playback speed"
    }

    /// Slider position from the live countdown; thumb text shows the
    /// remaining time ("40:00" / "1h" / "OFF"), refreshed every second by
    /// the ticker.
    private func renderCountdown() {
        // Dart parity (player.dart:1526-1537): the Slider's value is
        // `countdownDuration.inMinutes` (a floor of the remaining time) and
        // the divisioned thumb snaps that to the NEAREST stop — not
        // floor(ceil(minutes) / 10), which sits a full stop low through the
        // back half of every window.
        let remainingMinutes: Double
        if let remaining = context.sleepTimer.remainingMilliseconds, remaining > 0 {
            remainingMinutes = Double(remaining) / 60_000
        } else {
            remainingMinutes = 0
        }
        let nearestIndex = Int((remainingMinutes / 10).rounded())
        let index = min(max(nearestIndex, 0), SleepTimerController.sliderMinutes.count - 1)
        countdownSlider.select(index: index)
        countdownSlider.refreshThumbText(
            remainingValue: Double(context.sleepTimer.remainingMilliseconds ?? -1)
        )
        countdownSlider.accessibilityLabel = "Sleep timer"
    }

    private func renderContinuous() {
        continuousSwitch.isOn = context.settingsBox.current.continuousPlaying
    }

    /// The Dart 1 s Timer.periodic that decrements the countdown only while
    /// playing lives in SleepTimerController; this ticker just re-reads it
    /// so the thumb label ticks down live (player.dart:1542-1543).
    private func startCountdownTicker() {
        guard countdownTicker == nil else { return }
        countdownTicker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.renderCountdown() }
        }
    }

    // MARK: - Tooltip (tap-triggered, 2 s — player.dart:1628-1636)

    private func showTooltip() {
        tooltip?.dismiss()
        let tip = InlineTooltip(text: "Auto play next episode after the current one ends.")
        tooltip = tip
        tip.show(above: tooltipButton, in: view, duration: 2.0) { [weak self] in
            self?.tooltip = nil
        }
    }
}

/// Minimal tap-tooltip: dark rounded bubble anchored above its trigger,
/// auto-dismissed after `duration` (the Dart Tooltip default dark surface).
@MainActor
private final class InlineTooltip {

    private let bubble = UIView()
    private let label = UILabel()
    private var dismissalTask: Task<Void, Never>?

    init(text: String) {
        label.text = text
        label.font = Typography.defaultText.font()
        label.textColor = Theme.primaryLightMax
        label.numberOfLines = 0
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true

        bubble.backgroundColor = .black.withAlphaComponent(0.87)
        bubble.layer.cornerRadius = 8
        bubble.layer.cornerCurve = .continuous
        bubble.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    func show(above anchor: UIView, in container: UIView, duration: TimeInterval, onDismiss: @escaping () -> Void) {
        container.addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.alpha = 0
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -6),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            bubble.centerXAnchor.constraint(equalTo: anchor.centerXAnchor),
            bubble.bottomAnchor.constraint(equalTo: anchor.topAnchor, constant: -8),
        ])
        UIView.animate(withDuration: 0.15) { self.bubble.alpha = 1 }
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.dismiss()
            onDismiss()
        }
    }

    func dismiss() {
        dismissalTask?.cancel()
        bubble.removeFromSuperview()
    }
}
