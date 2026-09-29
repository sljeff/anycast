import Testing
import AnycastKit
@testable import Anycast

/// Slider stop math and thumb-text parity for the two player sliders
/// (SPEED and COUNTDOWN — widget #5). The SPEED thumb strings pin the Dart
/// `toStringAsFixed(1)` behavior exactly, rounded halves included.
struct PlayerSliderMathTests {

    @Test("Both sliders expose exactly 7 stops (divisions 6)")
    func sevenStops() {
        let speed = PlayerSliderMath.stops(min: 0.5, max: 2.0, divisions: 6)
        #expect(speed.count == 7)
        #expect(speed == [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])

        let countdown = PlayerSliderMath.stops(min: 0, max: 60, divisions: 6)
        #expect(countdown.count == 7)
        #expect(countdown == [0, 10, 20, 30, 40, 50, 60])

        // The countdown slider drives SleepTimerController indices, whose
        // own stop list (G9) must be the same values.
        #expect(SleepTimerController.sliderMinutes.map(Double.init) == countdown)
    }

    @Test("Raw values snap to the nearest stop")
    func snapping() {
        let speed = PlayerSliderMath.stops(min: 0.5, max: 2.0, divisions: 6)
        #expect(PlayerSliderMath.nearestIndex(for: 0.5, in: speed) == 0)
        #expect(PlayerSliderMath.nearestIndex(for: 1.0, in: speed) == 2)
        #expect(PlayerSliderMath.nearestIndex(for: 1.1, in: speed) == 2)   // closer to 1.0
        #expect(PlayerSliderMath.nearestIndex(for: 1.4, in: speed) == 4)   // closer to 1.5
        #expect(PlayerSliderMath.nearestIndex(for: 2.0, in: speed) == 6)
        // Out-of-range values clamp onto the end stops.
        #expect(PlayerSliderMath.nearestIndex(for: 0.0, in: speed) == 0)
        #expect(PlayerSliderMath.nearestIndex(for: 9.9, in: speed) == 6)
    }

    @Test("SPEED thumb text matches Dart toStringAsFixed(1) — halves away from zero")
    func speedThumbParity() {
        // Shipped Dart strings: 0.75 → "0.8", 1.25 → "1.3", 1.75 → "1.8".
        #expect(PlayerSliderMath.dartFixed1(0.5) == "0.5")
        #expect(PlayerSliderMath.dartFixed1(0.75) == "0.8")
        #expect(PlayerSliderMath.dartFixed1(1.0) == "1.0")
        #expect(PlayerSliderMath.dartFixed1(1.25) == "1.3")
        #expect(PlayerSliderMath.dartFixed1(1.5) == "1.5")
        #expect(PlayerSliderMath.dartFixed1(1.75) == "1.8")
        #expect(PlayerSliderMath.dartFixed1(2.0) == "2.0")

        for value in PlayerSliderMath.stops(min: 0.5, max: 2.0, divisions: 6) {
            #expect(PlayerSliderMath.speedThumbText(value) == PlayerSliderMath.dartFixed1(value))
        }
    }

    @Test("Speed stops round-trip through the service's Float API unchanged")
    func speedServiceMapping() {
        let stops = PlayerSliderMath.stops(min: 0.5, max: 2.0, divisions: 6)
        for stop in stops {
            // Every 0.25 step is exactly representable as Float and Double.
            #expect(Double(Float(stop)) == stop)
            // A persisted speed re-snaps to its own index (UI restore).
            let index = PlayerSliderMath.nearestIndex(for: stop, in: stops)
            #expect(stops[index] == stop)
        }
    }

    @Test("COUNTDOWN thumb text is the live remaining time, OFF when unset")
    func countdownThumbText() {
        #expect(PlayerSliderMath.countdownThumbText(remainingMilliseconds: nil) == "OFF")
        #expect(PlayerSliderMath.countdownThumbText(remainingMilliseconds: -1) == "OFF")
        #expect(PlayerSliderMath.countdownThumbText(remainingMilliseconds: 0) == "OFF")
        #expect(PlayerSliderMath.countdownThumbText(remainingMilliseconds: 60 * 60_000) == "1h")
        #expect(PlayerSliderMath.countdownThumbText(remainingMilliseconds: 40 * 60_000) == "40:00")
        #expect(PlayerSliderMath.countdownThumbText(remainingMilliseconds: 25 * 60_000 + 30_000) == "25:30")
    }
}
