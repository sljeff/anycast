import UIKit
import AnycastKit

/// The playback-speed and sleep-timer buttons that flank the transport row
/// on both player pages (main and transcript): the two tonal buttons, their
/// menus and their rendering live here once, so the pages cannot drift.
/// Owns its own speed observation and the sleep countdown tick; hosts call
/// `install(in:)` once and forward `pageWillAppear` / `pageDidDisappear`.
final class PlayerSpeedSleepControls {

    private let context: UIContext
    private let observation = ObservationLoop()
    private var sleepTicker: Timer?

    let speedButton = AnycastIconButton(
        style: .tonal, icon: nil, accessibilityLabel: "Playback speed", glyphSize: 20
    )
    let sleepButton = AnycastIconButton(
        style: .tonal, icon: AppIcons.sleepTimer, accessibilityLabel: "Sleep timer", glyphSize: 20
    )

    /// The speed menu: the stepper's 0.5–2 ×0.25 stops, with the rarely
    /// used 0.5× set apart at the bottom.
    private static let speedStops = PlayerSliderMath.stops(min: 0.5, max: 2.0, divisions: 6)
    private static let sleepMinutes = [10, 20, 30, 45, 60]

    init(context: UIContext) {
        self.context = context
        for button in [speedButton, sleepButton] {
            button.configuration?.baseBackgroundColor = Theme.playerText.withAlphaComponent(0.08)
            button.configuration?.baseForegroundColor = Theme.playerText
            button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = TypographyV2.body.font().monospacedDigits()
                return outgoing
            }
            button.configuration?.titleLineBreakMode = .byClipping
            button.showsMenuAsPrimaryAction = true
        }
        speedButton.accessibilityIdentifier = "player-speed"
        sleepButton.accessibilityIdentifier = "player-sleep"
        speedButton.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.speedMenuElements() ?? [])
            },
        ])
        sleepButton.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.sleepMenuElements() ?? [])
            },
        ])
        renderSpeed()
        renderSleep()
        observation.track(
            read: { [weak self] in _ = self?.context.playback.speed },
            onChange: { [weak self] in self?.renderSpeed() }
        )
    }

    /// Speed at the leading end of the transport row, sleep at the trailing.
    func install(in transport: PlayerTransportView) {
        transport.setAccessories(leading: speedButton, trailing: sleepButton)
    }

    // MARK: - Page lifecycle

    func pageWillAppear() {
        renderSleep()
        // The sleep countdown lives in SleepTimerController; this only
        // re-reads it so the button's minutes tick down.
        guard sleepTicker == nil else { return }
        sleepTicker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.renderSleep() }
        }
    }

    func pageDidDisappear() {
        sleepTicker?.invalidate()
        sleepTicker = nil
    }

    deinit {
        MainActor.assumeIsolated { sleepTicker?.invalidate() }
    }

    // MARK: - Rendering

    private func renderSpeed() {
        let index = PlayerSliderMath.nearestIndex(for: Double(context.playback.speed), in: Self.speedStops)
        let text = PlayerSliderMath.speedText(Self.speedStops[index])
        guard speedButton.configuration?.title != text else { return }
        speedButton.configuration?.title = text
        speedButton.accessibilityValue = text
    }

    /// Off: outline moon in player text. End of episode: filled moon in
    /// primary. Counting down: the minutes replace the glyph (the button
    /// is one slot). Player text, not `Theme.onSurface`: the player is
    /// always dark, and onSurface follows the app appearance.
    private func renderSleep() {
        let timer = context.sleepTimer
        let remaining = timer.remainingMilliseconds ?? 0
        if remaining > 0 {
            sleepButton.setIcon(nil)
            sleepButton.configuration?.title = "\(timer.countdownMinutes)m"
            sleepButton.configuration?.baseForegroundColor = Theme.primary
            sleepButton.accessibilityValue = "\(timer.countdownMinutes) minutes left"
        } else {
            sleepButton.configuration?.title = nil
            let engaged = timer.stopsAtEpisodeEnd
            sleepButton.setIcon(engaged ? AppIcons.sleepTimerActive : AppIcons.sleepTimer)
            sleepButton.configuration?.baseForegroundColor = engaged ? Theme.primary : Theme.playerText
            sleepButton.accessibilityValue = engaged ? "End of episode" : "Off"
        }
    }

    // MARK: - Menus

    private func speedMenuElements() -> [UIMenuElement] {
        let current = PlayerSliderMath.nearestIndex(for: Double(context.playback.speed), in: Self.speedStops)
        let actions = Self.speedStops.enumerated().map { index, stop in
            UIAction(
                title: PlayerSliderMath.speedText(stop),
                state: index == current ? .on : .off
            ) { [weak self] _ in
                self?.context.playback.setSpeed(Float(stop))
                self?.renderSpeed()
            }
        }
        // Everyday speeds first; the slow 0.5× sits apart below them.
        return [
            UIMenu(title: "Playback speed", options: .displayInline, children: Array(actions.dropFirst())),
            UIMenu(options: .displayInline, children: [actions[0]]),
        ]
    }

    private func sleepMenuElements() -> [UIMenuElement] {
        let timer = context.sleepTimer
        let remaining = timer.remainingMilliseconds ?? 0
        let counting = remaining > 0
        let title = counting ? "Sleep timer · \(timer.countdownMinutes) min left" : "Sleep timer"

        var timerItems: [UIMenuElement] = [
            UIAction(title: "Off", state: !counting && !timer.stopsAtEpisodeEnd ? .on : .off) { [weak self] _ in
                self?.context.sleepTimer.stop()
                self?.renderSleep()
            },
        ]
        for minutes in Self.sleepMinutes {
            timerItems.append(UIAction(title: "\(minutes) minutes") { [weak self] _ in
                self?.context.sleepTimer.setCountdown(minutes: minutes)
                Haptics.timerSet()
                self?.renderSleep()
            })
        }
        let position = context.playback.positionData
        let left = max(position.durationMilliseconds - position.positionMilliseconds, 0)
        let endOfEpisode = UIAction(
            title: "End of episode",
            subtitle: left > 0 ? "\(Int((Double(left) / 60_000).rounded(.up))) min" : nil,
            state: timer.stopsAtEpisodeEnd ? .on : .off
        ) { [weak self] _ in
            self?.context.sleepTimer.setStopAtEpisodeEnd()
            Haptics.timerSet()
            self?.renderSleep()
        }
        timerItems.append(endOfEpisode)

        // Continuous play: what happens whenever an episode finishes.
        let continuous = context.playback.continuousPlaying
        let afterItems: [UIMenuElement] = [
            UIAction(title: "Play next in playlist", state: continuous ? .on : .off) { [weak self] _ in
                self?.context.playback.setContinuousPlaying(true)
            },
            UIAction(title: "Stop", state: continuous ? .off : .on) { [weak self] _ in
                self?.context.playback.setContinuousPlaying(false)
            },
        ]
        return [
            UIMenu(title: title, options: .displayInline, children: timerItems),
            UIMenu(title: "When an episode ends", options: .displayInline, children: afterItems),
        ]
    }
}
