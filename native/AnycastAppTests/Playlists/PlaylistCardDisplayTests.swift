import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// Playlist card time-text and progress reducers (card.dart:50-82) — the
/// minute math delegates to the golden-pinned `TimeFormats`; these tests
/// pin the SOURCE selection, the "left" wording and clamping.
@MainActor
struct PlaylistCardDisplayTests {

    private func input(
        isCurrent: Bool = false,
        livePosition: Int64 = 0,
        liveDuration: Int64 = 0,
        played: Int64? = nil,
        duration: Int64? = nil,
        pubDate: Int64? = nil,
        now: Int64 = 1_800_000_000_000
    ) -> PlaylistCardDisplay.Input {
        PlaylistCardDisplay.Input(
            isCurrentEpisode: isCurrent,
            livePositionMilliseconds: livePosition,
            liveDurationMilliseconds: liveDuration,
            playedDurationMilliseconds: played,
            durationMilliseconds: duration,
            pubDateMilliseconds: pubDate,
            nowEpochMilliseconds: now
        )
    }

    // MARK: - Right text

    @Test("Current episode reads live positionData")
    func currentRightText() {
        // 2h total, 30m in → 90 minutes remaining; formatRemainingTime only
        // switches to h+m at ≥100 minutes (formatters.dart:66-70).
        #expect(PlaylistCardDisplay.rightText(input(
            isCurrent: true, livePosition: 30 * 60_000, liveDuration: 2 * 3_600_000
        )) == "90m left")
        // 2h30m total, 30m in → exactly 120 minutes remaining → h+m form.
        #expect(PlaylistCardDisplay.rightText(input(
            isCurrent: true, livePosition: 30 * 60_000, liveDuration: 150 * 60_000
        )) == "2h 0m left")
        // Played nothing yet: bare minutes.
        #expect(PlaylistCardDisplay.rightText(input(
            isCurrent: true, livePosition: 0, liveDuration: 73 * 60_000
        )) == "73m")
        // Unknown duration → empty (formatRemainingTime's zero guard).
        #expect(PlaylistCardDisplay.rightText(input(isCurrent: true)) == "")
    }

    @Test("Stored playedDuration drives non-current rows once playback started")
    func storedRightText() {
        // 90 minutes remaining < 100 → bare minutes (formatters.dart:66-70).
        #expect(PlaylistCardDisplay.rightText(input(
            played: 30 * 60_000, duration: 2 * 3_600_000
        )) == "90m left")
        #expect(PlaylistCardDisplay.rightText(input(
            played: 15 * 60_000, duration: 45 * 60_000
        )) == "30m left")
    }

    @Test("Unplayed rows show the duration only")
    func unplayedRightText() {
        let now: Int64 = 1_800_000_000_000
        let text = PlaylistCardDisplay.rightText(input(
            played: 0, duration: 73 * 60_000, pubDate: now - 120_000, now: now
        ))
        #expect(text == "73m")
        // Unknown duration → empty (the card then drops the separator).
        let zero = PlaylistCardDisplay.rightText(input(
            played: 0, duration: 0, pubDate: now - 120_000, now: now
        ))
        #expect(zero == "")
    }

    // MARK: - Detail Play capsule label

    @Test("Detail Play label: resume with time left, else play with the duration")
    func detailPlayLabel() {
        let resume = DetailViewController.PlayLabel.make(
            durationMilliseconds: 80 * 60_000, playedMilliseconds: 48 * 60_000
        )
        #expect(resume.title == "Resume · 32m left")
        #expect(abs(resume.fraction - 0.6) < 0.001)

        let fresh = DetailViewController.PlayLabel.make(durationMilliseconds: 80 * 60_000, playedMilliseconds: nil)
        #expect(fresh == DetailViewController.PlayLabel(title: "Play · 80m", fraction: 0))

        let unknown = DetailViewController.PlayLabel.make(durationMilliseconds: nil, playedMilliseconds: 5_000)
        #expect(unknown == DetailViewController.PlayLabel(title: "Play", fraction: 0))

        // Played past the end clamps to a full capsule.
        let over = DetailViewController.PlayLabel.make(
            durationMilliseconds: 30 * 60_000, playedMilliseconds: 35 * 60_000
        )
        #expect(over.title == "Resume · 0m left")
        #expect(over.fraction == 1)
    }

    // MARK: - Progress fraction (playbackProgress, formatters.dart:80-87)

    @Test("Current row fraction uses live data and clamps")
    func currentFraction() {
        #expect(PlaylistCardDisplay.progressFraction(input(
            isCurrent: true, livePosition: 30 * 60_000, liveDuration: 60 * 60_000
        )) == 0.5)
        #expect(PlaylistCardDisplay.progressFraction(input(
            isCurrent: true, livePosition: 90 * 60_000, liveDuration: 60 * 60_000
        )) == 1)
        #expect(PlaylistCardDisplay.progressFraction(input(
            isCurrent: true, livePosition: -5, liveDuration: 60 * 60_000
        )) == 0)
        #expect(PlaylistCardDisplay.progressFraction(input(isCurrent: true)) == 0)
    }

    @Test("Non-current rows use the stored playedDuration")
    func storedFraction() {
        #expect(PlaylistCardDisplay.progressFraction(input(
            played: 25 * 60_000, duration: 100 * 60_000
        )) == 0.25)
        #expect(PlaylistCardDisplay.progressFraction(input(played: nil, duration: nil)) == 0)
    }
}

