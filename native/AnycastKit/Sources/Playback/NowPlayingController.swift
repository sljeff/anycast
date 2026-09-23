import Foundation
import MediaPlayer
import UIKit

/// Lock screen / control center integration (K1, K19; docs/migration/04 §2,
/// 05 §5.2):
///
/// - The remote command set is EXACTLY the shipped app's: rewind −10 s /
///   play-pause toggle / fast-forward +10 s (`preferredIntervals = [10 s]`)
///   plus a draggable position. There are NO next/previous-track commands —
///   the "previous/next" buttons of the old app were ±10 s seeks, an
///   intentional podcast convention, replicated as-is.
/// - Now Playing metadata mirrors the old `MediaItem`: title = episode
///   title, album = channel title, duration = the RSS duration, rate = the
///   speed setting, artwork = the cover URL — with a local fallback (K19:
///   the old app had none, so weak networks showed no cover).
@MainActor
public final class NowPlayingController {

    public struct Metadata: Equatable, Sendable {
        public var title: String
        public var channelTitle: String?
        /// RSS-provided duration in milliseconds (may be nil — then the
        /// item carries no duration).
        public var durationMilliseconds: Int64?
        public var artworkURL: String?

        public init(title: String, channelTitle: String?,
                    durationMilliseconds: Int64?, artworkURL: String?) {
            self.title = title
            self.channelTitle = channelTitle
            self.durationMilliseconds = durationMilliseconds
            self.artworkURL = artworkURL
        }
    }

    /// Remote-command handlers, injected by `PlaybackService` wiring.
    public struct RemoteCommands {
        public var skipBackward: () -> Void          // −10 s
        public var skipForward: () -> Void           // +10 s
        public var togglePlayPause: () -> Void
        public var changePlaybackPosition: (Double) -> Void  // seconds

        public init(skipBackward: @escaping () -> Void,
                    skipForward: @escaping () -> Void,
                    togglePlayPause: @escaping () -> Void,
                    changePlaybackPosition: @escaping (Double) -> Void) {
            self.skipBackward = skipBackward
            self.skipForward = skipForward
            self.togglePlayPause = togglePlayPause
            self.changePlaybackPosition = changePlaybackPosition
        }
    }

    /// K19 artwork resolution: local cover-cache file first, then network,
    /// memory-cached afterwards.
    public protocol ArtworkProviding: Sendable {
        func artwork(for urlString: String?) async -> UIImage?
    }

    private let artworkProvider: ArtworkProviding
    private var cachedArtworkURL: String?
    private var currentMetadata = Metadata(title: "", channelTitle: nil,
                                           durationMilliseconds: nil, artworkURL: nil)
    private var currentSpeed: Float = 1.0
    private var currentlyPlaying = false
    private var currentPositionSeconds: Double = 0
    private var commandsAttached = false
    private var artworkLoadTask: Task<Void, Never>?

    public init(artworkProvider: ArtworkProviding) {
        self.artworkProvider = artworkProvider
    }

