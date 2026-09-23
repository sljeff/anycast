import AVFoundation
import Foundation

/// The production engine: one `AVPlayer`, one item at a time (docs/migration
/// 04 §1.2 — the app-layer queue is the database, never AVQueuePlayer).
///
/// - Position/buffering come from a periodic time observer on the main
///   queue (the Dart `positionDataStream`).
/// - Completion is `AVPlayerItemDidPlayToEndTime`; a failed item or a
///   `FailedToPlayToEndTime` error surfaces as `.failed` (K6).
/// - Speed sets `defaultRate` + live `rate`; pitch is preserved with
///   `.timeDomain` (04 §8/§9 — speech-optimized, 1/32–32×).
@MainActor
public final class AVPlayerEngine: PlaybackEngine {

    public var events: (@MainActor (PlaybackEngineEvent) -> Void)?

    private let player = AVPlayer()
    private var desiredSpeed: Float = 1.0
    // Observer tokens: removed from a nonisolated deinit (the underlying
    // AVPlayer/NSNotificationCenter APIs are documented thread-safe).
    nonisolated(unsafe) private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var endToken: (any NSObjectProtocol)?
    nonisolated(unsafe) private var failureToken: (any NSObjectProtocol)?

    public init() {
        let observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.emitTick(at: time)
            }
        }
        self.timeObserver = observer

        // Playing/loading state: AVPlayer.timeControlStatus covers playing
        // (.playing) and buffering (.waitingToPlayAtSpecifiedRate); item
        // status not-yet-ready is the "loading" leg of just_audio's
        // ProcessingState.loading.
        rateObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                self.events?(.playingChanged(player.timeControlStatus == .playing))
                self.events?(.loadingChanged(player.timeControlStatus == .waitingToPlayAtSpecifiedRate))
            }
        }

        let center = NotificationCenter.default
        endToken = center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                      object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.events?(.completed)
            }
        }
        failureToken = center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
                                          object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
            let message = reason?.localizedDescription ?? "playback failed"
            Task { @MainActor in
                self?.events?(.failed(message))
            }
        }
    }

    deinit {
        // AVPlayer/NSNotificationCenter APIs here are documented thread-safe;
        // deinit cannot hop to the main actor.
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        statusObservation?.invalidate()
        rateObservation?.invalidate()
        let center = NotificationCenter.default
        if let endToken { center.removeObserver(endToken) }
        if let failureToken { center.removeObserver(failureToken) }
    }

    public var hasItem: Bool { player.currentItem != nil }
    public var rate: Float { player.rate }
    public var desiredSpeedValue: Float { desiredSpeed }

    public var positionMilliseconds: Int64 {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds >= 0 else { return 0 }
        return Int64((seconds * 1000).rounded())
    }

    public var durationMilliseconds: Int64? {
        guard let seconds = player.currentItem?.duration.seconds,
              seconds.isFinite, seconds > 0 else { return nil }
        return Int64((seconds * 1000).rounded())
    }

    public var bufferedMilliseconds: Int64 {
        guard let item = player.currentItem else { return 0 }
        guard let range = item.loadedTimeRanges.first?.timeRangeValue else { return 0 }
        let seconds = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int64((seconds * 1000).rounded())
    }

    public func load(url: URL, initialPositionMilliseconds: Int64) {
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        player.replaceCurrentItem(with: item)
        events?(.loadingChanged(true))

        if initialPositionMilliseconds > 0 {
            let target = CMTime(value: CMTimeValue(initialPositionMilliseconds), timescale: 1000)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.events?(.loadingChanged(false))
                case .failed:
                    self.events?(.failed(item.error?.localizedDescription ?? "load failed"))
                @unknown default:
                    break
                }
            }
        }
    }

    public func playImmediately() {
        player.defaultRate = desiredSpeed
        player.play()
        if desiredSpeed != 1.0 {
            player.rate = desiredSpeed
        }
    }

    public func pause() {
        player.pause()
    }

    public func seek(toMilliseconds: Int64) {
        let target = CMTime(value: CMTimeValue(max(0, toMilliseconds)), timescale: 1000)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func setDesiredSpeed(_ speed: Float) {
        desiredSpeed = speed
        player.defaultRate = speed
        if player.timeControlStatus == .playing {
            player.rate = speed
        }
    }

    private func emitTick(at time: CMTime) {
        // CMTime is NaN/indefinite before an item's timeline exists.
        let seconds = time.seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        let position = Int64((seconds * 1000).rounded())
        events?(.positionTick(
            positionMilliseconds: position,
            bufferedMilliseconds: bufferedMilliseconds,
            durationMilliseconds: durationMilliseconds
        ))
    }
}
