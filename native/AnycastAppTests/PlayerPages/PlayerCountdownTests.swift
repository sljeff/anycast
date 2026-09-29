import Testing
import AnycastKit
@testable import Anycast

/// COUNTDOWN semantics end to end: the label formats (G9 golden parity via
/// TimeFormats.formatCountdown, OFF/1h boundaries included), the live
/// remaining → slider position mapping, and K38 (selecting OFF never
/// touches playback).
@MainActor
struct PlayerCountdownTests {

    @Test("Label formats match the Dart formatCountdown golden")
    func labelFormats() {
        #expect(TimeFormats.formatCountdown(-1) == "OFF")
        #expect(TimeFormats.formatCountdown(0) == "OFF")
        // 1 ms is still 0 whole seconds → OFF (Duration.inSeconds parity).
        #expect(TimeFormats.formatCountdown(1) == "OFF")
        #expect(TimeFormats.formatCountdown(1_000) == "00:01")
        #expect(TimeFormats.formatCountdown(59_999) == "00:59")
        #expect(TimeFormats.formatCountdown(60_000) == "01:00")
        #expect(TimeFormats.formatCountdown(10 * 60_000) == "10:00")
        #expect(TimeFormats.formatCountdown(59 * 60_000 + 59_000) == "59:59")
        // The boundary quirk: exactly 60 minutes renders "1h", not "60:00".
        #expect(TimeFormats.formatCountdown(60 * 60_000) == "1h")
    }

    @Test("Remaining time maps onto the slider position the controller defines")
    func sliderPositionFromRemaining() {
        let timer = SleepTimerController(isPlaying: { true })

        // OFF (nil) → position 0.
        #expect(timer.countdownMinutes == 0)
        #expect(Self.sliderIndex(for: timer) == 0)

        timer.setCountdown(minutes: 60)
        #expect(timer.remainingMilliseconds == 60 * 60_000 as Int64)
        #expect(timer.countdownMinutes == 60)
        #expect(Self.sliderIndex(for: timer) == 6)

        timer.setCountdown(minutes: 40)
        #expect(timer.countdownMinutes == 40)
        #expect(Self.sliderIndex(for: timer) == 4)

        // 39:01 remaining still ceils to the 40 stop (G9 ceil semantics).
        timer.setCountdown(minutes: 40)
        timer.tick() // playing → 39:59
        #expect(timer.countdownMinutes == 40)
        #expect(Self.sliderIndex(for: timer) == 4)
    }

    @Test("K38: dragging to OFF clears the countdown without pausing")
    func offDoesNotPause() {
        var pauseCalls = 0
        let timer = SleepTimerController(isPlaying: { true })
        timer.onExpired = { pauseCalls += 1 }

        timer.setCountdown(minutes: 30)
        #expect(timer.remainingMilliseconds == 30 * 60_000 as Int64)

        // The slider's OFF stop.
        timer.selectSliderIndex(0)
        #expect(timer.remainingMilliseconds == nil)
        #expect(timer.countdownMinutes == 0)
        // No expiry fired — only the natural countdown reaching zero pauses.
        #expect(pauseCalls == 0)
    }

    @Test("Only playing time decrements the countdown")
    func onlyPlayingTicks() {
        let timer = SleepTimerController(isPlaying: { false })
        timer.setCountdown(minutes: 10)
        timer.tick()
        timer.tick()
        #expect(timer.remainingMilliseconds == 10 * 60_000 as Int64)

        timer.selectSliderIndex(3)
        #expect(timer.remainingMilliseconds == 30 * 60_000 as Int64)
    }

    /// The page's index math over the controller's UI value.
    private static func sliderIndex(for timer: SleepTimerController) -> Int {
        min(max(timer.countdownMinutes / 10, 0), SleepTimerController.sliderMinutes.count - 1)
    }
}
