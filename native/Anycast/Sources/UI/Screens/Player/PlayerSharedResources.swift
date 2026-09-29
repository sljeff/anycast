import UIKit
import SafariServices
import AnycastKit

/// Palette-derived player rules shared by the player pages (kept pure for
/// tests; the channel page header can reuse them in T5).
enum PlayerPaletteRules {

    /// Channel-name color = getTextSafeColor(dominant) (formatters.dart:
    /// 139-153 at the 1.2.1 baseline): luminance < 0.2 folds to the shipped
    /// fallback green 0x10B981; otherwise the dominant itself.
    static func channelNameColor(dominantRGB: UInt32) -> UIColor {
        let safe = TextSafeColor.getTextSafeColor(argb: dominantRGB | 0xFF00_0000)
        return UIColor(
            red: CGFloat((safe >> 16) & 0xFF) / 255,
            green: CGFloat((safe >> 8) & 0xFF) / 255,
            blue: CGFloat(safe & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension HTMLContentRenderer {

    /// The app-side shared renderer instance for player show notes (one
    /// per-episode in-memory parse cache per renderer). T0a's Detail
    /// currently constructs its own instance; unifying the two caches is a
    /// T11 follow-up if memory/parse duplication ever matters.
    static let playerShared = HTMLContentRenderer(onLinkTap: { url in
        // K7 registered enhancement: show-notes links open in-app through
        // SFSafariViewController (the Dart baseline had dead links).
        let safari = SFSafariViewController(url: url)
        safari.preferredBarTintColor = Theme.primaryBackgroundDark
        safari.preferredControlTintColor = Theme.primaryLightMax
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
