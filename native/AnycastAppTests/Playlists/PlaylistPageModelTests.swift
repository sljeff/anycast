import Testing
import AnycastKit
@testable import Anycast

/// Per-playlist paging (playlists.dart:43-55, 03 §10.1): swipe-only page
/// switching with NO visible tab bar — the pure page model.
@MainActor
struct PlaylistPageModelTests {

    @Test("Single default playlist has no adjacent pages")
    func singlePlaylist() {
        let model = PlaylistPageModel(playlistIDs: [1])
        #expect(model.currentPlaylistID == 1)
        #expect(model.page(after: 0) == nil)
        #expect(model.page(before: 0) == nil)
    }

    @Test("Multiple playlists page in both directions")
    func multiplePlaylists() {
        let model = PlaylistPageModel(playlistIDs: [1, 7, 9], currentIndex: 1)
        #expect(model.page(before: 1) == 0)
        #expect(model.page(after: 1) == 2)
        #expect(model.page(before: 0) == nil)
        #expect(model.page(after: 2) == nil)
        #expect(model.currentPlaylistID == 7)
    }

    @Test("Empty playlist table has no current page")
    func empty() {
        let model = PlaylistPageModel(playlistIDs: [])
        #expect(model.currentPlaylistID == nil)
    }

    @Test("Rebuilding the playlist table preserves the visible page by id")
    func rebuildPreservesCurrent() {
        var model = PlaylistPageModel(playlistIDs: [1, 7], currentIndex: 1)
        model = model.replacingPlaylistIDs([1, 7, 12])
        #expect(model.currentIndex == 1)
        #expect(model.currentPlaylistID == 7)

        // The current playlist disappearing resets to the first page.
        model = model.replacingPlaylistIDs([1, 12])
        #expect(model.currentIndex == 0)
        #expect(model.currentPlaylistID == 1)
    }
}

/// Download indicator mapping (card.dart:232-275): live cache state →
/// manual download → disk truth, in that priority.
@MainActor
struct PlaylistDownloadDisplayTests {

    @Test("Unknown URL and nothing on disk: not downloaded")
    func notDownloaded() {
        #expect(PlaylistDownloadDisplay.display(cacheState: nil, manualProgress: nil, diskCached: false) == .notDownloaded)
    }

    @Test("Live play-driven progress drives the ring")
    func liveProgress() {
        #expect(PlaylistDownloadDisplay.display(cacheState: 0.25, manualProgress: nil, diskCached: false) == .downloading(0.25))
        #expect(PlaylistDownloadDisplay.display(cacheState: 1, manualProgress: nil, diskCached: false) == .downloaded)
    }

    @Test("Manual card downloads report when playback has no state")
    func manualProgress() {
        #expect(PlaylistDownloadDisplay.display(cacheState: nil, manualProgress: 0.5, diskCached: false) == .downloading(0.5))
        #expect(PlaylistDownloadDisplay.display(cacheState: nil, manualProgress: 1, diskCached: false) == .downloaded)
    }

    @Test("Cold-start disk cache shows the green check (CacheController.onInit)")
    func diskCached() {
        #expect(PlaylistDownloadDisplay.display(cacheState: nil, manualProgress: nil, diskCached: true) == .downloaded)
    }

    @Test("Live playback state outranks disk and manual")
    func priority() {
        #expect(PlaylistDownloadDisplay.display(cacheState: 0.4, manualProgress: 1, diskCached: true) == .downloading(0.4))
        #expect(PlaylistDownloadDisplay.display(cacheState: nil, manualProgress: 0.7, diskCached: true) == .downloading(0.7))
    }

    @Test("Progress clamps into 0…1")
    func clamping() {
        #expect(PlaylistDownloadDisplay.display(cacheState: 1.4, manualProgress: nil, diskCached: false) == .downloaded)
        #expect(PlaylistDownloadDisplay.display(cacheState: -0.2, manualProgress: nil, diskCached: false) == .downloading(0))
    }
}

/// AI transcribe four-state display + tap actions (play_icon.dart AIIcon,
/// playlists.dart:149-181).
@MainActor
struct AITranscriptDisplayTests {

    @Test("Status string mapping")
    func statusMapping() {
        #expect(AITranscriptDisplay.display(status: nil) == .default)
        #expect(AITranscriptDisplay.display(status: "processing") == .processing)
        #expect(AITranscriptDisplay.display(status: "succeeded") == .succeeded)
        #expect(AITranscriptDisplay.display(status: "failed") == .failed)
        // Server passthrough strings matched no Dart case — no-op taps.
        #expect(AITranscriptDisplay.display(status: "weird") == .unknown)
    }

    @Test("Tap actions per state, with the exact Dart toast copy")
    func actions() {
        #expect(AITranscriptAction.action(display: .default) == .requestTranscript)
        #expect(AITranscriptAction.action(display: .failed) == .removeStaleRecord)
        #expect(AITranscriptAction.action(display: .unknown) == AITranscriptAction.none)
        #expect(AITranscriptAction.action(display: .succeeded) == .toast("You can check the transcript when playing."))
        #expect(AITranscriptAction.action(display: .processing) == .toast("Generating transcript may take 2 ~ 5 minutes..."))
        #expect(AITranscriptAction.failedToastMessage == "Transcript generation failed, please try again later.")
    }

    @Test("Icons: sparkle default, SF check/bubble for terminal states")
    func icons() {
        #expect(AITranscriptDisplay.display(status: nil).icon == AppIcons.aiTranscript)
        #expect(AITranscriptDisplay.display(status: "processing").icon == AppIcons.aiTranscript)
        #expect(AITranscriptDisplay.display(status: "succeeded").icon == AppIcons.checkCircle)
        #expect(AITranscriptDisplay.display(status: "failed").icon == AppIcons.smsFailed)
    }
}
