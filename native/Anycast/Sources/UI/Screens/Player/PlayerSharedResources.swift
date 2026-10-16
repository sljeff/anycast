import UIKit
import SafariServices
import AnycastKit

extension HTMLContentRenderer {

    /// The app-side shared renderer instance for player show notes (one
    /// per-episode in-memory parse cache per renderer). T0a's Detail
    /// currently constructs its own instance; unifying the two caches is a
    /// T11 follow-up if memory/parse duplication ever matters.
    static let playerShared = HTMLContentRenderer(onLinkTap: { url in
        // K7 registered enhancement: show-notes links open in-app through
        // SFSafariViewController (the Dart baseline had dead links).
        let safari = SFSafariViewController(url: url)
        safari.preferredBarTintColor = Theme.background
        safari.preferredControlTintColor = Theme.onSurface
        if let anchor = HTMLContentRenderer.topMostViewController() {
            anchor.present(safari, animated: true)
        }
    })

    /// The top-most view controller over the app's first FOREGROUND-ACTIVE
    /// window scene (sheets stack, 03 §1.2 — presentation must always walk
    /// up). Unactivated scenes can still carry windows; on iPad the first
    /// connected scene may be another app window whose key window is the
    /// wrong presentation target.
    private static func topMostViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .compactMap(\.keyWindow?.rootViewController)
            .first?
            .topMostPresented()
    }
}
