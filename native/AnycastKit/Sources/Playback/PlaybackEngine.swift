import Foundation

/// The transport surface `PlaybackService` drives. The protocol exists so
/// the queue state machine (05 §5.1) can be tested against a scriptable
/// engine; `AVPlayerEngine` is the production implementation.
///
/// The Dart original (utils/audio_handler.dart) kept a single
/// `just_audio.AudioPlayer` fed one source at a time — never its playlist
/// APIs — so the native shape is one `AVPlayer` fed one item at a time.
@MainActor
public protocol PlaybackEngine: AnyObject {

    /// Machine events, delivered on the main actor. `positionTick` is the
    /// periodic time observer (the Dart `positionDataStream`).
    var events: (@MainActor (PlaybackEngineEvent) -> Void)? { get set }

    /// An item is attached (the Dart `audioSource != null` check).
    var hasItem: Bool { get }

    /// Current playback speed (the speed setting, applied while playing).
    var rate: Float { get }

    var positionMilliseconds: Int64 { get }

    /// Item duration when known (`_player.duration` — nil until the item
    /// reports it; the K4 crash family is fixed by treating nil as
    /// "unknown", never force-unwrapping).
    var durationMilliseconds: Int64? { get }

    var bufferedMilliseconds: Int64 { get }

    /// Attach a new single source and seek to the initial position — the
    /// Dart `autoSet` load (`setUrl`/`setFilePath` with
    /// `initialPosition:`), whose load future was deliberately discarded
    /// (loading failures surface through events, K6).
    func load(url: URL, initialPositionMilliseconds: Int64)

    func playImmediately()

    func pause()

    /// Seek with zero tolerance (progress-bar / ±10s semantics).
    func seek(toMilliseconds: Int64)

    /// The speed setting (0.5…2.0); applies on the next play and to a
    /// running item, pitch-preserved (`.timeDomain`).
    func setDesiredSpeed(_ speed: Float)
}

public enum PlaybackEngineEvent: Sendable {
    case playingChanged(Bool)
    case loadingChanged(Bool)
    /// `durationMilliseconds` is nil while the item duration is unknown
    /// (the Dart stream mapped nil to zero only at the UI edge).
    case positionTick(positionMilliseconds: Int64,
                      bufferedMilliseconds: Int64,
                      durationMilliseconds: Int64?)
    case completed
    /// Load or playback failure (K6: the old app had zero error handling —
    /// an error toast + manual retry replace silent buffering).
    case failed(String)
}