    /// Wires the command center. Idempotent (test + production safety).
    public func attachRemoteCommands(_ commands: RemoteCommands) {
        let center = MPRemoteCommandCenter.shared()

        // K1: ±10 s exactly — the intervals shown by the system UI.
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: 10.0)]
        center.skipBackwardCommand.addTarget { _ in
            commands.skipBackward()
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: 10.0)]
        center.skipForwardCommand.addTarget { _ in
            commands.skipForward()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            commands.togglePlayPause()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            commands.changePlaybackPosition(positionEvent.positionTime)
            return .success
        }

        // The shipped app exposed NO track commands; make that explicit
        // rather than relying on registration defaults.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false

        commandsAttached = true
    }

    public var remoteCommandsAttached: Bool { commandsAttached }

    /// Full metadata refresh — called the moment a load is INITIATED
    /// (the old `mediaItem` was updated before loading finished; the
    /// ordering is pinned by 08 §12.2).
    public func update(metadata: Metadata, speed: Float, positionMilliseconds: Int64, playing: Bool) {
        currentMetadata = metadata
        currentSpeed = speed
        currentlyPlaying = playing
        currentPositionSeconds = Double(positionMilliseconds) / 1000
        publishNowPlayingInfo(artwork: nil)

        // K19: resolve artwork asynchronously, local-first; publish again
        // when (and only when) it arrives.
        if cachedArtworkURL == metadata.artworkURL { return }
        let urlString = metadata.artworkURL
        artworkLoadTask?.cancel()
        artworkLoadTask = Task { [weak self] in
            guard let self, let urlString else { return }
            let image = await self.artworkProvider.artwork(for: urlString)
            guard !Task.isCancelled else { return }
            self.cachedArtworkURL = urlString
            self.publishNowPlayingInfo(artwork: image.map(Self.makeArtwork))
        }
    }

    public func updatePlaybackState(positionMilliseconds: Int64, speed: Float, playing: Bool) {
        currentPositionSeconds = Double(positionMilliseconds) / 1000
        currentSpeed = speed
        currentlyPlaying = playing
        publishNowPlayingInfo(artwork: nil)
    }

    public func updateSpeed(_ speed: Float) {
        currentSpeed = speed
        publishNowPlayingInfo(artwork: nil)
    }

    public var currentInfo: [String: Any] {
        MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    }

    /// MediaPlayer invokes the request handler on its OWN queue — the
    /// closure must not inherit MainActor isolation (a raw UIImage capture
    /// would isolate it and trip the queue assertion).
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        let box = SendableImage(image)
        return MPMediaItemArtwork(boundsSize: image.size) { _ in box.image }
    }

    private final class SendableImage: @unchecked Sendable {
        let image: UIImage
        init(_ image: UIImage) { self.image = image }
    }

    private func publishNowPlayingInfo(artwork: MPMediaItemArtwork?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentMetadata.title,
            MPMediaItemPropertyAlbumTitle: currentMetadata.channelTitle ?? "",
            MPMediaItemPropertyPlaybackDuration: (currentMetadata.durationMilliseconds.map { Double($0) / 1000 }) ?? 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentPositionSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: currentlyPlaying ? Double(currentSpeed) : 0.0,
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        } else if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork,
                  cachedArtworkURL == currentMetadata.artworkURL {
            info[MPMediaItemPropertyArtwork] = existing
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

/// K19: cover art with a local fallback. Order: the old app's cover cache
/// (`libCachedImageData` meta DB → file), then the network, then an
/// in-memory NSCache so repeated track changes stay offline-friendly.
public actor NowPlayingArtworkProvider: NowPlayingController.ArtworkProviding {

    private let coverMeta: CacheMetaDatabase
    private let coverDirectory: URL
    private let fetchImage: @Sendable (URL) async -> UIImage?
    private let memoryCache = NSCache<NSString, UIImage>()

    public init(
        coverMeta: CacheMetaDatabase,
        coverDirectory: URL,
        fetchImage: @escaping @Sendable (URL) async -> UIImage? = { url in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data)
            else { return nil }
            return image
        }
    ) {
        self.coverMeta = coverMeta
        self.coverDirectory = coverDirectory
        self.fetchImage = fetchImage
    }

    public func artwork(for urlString: String?) async -> UIImage? {
        guard let urlString, let url = URL(string: urlString) else { return nil }

        if let cached = memoryCache.object(forKey: urlString as NSString) {
            return cached
        }

        // 1. Local cover cache written by the old app (K19 fallback).
        if let row = await coverMeta.entry(forURL: urlString),
           let name = row.relativePath {
            let fileURL = coverDirectory.appendingPathComponent(name)
            if let image = UIImage(contentsOfFile: fileURL.path) {
                memoryCache.setObject(image, forKey: urlString as NSString)
                return image
            }
        }

        // 2. Network (the old app's only path — artwork by remote URL).
        if let image = await fetchImage(url) {
            memoryCache.setObject(image, forKey: urlString as NSString)
            return image
        }
        return nil
    }
}
