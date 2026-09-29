import Testing
import AnycastKit
@testable import Anycast

/// Playlist card right-text and progress-backdrop reducers
/// (card.dart:50-82) — the "xx remaining" minute format delegates to the
/// golden-pinned `TimeFormats`; these tests pin the SOURCE selection and
/// clamping.
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
        )) == "90m remaining")
        // 2h30m total, 30m in → exactly 120 minutes remaining → h+m form.
        #expect(PlaylistCardDisplay.rightText(input(
            isCurrent: true, livePosition: 30 * 60_000, liveDuration: 150 * 60_000
        )) == "2h 0m remaining")
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
        )) == "90m remaining")
        #expect(PlaylistCardDisplay.rightText(input(
            played: 15 * 60_000, duration: 45 * 60_000
        )) == "30m remaining")
    }

    @Test("Unplayed rows keep the generic duration • date meta")
    func unplayedRightText() {
        // 73-minute duration, pubDate 2 minutes before `now` → "2m ago"
        // via timeago en_short (90 s ≤ elapsed < 45 min).
        let now: Int64 = 1_800_000_000_000
        let text = PlaylistCardDisplay.rightText(input(
            played: 0, duration: 73 * 60_000, pubDate: now - 120_000, now: now
        ))
        #expect(text == "73m • 2m ago")
        // Zero duration degrades to the empty duration segment.
        let zero = PlaylistCardDisplay.rightText(input(
            played: 0, duration: 0, pubDate: now - 120_000, now: now
        ))
        #expect(zero == " • 2m ago")
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
