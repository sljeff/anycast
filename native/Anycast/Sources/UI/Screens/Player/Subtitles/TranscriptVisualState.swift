import Foundation

/// Five-state panel reducer for the player's transcript page
/// (lib/pages/player.dart `Subtitles` + `transcriptVisualState`,
/// lib/utils/formatters.dart:118-150).
///
/// The Dart truth derives the panel from (episode present, subtitle poll
/// status, row fetch outcome, translation poll status, translation row
/// fetch outcome). Polling itself lives in the poll controllers; this type
/// is the pure view-state mapping only.
enum TranscriptVisualState: Equatable {

    /// No playable episode (url empty) — "Transcript unavailable".
    case unavailable

    /// No subtitle row for the episode — the generate prompt.
    case prompt

    /// Transcription running (poll status "processing", or a stored row
    /// with an unusable payload — the Dart path deletes the row and shows
    /// processing).
    case processing

    /// Server said "failed" (or an unknown status string — the Dart
    /// default branch).
    case failed

    /// Row fetch in flight after status "succeeded".
    case loading

    /// Row fetch threw (or the stored payload failed to decode).
    case loadFailed

    /// Transcript row loaded; the lyrics area with a per-translation phase.
    case ready(translation: TranslationPhase)
}

/// Translation sub-state of `.ready` (player.dart:821-885).
enum TranslationPhase: Equatable {

    /// Lyrics only — no translation in progress, failed (K9 5-strike), or
    /// same-language skip.
    case mono

    /// Translation poll status "processing" — lyrics + spinner
    /// "Translating transcript…".
    case translating

    /// Translation status "succeeded", row fetch in flight —
    /// "Loading translation…".
    case loadingTranslation

    /// Translation row fetch failed — "Translation unavailable".
    case translationUnavailable

    /// Translation row loaded — bilingual lyrics.
    case bilingual
}

/// Row fetch phases. `.empty` mirrors the Dart cleanup: a stored row whose
/// payload is null/blank/"null" gets deleted and the panel falls back to
/// processing (player.dart:779-787).
enum TranscriptRowPhase: Equatable {
    case fetching
    case failed
    case empty
    case loaded
}

enum TranslationRowPhase: Equatable {
    case idle
    case fetching
    case failed
    case loaded
}

enum TranscriptStateReducer {

    /// `transcriptVisualState` plus the row-level wrapper states of the
    /// `Subtitles` widget.
    static func reduce(
        hasEpisode: Bool,
        subtitleStatus: String?,
        row: TranscriptRowPhase,
        translationStatus: String?,
        translationRow: TranslationRowPhase
    ) -> TranscriptVisualState {
        guard hasEpisode else { return .unavailable }
        guard let subtitleStatus else { return .prompt }

        switch subtitleStatus {
        case "processing":
            return .processing
        case "failed":
            return .failed
        case "succeeded":
            switch row {
            case .failed:
                return .loadFailed
            case .fetching:
                return .loading
            case .empty:
                // Dart deletes the unusable row and re-enters processing.
                return .processing
            case .loaded:
                return .ready(translation: translationPhase(
                    translationStatus: translationStatus,
                    translationRow: translationRow
                ))
            }
        default:
            // Unknown server strings land on the failed panel (Dart default).
            return .failed
        }
    }

    private static func translationPhase(
        translationStatus: String?,
        translationRow: TranslationRowPhase
    ) -> TranslationPhase {
        switch translationStatus {
        case "succeeded":
            switch translationRow {
            case .failed:
                return .translationUnavailable
            case .loaded:
                return .bilingual
            // The poller only reports "succeeded" once a row exists, so
            // .idle cannot be observed in practice; it maps to the loading
            // panel like an in-flight fetch.
            case .idle, .fetching:
                return .loadingTranslation
            }
        case "processing":
            return .translating
        default:
            return .mono
        }
    }
}