// MARK: - Queue summary footer

@MainActor
struct PlaylistQueueSummaryTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A fixed locale and zone, so the expectation is built from the same
    /// formatter the production code receives (device short styles differ).
    private func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private func row(_ durationMinutes: Int64?, played: Int64? = nil) -> PlaylistQueueSummary.Row {
        PlaylistQueueSummary.Row(
            durationMilliseconds: durationMinutes.map { $0 * 60_000 },
            playedMilliseconds: played.map { $0 * 60_000 }
        )
    }

    private func expectedRest(after minutes: Double, speedText: String) -> String {
        let finish = now.addingTimeInterval(minutes * 60)
        return " left · done around \(formatter().string(from: finish)) at \(speedText)"
    }

    @Test("Under an hour reads minutes alone")
    func underAnHour() throws {
        let text = try #require(PlaylistQueueSummary.text(
            rows: [row(60, played: 18)], speed: 1, now: now, timeFormatter: formatter()
        ))
        #expect(text.emphasis == "42 m")
        #expect(text.rest == expectedRest(after: 42, speedText: "1×"))
        #expect(text.plain == "42 m" + expectedRest(after: 42, speedText: "1×"))
    }

    @Test("An hour or more reads hours and minutes, summed over the queue")
    func overAnHour() throws {
        let text = try #require(PlaylistQueueSummary.text(
            rows: [row(90), row(45, played: 15)], speed: 1, now: now, timeFormatter: formatter()
        ))
        #expect(text.emphasis == "2 h 0 m")
        #expect(text.rest == expectedRest(after: 120, speedText: "1×"))
    }

    @Test("Speed shortens the finish time and is named in the line")
    func speed() throws {
        let text = try #require(PlaylistQueueSummary.text(
            rows: [row(90)], speed: 1.5, now: now, timeFormatter: formatter()
        ))
        #expect(text.emphasis == "1 h 30 m", "the amount left is wall-clock independent")
        #expect(text.rest == expectedRest(after: 60, speedText: "1.5×"))
        // A nonsensical speed falls back to 1×.
        let fallback = try #require(PlaylistQueueSummary.text(
            rows: [row(30)], speed: 0, now: now, timeFormatter: formatter()
        ))
        #expect(fallback.rest == expectedRest(after: 30, speedText: "1×"))
    }

    @Test("Over-played and unknown rows contribute nothing")
    func clamping() throws {
        let rows = [row(10, played: 30), row(nil, played: 5), row(20)]
        #expect(PlaylistQueueSummary.remainingMilliseconds(rows: rows) == 20 * 60_000)
        let text = try #require(PlaylistQueueSummary.text(
            rows: rows, speed: 1, now: now, timeFormatter: formatter()
        ))
        #expect(text.emphasis == "20 m")
    }

    @Test("Empty and finished queues have no line")
    func hidden() {
        #expect(PlaylistQueueSummary.text(rows: [], speed: 1, now: now, timeFormatter: formatter()) == nil)
        #expect(PlaylistQueueSummary.text(
            rows: [row(10, played: 10), row(nil)], speed: 1, now: now, timeFormatter: formatter()
        ) == nil)
    }
}

// MARK: - Pull-up to History

@MainActor
struct PlaylistHistoryPullTests {

    @Test("Overscroll is measured from the real maximum offset")
    func overscroll() {
        // Content 1000, viewport 800, adjusted insets 100 top / 34 bottom:
        // the maximum offset is 1000 - 800 + 34 = 234.
        func over(_ offsetY: CGFloat, bottom: CGFloat = 34, content: CGFloat = 1000) -> CGFloat {
            PlaylistHistoryPull.overscroll(
                offsetY: offsetY, contentHeight: content, viewportHeight: 800,
                adjustedInsetTop: 100, adjustedInsetBottom: bottom
            )
        }
        #expect(over(0) == 0)
        #expect(over(234) == 0)
        #expect(over(270) == 36)
        // An open action group extends the bottom inset: the same offset is
        // then inside the content, not a pull.
        #expect(over(270, bottom: 154) == 0)
        #expect(over(354, bottom: 154) == 0)
        #expect(over(426, bottom: 154) == 72)
        // A short list rests at its minimum offset (-top), so any drag up
        // past it is a pull.
        #expect(over(-100, content: 300) == 0)
        #expect(over(-28, content: 300) == 72)
    }

    @Test("Progress runs 0…1 over 72 pt and a release opens only at full pull")
    func progressAndRelease() {
        #expect(PlaylistHistoryPull.progress(overscroll: 0) == 0)
        #expect(PlaylistHistoryPull.progress(overscroll: -20) == 0)
        #expect(PlaylistHistoryPull.progress(overscroll: 36) == 0.5)
        #expect(PlaylistHistoryPull.progress(overscroll: 72) == 1)
        #expect(PlaylistHistoryPull.progress(overscroll: 500) == 1)
        #expect(PlaylistHistoryPull.progress(overscroll: .infinity) == 0)
        #expect(!PlaylistHistoryPull.opensOnRelease(progress: 0.99))
        #expect(PlaylistHistoryPull.opensOnRelease(progress: 1))
    }
}
