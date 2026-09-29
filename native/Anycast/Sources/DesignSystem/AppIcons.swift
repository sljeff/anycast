import UIKit

/// Centralized icon accessors. The Dart baseline mixes five icon packs
/// (03 §5.3); the native port maps them to the nearest SF Symbol, except the
/// four brand SVGs that live in the asset catalog as template images
/// (`BrandaiChat`, `BrandtablerTopology`, `BrandnewDoc`, `BrandaiTranscript`).
///
/// Mapping table (dart icon → SF Symbol):
///
///   Material                 → SF Symbol
///   home_rounded             → house.fill
///   video_library_rounded    → play.rectangle.on.rectangle
///                               (videos.fill is not offered on iOS 18)
///   search / search_rounded  → magnifyingglass
///   settings_rounded         → gearshape.fill
///   round_settings           → gearshape
///   replay_10                → gobackward.10
///   forward_30               → goforward.30
///   play_arrow_rounded       → play.fill
///   image                    → photo
///   image_not_supported      → photo (approximation; no slashed-photo symbol)
///   more_vert_rounded        → ellipsis
///   person                   → person
///   info                     → info.circle.fill
///   info_outline             → info.circle
///   exit_to_app              → rectangle.portrait.and.arrow.right
///   close                    → xmark
///   delete_outline           → trash
///   question_mark_rounded    → questionmark
///   check                    → checkmark
///   podcasts_rounded         → dot.radiowaves.left.and.right
///                               (podcast is not offered on iOS)
///
///   ic (Material round set)  → SF Symbol
///   round_podcasts           → dot.radiowaves.left.and.right
///   round_pause              → pause.fill
///   round_download           → arrow.down.circle
///   round_file_download      → arrow.down.circle
///   round_clear / clear      → xmark
///   round_playlist_add       → text.badge.plus
///   round_playlist_add_check → checklist
///   round_ios_share          → square.and.arrow.up
///   round_arrow_back         → chevron.left
///   round_add_circle_outline → plus.circle
///   round_help               → questionmark.circle
///   round_check_circle       → checkmark.circle.fill
///   round_sms_failed         → exclamationmark.bubble.fill
///   round_apple              → apple.logo
///   email                    → envelope
///   content_copy             → doc.on.doc
///   baseline_explore         → safari.fill
///   outline_explore          → safari
///   baseline_offline_share   → arrow.up.doc (export-to-file approximation)
///
///   icon_park_solid.check_one                → checkmark.circle.fill
///   ph.arrow_elbow_down_right_bold           → arrow.turn.down.right
///   FluentIcons.mail_inbox_all_24_filled     → tray.fill
///   FluentIcons.library_24_filled            → books.vertical.fill
///   MdiIcons.cloudSearch                     → magnifyingglass.circle
///   Remix.forward_30_fill                    → goforward.30
///
///   Ri.google_fill is a brand logo with no SF Symbol — the login task
///   bundles the Google "G" as an asset instead.
nonisolated enum AppIcons {

    // Tab bar (03 §1.1)
    static let home = symbol("house.fill")
    static let playlist = symbol("play.rectangle.on.rectangle")
    static let discover = symbol("magnifyingglass.circle")

    // PodcastsPage secondary tabs (03 §2.1)
    static let inbox = symbol("tray.fill")
    static let subscriptions = symbol("books.vertical.fill")

    // Cards & actions (03 §2.11 / §2.2)
    static let play = symbol("play.fill")
    static let pause = symbol("pause.fill")
    static let addToList = symbol("text.badge.plus")
    static let addedToList = symbol("checklist")
    static let remove = symbol("xmark")
    static let download = symbol("arrow.down.circle")
    static let downloadDone = symbol("checkmark.circle.fill")

    // Detail (03 §1.3 / §2.11)
    static let share = symbol("square.and.arrow.up")
    static let back = symbol("chevron.left")

    // Player (03 §2.10)
    static let replay10 = symbol("gobackward.10")
    static let forward30 = symbol("goforward.30")
    static let playerSettings = symbol("gearshape")
    static let playerMain = symbol("dot.radiowaves.left.and.right")

    // Settings & login (03 §2.13 / §2.14)
    static let settings = symbol("gearshape.fill")
    static let search = symbol("magnifyingglass")
    static let close = symbol("xmark")
    static let delete = symbol("trash")
    static let check = symbol("checkmark")
    static let person = symbol("person")
    static let signInOut = symbol("rectangle.portrait.and.arrow.right")
    static let info = symbol("info.circle.fill")
    static let infoOutline = symbol("info.circle")
    static let help = symbol("questionmark.circle")
    static let questionMark = symbol("questionmark")
    static let more = symbol("ellipsis")
    static let copy = symbol("doc.on.doc")
    static let explore = symbol("safari.fill")
    static let exploreOutline = symbol("safari")
    static let exportFile = symbol("arrow.up.doc")
    static let appleLogo = symbol("apple.logo")
    static let email = symbol("envelope")
    static let addCircle = symbol("plus.circle")
    static let checkCircle = symbol("checkmark.circle.fill")
    static let smsFailed = symbol("exclamationmark.bubble.fill")
    static let photo = symbol("photo")
    static let elbowIndent = symbol("arrow.turn.down.right")

    /// Brand SVGs from the Dart sources (template images; tint with tintColor).
    static let aiChat = UIImage(named: "BrandaiChat")
    static let topology = UIImage(named: "BrandtablerTopology")
    static let newDoc = UIImage(named: "BrandnewDoc")
    static let aiTranscript = UIImage(named: "BrandaiTranscript")

    /// Every SF Symbol name referenced above — the registration test asserts
    /// each resolves on the running OS (a typo would otherwise render blanks).
    static let symbolNames: [String] = [
        "house.fill", "play.rectangle.on.rectangle", "magnifyingglass.circle", "tray.fill",
        "books.vertical.fill", "play.fill", "pause.fill", "text.badge.plus",
        "checklist", "xmark", "arrow.down.circle", "checkmark.circle.fill",
        "square.and.arrow.up", "chevron.left", "gobackward.10",
        "goforward.30", "gearshape", "dot.radiowaves.left.and.right", "gearshape.fill",
        "magnifyingglass", "trash", "checkmark", "person",
        "rectangle.portrait.and.arrow.right", "info.circle.fill",
        "info.circle", "questionmark.circle", "questionmark", "ellipsis",
        "doc.on.doc", "safari.fill", "safari", "arrow.up.doc", "apple.logo",
        "envelope", "plus.circle", "exclamationmark.bubble.fill", "photo",
        "arrow.turn.down.right",
    ]

    private static func symbol(_ name: String) -> UIImage {
        guard let image = UIImage(systemName: name) else {
            assertionFailure("SF Symbol \(name) did not resolve")
            return UIImage()
        }
        return image
    }
}
