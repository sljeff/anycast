import Foundation

/// Scroll-follow state machine for the lyrics view
/// (flutter_lyric 3.0.2 `LyricTouchMixin` under the player's
/// configuration: `selectLineResumeMode: neverResume`,
/// `selectLineResumeDuration: 300ms`, `activeLineResumeDuration: 3000ms`,
/// player.dart:988-990).
///
/// `neverResume` means the 300 ms selected-line resume never schedules —
/// after a drag the view stays where the user left it, and only the 3 s
/// active-line resume returns following. Timers live in the view; this
/// type decides what to schedule.
struct LyricsFollowStateMachine: Equatable {

    enum Mode: Equatable {
        /// Auto-following the active line.
        case following
        /// User-scrolled; the time bar is visible and following is off.
        case selecting
    }

    enum Event: Equatable {
        case dragBegan
        case dragEnded
        case activeResumeTimerFired
        case stopSelectionRequested
    }

    enum ResumeScheduling: Equatable {
        /// Leave any pending timer as-is.
        case none
        /// (Re)start the active-line resume timer (3 s).
        case startActiveResume
        /// Cancel the pending timer (a new drag supersedes it).
        case cancel
    }

    static let activeLineResumeMilliseconds: Int = 3_000
    /// Kept for parity documentation only: under `neverResume` the 300 ms
    /// selected-line resume never fires (player.dart:988-989).
    static let selectLineResumeMilliseconds: Int = 300

    private(set) var mode: Mode = .following
    /// True between dragEnded (or fling end) and the resume firing — a
    /// dragBegan after arming disarms it, so a late timer fire can never
    /// yank control away from an in-progress drag.
    private var resumeArmed = false

    mutating func handle(_ event: Event) -> ResumeScheduling {
        switch event {
        case .dragBegan:
            // onVerticalDragDown cancels the resume debounce and marks
            // selecting on drag start.
            mode = .selecting
            resumeArmed = false
            return .cancel

        case .dragEnded:
            // Finger lift / deceleration end: schedule the 3 s resume.
            mode = .selecting
            resumeArmed = true
            return .startActiveResume

        case .activeResumeTimerFired:
            // Guarded no-op unless the pending resume is still armed (a
            // drag that began after the timer was queued wins — dragBegan
            // disarms). A fired one-shot timer needs no cancel; the view
            // just clears its reference.
            guard mode == .selecting, resumeArmed else { return .none }
            mode = .following
            resumeArmed = false
            return .none

        case .stopSelectionRequested:
            // LyricController.stopSelection: immediate return to following.
            mode = .following
            resumeArmed = false
            return .cancel
        }
    }
}
