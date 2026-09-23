import Foundation
import MediaPlayer
import UIKit
import Testing
@testable import AnycastKit

@MainActor
@Suite(.serialized)
struct AudioPolicyTests {

    // MARK: - K18 session policy

    final class FakeSessionBackend: AudioSessionController.Backend, @unchecked Sendable {
        enum Call: Equatable {
            case setCategory
            case activate
            case deactivate(notifyOthers: Bool)
        }

        private let lock = NSLock()
        private var _calls: [Call] = []
        private var _failDeactivate = false

        var calls: [Call] {
            lock.lock(); defer { lock.unlock() }
            return _calls
        }

        func failNextDeactivate() {
            lock.lock(); _failDeactivate = true; lock.unlock()
        }

        func setCategoryPlayback() throws {
            lock.lock(); _calls.append(.setCategory); lock.unlock()
        }

        func activate() throws {
            lock.lock(); _calls.append(.activate); lock.unlock()
        }

        func deactivate(notifyOthers: Bool) throws {
            lock.lock()
            _calls.append(.deactivate(notifyOthers: notifyOthers))
            let shouldThrow = _failDeactivate
            lock.unlock()
            if shouldThrow {
                // 560030880 ('!act') — another app holds the audio focus.
                throw NSError(domain: NSOSStatusErrorDomain, code: 560030880)
            }
        }

        func setInterruptionHandler(_ handler: @escaping @Sendable (AudioSessionController.Interruption) -> Void) {}
        func setRouteChangeHandler(_ handler: @escaping @Sendable (AudioSessionController.RouteChange) -> Void) {}
    }

    @Test("K18: startup sets category ONLY; first play activates; pause stays active; drained queue deactivates with notifyOthers and swallows 560030880")
    func sessionPolicy() {
        let backend = FakeSessionBackend()
        let controller = AudioSessionController(backend: backend)

        // Cold start: category only — never an activation (another app's
        // audio must keep playing).
        controller.configureAtStartup()
        #expect(backend.calls == [.setCategory])

        // Browsing without playing changes nothing.
        controller.configureAtStartup()
        #expect(backend.calls == [.setCategory])

        // First play activates; repeated plays do not re-activate.
        controller.activateForPlayback()
        controller.activateForPlayback()
        #expect(backend.calls == [.setCategory, .activate])

        // Pause keeps the session (lock-screen card survives).
        controller.activateForPlayback()
        #expect(backend.calls == [.setCategory, .activate])

        // Queue drained: deactivate with notifyOthers, swallowing the
        // focus-held error instead of surfacing it.
        backend.failNextDeactivate()
        controller.deactivate()
        #expect(backend.calls == [.setCategory, .activate, .deactivate(notifyOthers: true)])
    }

    @Test("K18: interruption / unplugged-route handlers pause; interruption end never auto-resumes")
    func sessionInterruptions() async {
        final class RecordingBackend: AudioSessionController.Backend, @unchecked Sendable {
            var interruption: (@Sendable (AudioSessionController.Interruption) -> Void)?
            var route: (@Sendable (AudioSessionController.RouteChange) -> Void)?
            func setCategoryPlayback() throws {}
            func activate() throws {}
            func deactivate(notifyOthers: Bool) throws {}
            func setInterruptionHandler(_ handler: @escaping @Sendable (AudioSessionController.Interruption) -> Void) {
                interruption = handler
            }
            func setRouteChangeHandler(_ handler: @escaping @Sendable (AudioSessionController.RouteChange) -> Void) {
                route = handler
            }
        }

        let backend = RecordingBackend()
        let controller = AudioSessionController(backend: backend)
        let pauseCount = L2ContractTests.Locked(0)
        controller.onShouldPause = { pauseCount.with { $0 += 1 } }

        backend.interruption?(.began)
        backend.route?(.oldDeviceUnavailable)
        // Interruption ended with shouldResume: the shipped app resumes
        // manually after a call — nothing automatic.
        backend.interruption?(.ended(shouldResume: true))
        // Unrelated route changes: no pause.
        backend.route?(.other)

        await Task.yield()
        #expect(pauseCount.with { $0 } == 2)
    }

    // MARK: - K1 remote-command contract + Now Playing info

