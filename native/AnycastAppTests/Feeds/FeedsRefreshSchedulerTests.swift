import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// The Inbox refresh trigger set as a pure scheduler model (feeds.dart:31-64
/// + states/feed_episode.dart:27-132, 03 §2.3): refreshOnStart, the 2 s
/// delayed auto fetch, the periodic auto fetch (DB default 300 s), pull,
/// and the Tab0 re-tap — with the auto paths' 1-minute throttle.
@MainActor
struct FeedsRefreshSchedulerTests {

    // MARK: - Manual clock

    @MainActor
    private final class ManualClock {
        var time: Date
        init(start: Date = Date(timeIntervalSince1970: 1_000_000)) { self.time = start }
        var now: Date { time }
        func advance(_ seconds: TimeInterval) { time = time.addingTimeInterval(seconds) }
    }

    private func makeGate(_ clock: ManualClock) -> InboxRefreshGate {
        InboxRefreshGate(now: { clock.now })
    }

    // MARK: - Trigger classification

    @Test("Only the autoFetch paths pass the 1-minute throttle")
    func triggerClassification() {
        #expect(!InboxRefreshTrigger.firstAppear.passesAutoThrottle)
        #expect(!InboxRefreshTrigger.pull.passesAutoThrottle)
        #expect(!InboxRefreshTrigger.tabRetapAtTop.passesAutoThrottle)
        #expect(InboxRefreshTrigger.delayedAuto.passesAutoThrottle)
        #expect(InboxRefreshTrigger.periodicAuto.passesAutoThrottle)
    }

    // MARK: - The trigger sequence of a cold start

    @Test("Cold start: first-appear fires; the 2 s delayed auto is throttled behind it")
    func coldStartSequence() {
        let clock = ManualClock()
        let gate = makeGate(clock)

        // refreshOnStart (feeds.dart:39) fires immediately.
        #expect(gate.permits(.firstAppear))
        // Future.delayed(2 s) → autoFetch: lastRefresh is 2 s old → skip.
        clock.advance(2)
        #expect(!gate.permits(.delayedAuto))
        // The skipped trigger did NOT move the stamp.
        #expect(gate.lastRefresh == clock.now.addingTimeInterval(-2))
    }

    @Test("First periodic tick at the DB default interval (300 s) fires")
    func firstPeriodicTick() {
        let clock = ManualClock()
        let gate = makeGate(clock)

        #expect(gate.permits(.firstAppear))
        clock.advance(InboxRefreshSchedule.autoRefreshInterval(from: .defaults(localeIdentifier: "en_US")))
        #expect(gate.permits(.periodicAuto))
        // autoFetch stamps lastRefresh before callRefresh.
        #expect(gate.lastRefresh == clock.now)
    }

    @Test("Periodic ticks closer than a minute to the last refresh are skipped")
    func periodicThrottle() {
        let clock = ManualClock()
        let gate = makeGate(clock)

        gate.markRefreshStarted()          // t = 0
        clock.advance(300)
        #expect(gate.permits(.periodicAuto))   // t = 300, stamps 300
        clock.advance(50)
        #expect(!gate.permits(.periodicAuto))  // 350: 50 s since 300
        clock.advance(9.9)
        #expect(!gate.permits(.periodicAuto))  // 359.9: 59.9 s since 300
        clock.advance(0.1)
        #expect(gate.permits(.periodicAuto))   // 360: exactly 60 s → allowed
    }

    @Test("Throttle boundary: 59.9 s blocked, 60.0 s allowed")
    func throttleBoundary() {
        let clock = ManualClock()
        let gate = makeGate(clock)

        gate.markRefreshStarted()
        clock.advance(59.9)
        #expect(!gate.permits(.delayedAuto))
        clock.advance(0.1)
        #expect(gate.permits(.delayedAuto))
    }

    @Test("With no lastRefresh the delayed auto fetch fires (fresh controller)")
    func freshControllerAutoFetch() {
        let gate = InboxRefreshGate()
        #expect(gate.lastRefresh == nil)
        #expect(gate.permits(.delayedAuto))
        #expect(gate.lastRefresh != nil)
    }

    // MARK: - Pull and Tab0 re-tap are unconditional

    @Test("Pull and Tab0 re-tap bypass the throttle at any time")
    func pullAndRetapBypass() {
        let clock = ManualClock()
        let gate = makeGate(clock)

        gate.markRefreshStarted()
        clock.advance(0.5)
        #expect(gate.permits(.pull))
        clock.advance(0.5)
        #expect(gate.permits(.tabRetapAtTop))
        // Only 1 s since the last refresh, both still fired.
        #expect(gate.lastRefresh == clock.now)
    }

    // MARK: - Cadences

    @Test("Auto-refresh interval uses the DB default caliber (300 s)")
    func intervalFromSettings() {
        #expect(InboxRefreshSchedule.autoRefreshInterval(from: .defaults(localeIdentifier: "en_US")) == 300)
        var settings = AppSettings.defaults(localeIdentifier: "en_US")
        settings.autoRefreshInterval = 60
        #expect(InboxRefreshSchedule.autoRefreshInterval(from: settings) == 60)
        settings.autoRefreshInterval = 1800
        #expect(InboxRefreshSchedule.autoRefreshInterval(from: settings) == 1800)
    }

    @Test("Cadence constants match the Dart timers")
    func cadences() {
        #expect(InboxRefreshSchedule.delayedAutoSeconds == 2)    // feed_episode.dart:34
        #expect(InboxRefreshSchedule.trimIntervalSeconds == 60)   // player.dart:451
        #expect(InboxRefreshGate.autoThrottleSeconds == 60)       // feed_episode.dart:113-114
    }
}
