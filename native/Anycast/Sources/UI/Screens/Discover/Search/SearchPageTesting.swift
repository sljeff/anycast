#if DEBUG
import UIKit
import AnycastKit

/// Debug-only seams for search result tests and snapshot captures.
/// Release builds omit this extension. The stored focus count stays on the
/// page, under the same flag, because an extension cannot add storage.
extension SearchPageViewController {

    /// Runs this search against a script instead of `context.api`.
    func search(
        _ text: String,
        channels: @escaping @Sendable (String) async throws -> [SubscriptionRow],
        episodes: @escaping @Sendable (String) async throws -> [APIClient.EpisodeWithChannel]
    ) {
        performSearch(text, channels: channels, episodes: episodes)
    }

    /// Replaces the transport used by later `search` calls.
    func setSearchTransport(
        channels: @escaping @Sendable (String) async throws -> [SubscriptionRow],
        episodes: @escaping @Sendable (String) async throws -> [APIClient.EpisodeWithChannel]
    ) {
        fetchChannels = channels
        fetchEpisodes = episodes
    }

    var searchFieldForTests: UITextField { activeSearchField }

    var segmentPhases: (channels: SearchListPhase, episodes: SearchListPhase) {
        (viewModel.channelsPhase, viewModel.episodesPhase)
    }

    /// Selects a segment the way the tab strip does.
    func selectSegmentForTests(_ index: Int) {
        showSegment(index)
    }
}
#endif