    @Test("K1: lock screen exposes exactly rewind/toggle/ff ±10s + position; no track commands; NowPlayingInfo carries the old MediaItem fields")
    func remoteCommandContract() async throws {
        final class NoArtwork: NowPlayingController.ArtworkProviding {
            func artwork(for urlString: String?) async -> UIImage? { nil }
        }

        let controller = NowPlayingController(artworkProvider: NoArtwork())
        controller.attachRemoteCommands(NowPlayingController.RemoteCommands(
            skipBackward: {}, skipForward: {}, togglePlayPause: {}, changePlaybackPosition: { _ in }
        ))

        let center = MPRemoteCommandCenter.shared()
        #expect(center.skipBackwardCommand.preferredIntervals as? [NSNumber] == [NSNumber(value: 10.0)])
        #expect(center.skipForwardCommand.preferredIntervals as? [NSNumber] == [NSNumber(value: 10.0)])
        #expect(!center.nextTrackCommand.isEnabled, "no next-track command (the shipped app had none)")
        #expect(!center.previousTrackCommand.isEnabled, "no previous-track command")
        #expect(center.changePlaybackPositionCommand.isEnabled)

        controller.update(
            metadata: NowPlayingController.Metadata(
                title: "Episode 42",
                channelTitle: "The Channel",
                durationMilliseconds: 3_600_000,
                artworkURL: nil
            ),
            speed: 1.5,
            positionMilliseconds: 30_000,
            playing: true
        )

        let info = controller.currentInfo
        #expect(info[MPMediaItemPropertyTitle] as? String == "Episode 42")
        #expect(info[MPMediaItemPropertyAlbumTitle] as? String == "The Channel")
        #expect((info[MPMediaItemPropertyPlaybackDuration] as? Double) ?? 0 == 3600)
        #expect((info[MPNowPlayingInfoPropertyPlaybackRate] as? Double) ?? 0 == 1.5)
        #expect((info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double) ?? 0 == 30)

        controller.updatePlaybackState(positionMilliseconds: 61_000, speed: 1.5, playing: false)
        let paused = controller.currentInfo
        #expect((paused[MPNowPlayingInfoPropertyPlaybackRate] as? Double) ?? 1 == 0,
                "paused → rate 0 (the system renders the paused state)")
        #expect((paused[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double) ?? 0 == 61)
    }

    // MARK: - K38 sleep timer

    @Test("sleep timer: decrements only while playing; zero pauses once; slider OFF never pauses")
    func sleepTimer() async {
        var playing = true
        let paused = L2ContractTests.Locked(0)
        let timer = SleepTimerController(isPlaying: { playing })
        timer.onExpired = { paused.with { $0 += 1 } }

        // Only playing time counts.
        timer.setCountdown(minutes: 2)
        playing = false
        for _ in 0..<10 { timer.tick() }
        #expect(timer.countdownMinutes == 2, "paused time must not decrement")

        playing = true
        // 120 decrements reach zero; the pause fires on the following tick
        // (the Dart timer checks `<= 0` before decrementing).
        for _ in 0..<121 { timer.tick() }
        #expect(paused.with { $0 } == 1, "natural decay to zero pauses exactly once")
        #expect(timer.countdownMinutes == 0)
        for _ in 0..<5 { timer.tick() }
        #expect(paused.with { $0 } == 1, "OFF after expiry — no repeat pauses")

        // K38: dragging the slider to 0 (OFF) stops the countdown without
        // pausing; a fresh selection restarts cleanly.
        timer.setCountdown(minutes: 1)
        timer.selectSliderIndex(0)
        #expect(timer.countdownMinutes == 0)
        #expect(paused.with { $0 } == 1, "slider OFF must not pause")
        for _ in 0..<60 { timer.tick() }
        #expect(paused.with { $0 } == 1)

        timer.selectSliderIndex(6)
        #expect(timer.countdownMinutes == 60, "index 6 = 1 hour (G9 slider values)")
    }

    // MARK: - K19 artwork fallback order

    @Test("K19: artwork resolves the old cover cache first, then network, then memory")
    func artworkFallbackOrder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("artwork-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let covers = directory.appendingPathComponent("libCachedImageData", isDirectory: true)
        try FileManager.default.createDirectory(at: covers, withIntermediateDirectories: true)
        let meta = try await CacheMetaDatabase.openWritable(
            at: directory.appendingPathComponent("libCachedImageData.db"))

        func makeImage(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }
        }

        // The old app's layout: an indexed cover file under
        // Library/Caches/libCachedImageData/.
        let url = "https://x.example/cover.jpg"
        let fileName = "11111111-2222-1333-8444-555555555555.png"
        try makeImage(.systemRed).pngData()?.write(to: covers.appendingPathComponent(fileName))
        await meta.upsert(row: CacheMetaDatabase.CacheObjectRow(
            _id: nil, url: url, key: url, relativePath: fileName,
            eTag: nil, validTill: nil, touched: nil, length: nil
        ))

        let fetchCount = L2ContractTests.Locked(0)
        let networkImage = makeImage(.systemBlue)
        let provider = NowPlayingArtworkProvider(
            coverMeta: meta,
            coverDirectory: covers,
            fetchImage: { _ in
                fetchCount.with { $0 += 1 }
                return networkImage
            }
        )

        // 1. Local hit: the old app's cover cache answers, zero network
        //    (the resolved image then also lives in the memory cache).
        let local = await provider.artwork(for: url)
        #expect(local != nil)
        #expect(fetchCount.with { $0 } == 0)

        // 2. A cover the old app never cached: network answers…
        let uncached = "https://x.example/never-cached.jpg"
        let fetched = await provider.artwork(for: uncached)
        #expect(fetched != nil)
        #expect(fetchCount.with { $0 } == 1)

        // 3. …and the memory cache keeps it: the same URL never fetches again.
        _ = await provider.artwork(for: uncached)
        #expect(fetchCount.with { $0 } == 1)

        // No URL (episode without a cover): nothing fetched, nil returned.
        #expect(await provider.artwork(for: nil) == nil)
        #expect(fetchCount.with { $0 } == 1)
    }
}
