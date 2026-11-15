import CoreGraphics
import Foundation

/// Which search segment a result sentence is about.
enum SearchResultSegment: Equatable {
    case channels
    case episodes
}

/// The one thing a result sentence can offer. `focusSearchField` is not a
/// button: both segments are empty, so the host puts the caret back in the
/// field instead of asking the user to choose.
enum SearchResultAction: Equatable {
    case showOtherSegment
    case retry
    case focusSearchField
}

/// The sentence and its single action for one segment. `title` is what the
/// label draws (a long query is shortened in the middle). `spokenTitle` is
/// the same sentence with the full query, which VoiceOver reads.
struct SearchResultPresentation: Equatable {
    var title: String
    var spokenTitle: String
    var action: SearchResultAction
    /// Nil when `action` is `focusSearchField`.
    var actionTitle: String?
    var actionAccessibilityLabel: String?

    var showsButton: Bool { actionTitle != nil }
}

/// Copy and the single next step for a search segment.
///
/// One sentence that names the query, and at most one button. The other
/// segment counts as empty only when its fetch has settled on zero rows.
/// Still loading, a failure, or a non-empty list all keep the "show the
/// other segment" button — switching there then shows that segment's own
/// sentence. Offline is not a separate sentence: the view model folds every
/// failure into `networkError`.
enum SearchResultState {

    /// Queries longer than this are drawn with the middle removed.
    static let echoLimit = 60
    private static let echoHead = 40
    private static let echoTail = 15

    /// Visible and spoken forms of `query` after trimming. The spoken form
    /// is the whole query; the visible form drops the middle past `echoLimit`
    /// characters (extended grapheme clusters, so a CJK character or an
    /// emoji counts as one).
    static func echoedQuery(_ query: String) -> (visible: String, spoken: String) {
        let spoken = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard spoken.count > echoLimit else { return (spoken, spoken) }
        let visible = "\(spoken.prefix(echoHead))…\(spoken.suffix(echoTail))"
        return (visible, spoken)
    }

    /// Word-wraps `text`, and breaks a token by character only when that
    /// token is wider than `lineWidth` and so cannot sit on a line of its
    /// own. `measure` is the rendered width of a string in the label's font.
    /// The spoken sentence does not use this.
    static func titleFittingLine(
        _ text: String,
        lineWidth: CGFloat,
        measure: (String) -> CGFloat
    ) -> String {
        guard lineWidth > 1 else { return text }
        var result = ""
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            let plain = token.replacingOccurrences(of: "\u{200B}", with: "")
            if measure(plain) > lineWidth {
                result += plain.map(String.init).joined(separator: "\u{200B}")
            } else {
                result += plain
            }
            token = ""
        }
        for character in text {
            if character.isWhitespace {
                flush()
                result.append(character)
            } else {
                token.append(character)
            }
        }
        flush()
        return result
    }

    static func searchingAnnouncement(query: String) -> String {
        "Searching for \(query.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// Nil while `phase` is loading or has rows — those are not result states.
    static func presentation(
        segment: SearchResultSegment,
        phase: SearchListPhase,
        otherPhase: SearchListPhase,
        query: String
    ) -> SearchResultPresentation? {
        let echo = echoedQuery(query)
        let visibleQuote = "“\(echo.visible)”"
        let spokenQuote = "“\(echo.spoken)”"
        switch phase {
        case .loading, .loaded:
            return nil
        case .networkError:
            return SearchResultPresentation(
                title: "Couldn’t load results for \(visibleQuote)",
                spokenTitle: "Couldn’t load results for \(spokenQuote)",
                action: .retry,
                actionTitle: "Retry",
                actionAccessibilityLabel: "Retry search for \(echo.spoken)"
            )
        case .noResults:
            if otherPhase == .noResults {
                return SearchResultPresentation(
                    title: "Nothing found for \(visibleQuote). Try another word.",
                    spokenTitle: "Nothing found for \(spokenQuote). Try another word.",
                    action: .focusSearchField,
                    actionTitle: nil,
                    actionAccessibilityLabel: nil
                )
            }
            switch segment {
            case .channels:
                return SearchResultPresentation(
                    title: "No channels for \(visibleQuote)",
                    spokenTitle: "No channels for \(spokenQuote)",
                    action: .showOtherSegment,
                    actionTitle: "Show episodes",
                    actionAccessibilityLabel: "Show episodes for \(echo.spoken)"
                )
            case .episodes:
                return SearchResultPresentation(
                    title: "No episodes for \(visibleQuote)",
                    spokenTitle: "No episodes for \(spokenQuote)",
                    action: .showOtherSegment,
                    actionTitle: "Show channels",
                    actionAccessibilityLabel: "Show channels for \(echo.spoken)"
                )
            }
        }
    }
}

/// When a submitted query is written to Recent.
///
/// A query is recorded the first time either segment of this search comes
/// back with at least one row. Zero rows and failures are not recorded, and
/// a query that is already in Recent is left where it is because this
/// returns false and the caller does not call `record`. A later hit in the
/// same search does not record a second time.
enum SearchRecentRule {

    static func shouldRecord(
        alreadyRecorded: Bool,
        channelsPhase: SearchListPhase,
        episodesPhase: SearchListPhase
    ) -> Bool {
        guard !alreadyRecorded else { return false }
        return hasHit(channelsPhase) || hasHit(episodesPhase)
    }

    static func hasHit(_ phase: SearchListPhase) -> Bool {
        if case .loaded(let count) = phase, count >= 1 { return true }
        return false
    }
}
