import AVFoundation
import Foundation

/// AVAudioSession policy (decision K18, docs/migration/06 §6, 05 §5.3):
///
/// - **Cold start must not interrupt other apps' audio.** The shipped app's
///   session activated only when playback started, so start-up merely sets
///   the category — `setCategory(.playback)` never grabs focus — and the
///   FIRST play is what activates the session.
/// - Pausing keeps the session active (the lock-screen Now Playing card
///   must survive a pause, matching the plugin behavior of the old build).
/// - Only a drained queue / explicit stop deactivates, with
///   `.notifyOthersOnDeactivation` so whatever the user listened to before
///   (Spotify, another podcast app) resumes — and the notorious error
///   560030880 (`!act` — another app holds the focus) is swallowed rather
///   than crashing.
/// - Interruptions (calls, Siri) pause playback and do NOT auto-resume —
///   the old app resumed manually after a call; removing an output route
///   (unplugging headphones) pauses explicitly (K18 enhancement: the old
///   app had zero handling).
@MainActor
public final class AudioSessionController {

    /// Abstracted for the policy unit tests (call order and gating, without
    /// a real audio session).
    public protocol Backend: AnyObject, Sendable {
        func setCategoryPlayback() throws
        func activate() throws
        /// Errors of `!act` (560030880) and friends are decided by the
        /// backend; the controller's contract is "deactivate never throws".
        func deactivate(notifyOthers: Bool) throws
        func setInterruptionHandler(_ handler: @escaping @Sendable (Interruption) -> Void)
        func setRouteChangeHandler(_ handler: @escaping @Sendable (RouteChange) -> Void)
    }

    public enum Interruption: Sendable, Equatable {
        case began
        case ended(shouldResume: Bool)
        case mediaServicesLost
        case mediaServicesReset
    }

    public enum RouteChange: Sendable, Equatable {
        case oldDeviceUnavailable
        case other
    }

    public enum State: Equatable, Sendable {
        case categoryOnly
        case active
        case inactive
    }

    public private(set) var state: State = .categoryOnly
    public var onShouldPause: (() -> Void)?
    /// Report hook (Sentry in the app): an activate() failure is visible —
    /// playback may be silent.
    public var onActivateFailure: ((String) -> Void)?

    private let backend: Backend
    private var didConfigureCategory = false

    public init(backend: Backend = AVAudioSessionBackend()) {
        self.backend = backend

        // Interruptions pause; no auto-resume after the call ends (05 §5.3:
        // manual resume is the shipped behavior).
        backend.setInterruptionHandler { [weak self] interruption in
            Task { @MainActor in
                switch interruption {
                case .began, .mediaServicesLost:
                    self?.onShouldPause?()
                case .mediaServicesReset:
                    self?.onShouldPause?()
                case .ended:
                    break
                }
            }
        }
        // Unplugged headphones / dropped Bluetooth: pause explicitly.
        backend.setRouteChangeHandler { [weak self] change in
            Task { @MainActor in
                guard change == .oldDeviceUnavailable else { return }
                self?.onShouldPause?()
            }
        }
    }

    /// Startup: category only, NEVER an activation (K18). Idempotent —
    /// the composition root may call it defensively.
    public func configureAtStartup() {
        guard !didConfigureCategory else { return }
        didConfigureCategory = true
        do {
            try backend.setCategoryPlayback()
            state = .categoryOnly
        } catch {
            onActivateFailure?("setCategory: \(error.localizedDescription)")
        }
    }

    /// Before the first play of a session. AVPlayer would implicitly
    /// activate under `.playback`; doing it explicitly makes activation
    /// failures observable.
    public func activateForPlayback() {
        guard state != .active else { return }
        do {
            try backend.activate()
            state = .active
        } catch {
            onActivateFailure?("activate: \(error.localizedDescription)")
        }
    }

    /// Queue drained / stopped: give the audio focus back, politely.
    public func deactivate() {
        guard state == .active else { return }
        // 560030880 and other deactivation quirks are expected on this
        // path — swallow, never surface.
        try? backend.deactivate(notifyOthers: true)
        state = .inactive
    }
}

/// Production backend over `AVAudioSession.sharedInstance()`.
public final class AVAudioSessionBackend: AudioSessionController.Backend, @unchecked Sendable {

    private let session = AVAudioSession.sharedInstance()

    public init() {}

    public func setCategoryPlayback() throws {
        try session.setCategory(.playback, mode: .default, options: [])
    }

    public func activate() throws {
        try session.setActive(true, options: [])
    }

    public func deactivate(notifyOthers: Bool) throws {
        try session.setActive(false,
                              options: notifyOthers ? .notifyOthersOnDeactivation : [])
    }

    public func setInterruptionHandler(_ handler: @escaping @Sendable (AudioSessionController.Interruption) -> Void) {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = AVAudioSession.InterruptionType(rawValue: raw ?? 0)
            switch type {
            case .began:
                handler(.began)
            case .ended:
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
                handler(.ended(shouldResume: options.contains(.shouldResume)))
            @unknown default:
                break
            }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification, object: nil, queue: .main
        ) { _ in handler(.mediaServicesLost) }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { _ in handler(.mediaServicesReset) }
    }

    public func setRouteChangeHandler(_ handler: @escaping @Sendable (AudioSessionController.RouteChange) -> Void) {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw ?? 0)
            handler(reason == .oldDeviceUnavailable ? .oldDeviceUnavailable : .other)
        }
    }
}
