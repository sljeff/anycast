import Testing
@testable import Anycast

/// Progress-bar clock strings (the audio_video_progress_bar
/// TimeLabelType.remainingTime port) and the MyProgressBar visual-state
/// ladder (formatters.dart:89-116).
struct PlayerProgressBarTests {

    @Test("Position labels render m:ss under an hour, h:mm:ss over")
    func positionText() {
        #expect(PlayerProgressClock.positionText(0) == "0:00")
        #expect(PlayerProgressClock.positionText(5_000) == "0:05")
        #expect(PlayerProgressClock.positionText(65_000) == "1:05")
        #expect(PlayerProgressClock.positionText(600_000) == "10:00")
        #expect(PlayerProgressClock.positionText(3_665_000) == "1:01:05")
        // Negative input clamps (never a "-0:xx" position label).
        #expect(PlayerProgressClock.positionText(-3_000) == "0:00")
    }

    @Test("Remaining labels are the negated remaining clock")
    func remainingText() {
        #expect(PlayerProgressClock.remainingText(positionMilliseconds: 5_000, durationMilliseconds: 65_000) == "-1:00")
        #expect(PlayerProgressClock.remainingText(positionMilliseconds: 0, durationMilliseconds: 65_000) == "-1:05")
        #expect(PlayerProgressClock.remainingText(positionMilliseconds: 0, durationMilliseconds: 3_600_000) == "-1:00:00")
        // Fully played → "-0:00"; over-played clamps the same way.
        #expect(PlayerProgressClock.remainingText(positionMilliseconds: 65_000, durationMilliseconds: 65_000) == "-0:00")
        #expect(PlayerProgressClock.remainingText(positionMilliseconds: 80_000, durationMilliseconds: 65_000) == "-0:00")
    }

    @Test("Visual-state ladder order and messages (Dart resolve order)")
    func visualState() {
        // No episode wins over everything.
        #expect(PlayerProgressVisualState.resolve(hasEpisode: false, isLoading: true, durationMilliseconds: 5) == .disabled)
        #expect(PlayerProgressVisualState.resolve(hasEpisode: false, isLoading: false, durationMilliseconds: 0) == .disabled)
        #expect(PlayerProgressVisualState.disabled.message == "Playback unavailable")
        #expect(!PlayerProgressVisualState.disabled.allowsSeek)

        #expect(PlayerProgressVisualState.resolve(hasEpisode: true, isLoading: true, durationMilliseconds: 5) == .loading)
        #expect(PlayerProgressVisualState.loading.message == "Loading…")
        #expect(!PlayerProgressVisualState.loading.allowsSeek)

        #expect(PlayerProgressVisualState.resolve(hasEpisode: true, isLoading: false, durationMilliseconds: 0) == .unknownDuration)
        #expect(PlayerProgressVisualState.unknownDuration.message == "Duration unavailable")
        #expect(!PlayerProgressVisualState.unknownDuration.allowsSeek)

        #expect(PlayerProgressVisualState.resolve(hasEpisode: true, isLoading: false, durationMilliseconds: 1) == .normal)
        #expect(PlayerProgressVisualState.normal.message == nil)
        #expect(PlayerProgressVisualState.normal.allowsSeek)
    }

    @Test("a11y summary composes position and duration")
    func accessibilityValue() {
        #expect(PlayerProgressClock.accessibilityValue(positionMilliseconds: 65_000, durationMilliseconds: 3_600_000) == "1:05 of 1:00:00")
    }
}
