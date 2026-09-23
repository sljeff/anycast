import Foundation

/// Manual sleep timer (docs/migration/04 §1.7, decision K38):
///
/// - Seven slider positions OFF/10/20/30/40/50/60 minutes; a 1 s tick that
///   decrements ONLY while playing; reaching zero naturally pauses.
/// - K38: dragging the slider to 0 means OFF — it neither pauses nor stops
///   anything; only the countdown expiring on its own pauses playback.
/// - `autoSleepTimer` (time-window + countdown) stays a stored-but-dead
///   setting (K17: the trigger call site was commented out in the shipped
///   app; the field is read for schema compatibility and never activated).
@MainActor
public final class SleepTimerController {

    /// The slider's minute values, OFF first (G9: index → {OFF,10..60}).
    nonisolated public static let sliderMinutes: [Int] = [0, 10, 20, 30, 40, 50, 60]

    /// Remaining milliseconds; nil = OFF (the Dart `noCountdown` sentinel).
    public private(set) var remainingMilliseconds: Int64?
    /// Pauses playback when the countdown expires.
    public var onExpired: (() -> Void)?

    private var timer: Timer?
    private let isPlaying: () -> Bool

    public init(isPlaying: @escaping () -> Bool = { false }) {
        self.isPlaying = isPlaying
    }

    /// Minutes left for the UI ("COUNTDOWN" slider value; 0 = OFF).
    public var countdownMinutes: Int {
        guard let remaining = remainingMilliseconds, remaining > 0 else { return 0 }
        return Int(ceil(Double(remaining) / 60_000))
    }

    /// Slider selection. Index 0 (OFF) clears without touching playback
    /// (K38); any other index starts the countdown immediately.
    public func selectSliderIndex(_ index: Int) {
        let minutes = Self.sliderMinutes[min(max(index, 0), Self.sliderMinutes.count - 1)]
        if minutes == 0 {
            stop()
        } else {
            setCountdown(minutes: minutes)
        }
    }

    public func setCountdown(minutes: Int) {
        remainingMilliseconds = Int64(minutes) * 60_000
        startTimerIfNeeded()
    }

    public func stop() {
        remainingMilliseconds = nil
        timer?.invalidate()
        timer = nil
    }

    /// One second of the Dart `Timer.periodic(1s)`: only playing time
    /// counts; expiry pauses exactly once and switches OFF.
    public func tick() {
        guard let remaining = remainingMilliseconds else { return }
        if remaining <= 0 {
            remainingMilliseconds = nil
            timer?.invalidate()
            timer = nil
            onExpired?()
            return
        }
        guard isPlaying() else { return }
        remainingMilliseconds = remaining - 1_000
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
}
