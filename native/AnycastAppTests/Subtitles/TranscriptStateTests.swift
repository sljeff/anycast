import Foundation
import Testing
@testable import Anycast

/// TranscriptStateReducer: the five-state mapping of the Dart `Subtitles`
/// widget (player.dart:681-891 + transcriptVisualState,
/// formatters.dart:118-150) across poll-status / row-phase combos.
struct TranscriptStateTests {

    @Test("No episode → unavailable")
    func unavailable() {
        let state = TranscriptStateReducer.reduce(
            hasEpisode: false,
            subtitleStatus: "succeeded",
            row: .loaded,
            translationStatus: "succeeded",
            translationRow: .loaded
        )
        #expect(state == .unavailable)
    }

    @Test("No row/status → prompt")
    func prompt() {
        let state = TranscriptStateReducer.reduce(
            hasEpisode: true,
            subtitleStatus: nil,
            row: .fetching,
            translationStatus: nil,
            translationRow: .idle
        )
        #expect(state == .prompt)
    }

    @Test("Polling statuses map directly")
    func pollStatuses() {
        func reduce(_ status: String?) -> TranscriptVisualState {
            TranscriptStateReducer.reduce(
                hasEpisode: true,
                subtitleStatus: status,
                row: .fetching,
                translationStatus: nil,
                translationRow: .idle
            )
        }
        #expect(reduce("processing") == .processing)
        #expect(reduce("failed") == .failed)
        // Unknown server strings take the Dart default branch.
        #expect(reduce("queued") == .failed)
    }

    @Test("succeeded + row phases")
    func rowPhases() {
        func reduce(_ row: TranscriptRowPhase) -> TranscriptVisualState {
            TranscriptStateReducer.reduce(
                hasEpisode: true,
                subtitleStatus: "succeeded",
                row: row,
                translationStatus: nil,
                translationRow: .idle
            )
        }
        #expect(reduce(.fetching) == .loading)
        #expect(reduce(.failed) == .loadFailed)
        // Unusable stored payload → Dart deletes the row and re-enters
        // processing (player.dart:779-787).
        #expect(reduce(.empty) == .processing)
        #expect(reduce(.loaded) == .ready(translation: .mono))
    }

    @Test("succeeded + loaded row: translation phases")
    func translationPhases() {
        func reduce(
            _ translationStatus: String?,
            _ translationRow: TranslationRowPhase
        ) -> TranscriptVisualState {
            TranscriptStateReducer.reduce(
                hasEpisode: true,
                subtitleStatus: "succeeded",
                row: .loaded,
                translationStatus: translationStatus,
                translationRow: translationRow
            )
        }
        #expect(reduce(nil, .idle) == .ready(translation: .mono))
        // K9: after 5 failures the URL leaves the loop — lyrics only, the
        // permanent "Translating" bar is gone.
        #expect(reduce("failed", .idle) == .ready(translation: .mono))
        #expect(reduce("processing", .idle) == .ready(translation: .translating))
        #expect(reduce("succeeded", .fetching) == .ready(translation: .loadingTranslation))
        #expect(reduce("succeeded", .idle) == .ready(translation: .loadingTranslation))
        #expect(reduce("succeeded", .failed) == .ready(translation: .translationUnavailable))
        #expect(reduce("succeeded", .loaded) == .ready(translation: .bilingual))
    }
}
