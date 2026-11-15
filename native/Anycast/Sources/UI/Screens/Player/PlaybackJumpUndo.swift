import UIKit

/// The player's one jump grammar: tapping a transcript line, a chapter or a
/// timestamp in the notes seeks there and offers "Playing from 26:23 · Undo"
/// for a few seconds. This holds the last jump and its timeout; each page
/// does its own seek and shows the content in its status capsule.
@MainActor
final class PlaybackJumpUndo {

    struct Jump: Equatable {
        let previousMilliseconds: Int
        let targetMilliseconds: Int
    }

    /// How long the Undo stays after a jump.
    static let seconds: TimeInterval = 4

    private(set) var current: Jump?
    /// Fires whenever `current` appears, changes or goes away.
    var onChange: (() -> Void)?

    private var timer: Timer?

    func record(from previousMilliseconds: Int, to targetMilliseconds: Int) {
        current = Jump(previousMilliseconds: previousMilliseconds, targetMilliseconds: targetMilliseconds)
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.clear() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        onChange?()
    }

    /// Clears and returns the jump to undo.
    func take() -> Jump? {
        let jump = current
        clear()
        return jump
    }

    func clear() {
        timer?.invalidate()
        timer = nil
        guard current != nil else { return }
        current = nil
        onChange?()
    }

    /// The status capsule's "Playing from … · Undo" content, nil when idle.
    func capsuleContent(undo: @escaping () -> Void) -> TranscriptStatusCapsuleView.Content? {
        guard let current else { return nil }
        return .init(
            id: "undo-\(current.targetMilliseconds)",
            message: "Playing from \(LyricsTimestamp.string(milliseconds: current.targetMilliseconds))",
            action: ("Undo", undo)
        )
    }
}
