import UIKit
import AnycastKit

/// Live state shared by Channel, in-show search and global episode search.
@MainActor
enum ShowEpisodeActionGroup {
    static func refresh(_ controller: ListActionController, playback: PlaybackService, inPlaylist: Bool) {
        guard let id = controller.selectedID else { return }
        if let add = controller.groupView.button(for: "add") {
            add.setIcon(inPlaylist ? AppIcons.addedToList : AppIcons.addToList, tint: Theme.onSurface)
            add.disc.backgroundColor = inPlaylist ? AnycastColor.sandAlpha5 : AnycastColor.sandAlpha3
            add.accessibilityLabel = inPlaylist ? "In playlist" : "Add to playlist"
            add.isEnabled = !inPlaylist
        }
        guard let play = controller.groupView.button(for: "play") else { return }
        let overlay: PlayPauseIconControl
        if let existing = play.contentHost.subviews.compactMap({ $0 as? PlayPauseIconControl }).first {
            overlay = existing
        } else {
            overlay = PlayPauseIconControl(size: 24)
            overlay.isUserInteractionEnabled = false
            overlay.isAccessibilityElement = false
            overlay.translatesAutoresizingMaskIntoConstraints = false
            play.contentHost.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.centerXAnchor.constraint(equalTo: play.contentHost.centerXAnchor),
                overlay.centerYAnchor.constraint(equalTo: play.contentHost.centerYAnchor),
                overlay.widthAnchor.constraint(equalToConstant: overlay.size),
                overlay.heightAnchor.constraint(equalToConstant: overlay.size),
            ])
        }
        play.setDefaultContentHidden(true)
        overlay.update(snapshot: .init(
            enclosureURL: id, currentEnclosureURL: playback.currentEpisode?.enclosureUrl,
            isPlaying: playback.isPlaying, isLoading: playback.isLoading
        ), tint: Theme.onSurface)
        play.accessibilityLabel = overlay.accessibilityLabel
    }
}
