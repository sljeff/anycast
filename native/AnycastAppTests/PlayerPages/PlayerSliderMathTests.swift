import Testing
import AnycastKit
@testable import Anycast

/// Stop math for the player's speed and sleep-timer steppers (the Dart
/// SPEED and COUNTDOWN sliders' stops — widget #5).
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

    @Test("Speed value text drops trailing zeros")
    func speedText() {
        let texts = PlayerSliderMath.stops(min: 0.5, max: 2.0, divisions: 6).map(PlayerSliderMath.speedText)
        #expect(texts == ["0.5×", "0.75×", "1×", "1.25×", "1.5×", "1.75×", "2×"])
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
}
