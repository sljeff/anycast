import Foundation

/// Scroll-follow state machine for the lyrics view. The list follows the
/// active line until the user drags it; from then on it stays where they
/// left it (no timed auto-resume) until they ask to return through the
/// "Back to now" capsule. The view owns scrolling; this type only decides
/// the mode.
struct LyricsFollowStateMachine: Equatable {

    enum Mode: Equatable {
        /// Auto-following the active line.
        case following
        /// The user scrolled away; following is off until they return.
        case detached
    }

    enum Event: Equatable {
        case dragBegan
        case backToNowRequested
    }

    private(set) var mode: Mode = .following

    mutating func handle(_ event: Event) {
        switch event {
        case .dragBegan:
            mode = .detached
        case .backToNowRequested:
            mode = .following
        }
    }
}
