import Foundation
import UIKit
import os
import AnycastKit

/// App-Group share handoff (docs/migration/01 §7): the shipped extension
/// copies the shared file into the group container root and writes the
/// `[SharedMediaFile]` JSON under `ShareKey` (+ optional `ShareMessageKey`)
/// before redirecting via `ShareMedia-<bundleid>:share`. The main app reads
/// that payload directly — receive_sharing_intent is gone.
nonisolated enum ShareHandoff {

    /// Byte-compatible mirror of the extension's `SharedMediaFile`
    /// (native/ShareExtension/Sources/SharedMediaTypes.swift — the extension
    /// encodes its own copy; both stay field-for-field identical). Optionals
    /// are absent keys in the JSON, exactly what the extension's encoder
    /// emits for nil.
    struct SharedMediaFile: Codable, Equatable, Sendable {
        var path: String
        var mimeType: String? = nil
        var thumbnail: String? = nil
        var duration: Double? = nil
        var message: String? = nil
        var type: SharedMediaType
    }

    enum SharedMediaType: String, Codable, Sendable {
        case image, video, text, file, url
    }

    /// kUserDefaultsKey / kUserDefaultsMessageKey (SharedMediaTypes.swift).
    static let userDefaultsKey = "ShareKey"
    static let userDefaultsMessageKey = "ShareMessageKey"

    /// getMediaStream/getInitialMedia → `[SharedMediaFile]` (empty on any
    /// decode failure — treated as "nothing shared").
    static func sharedFiles(in defaults: UserDefaults) -> [SharedMediaFile] {
        guard let data = defaults.data(forKey: userDefaultsKey) else { return [] }
        return (try? JSONDecoder().decode([SharedMediaFile].self, from: data)) ?? []
    }

    /// ShareController.sharedFile — the FIRST entry only.
    static func firstFilePath(from files: [SharedMediaFile]) -> String? {
        files.first?.path
    }

    /// `_parseOPML` path handling (states/share.dart:63-74): a `file://`
    /// prefixed string is parsed as a URI and converted to a file path
    /// (percent-decoded once, like `Uri.parse(...).toFilePath()`); anything
    /// else is used verbatim as a path.
    static func resolveFileURL(fromPath path: String) -> URL? {
        var filePath = path
        if filePath.hasPrefix("file://") {
            filePath = String(filePath.dropFirst("file://".count))
            filePath = filePath.removingPercentEncoding ?? filePath
        }
        guard !filePath.isEmpty else { return nil }
        return URL(fileURLWithPath: filePath)
    }

    /// ReceiveSharingIntent.reset(): clears the stored payload so a later
    /// cold start does not replay the same handoff.
    static func clearStoredPayload(in defaults: UserDefaults) {
        defaults.removeObject(forKey: userDefaultsKey)
        defaults.removeObject(forKey: userDefaultsMessageKey)
    }
}

/// The `ShareHandoffPresenting` implementation (App/UIContext.swift):
/// consumes the redirect URL, reads the App Group payload, parses the OPML
/// and presents the ShareDialog. Long-lived like Dart's ShareController —
/// `UIContext.shareHandoffPresenter` is weak, so registration retains the
/// instance for the process lifetime (static, below).
@MainActor
final class ShareHandoffCoordinator: ShareHandoffPresenting {

    private static var retained: ShareHandoffCoordinator?

    /// Handoff diagnostics — the drop path below must stay observable.
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Anycast",
        category: "ShareHandoff"
    )

    /// Composition-root registration (AppEnvironment.installUIContext) —
    /// the one delegated App/ edit.
    static func register(on context: UIContext) {
        let coordinator = ShareHandoffCoordinator(context: context)
        retained = coordinator
        context.shareHandoffPresenter = coordinator
        coordinator.consumeDebugLaunchArgument()
    }

    private let context: UIContext
    private weak var currentDialog: ShareDialogViewController?

    private init(context: UIContext) {
        self.context = context
    }

    /// The `ShareMedia-<bundleid>` URL is only the redirect signal
    /// (redirectToHostApp, ShareViewController.swift:223-237); the payload
    /// lives in the App Group. Both arrival paths — cold start (queued in
    /// RootViewController until the shell installs) and warm (openURLContexts)
    /// — land here.
    func presentShareHandoff(for url: URL) {
        beginHandoff(fixtureURL: nil)
    }

    private func beginHandoff(fixtureURL: URL?) {
        // Dart stacked a dialog per event; a visible handoff dialog swallows
        // repeats (the dedupe precedent from LoginPromptCoordinator).
        guard currentDialog?.view.window == nil else { return }

        var fileURL = fixtureURL
        if fixtureURL == nil {
            if let defaults = UserDefaults(suiteName: AppConfiguration.appGroupID) {
                let files = ShareHandoff.sharedFiles(in: defaults)
                ShareHandoff.clearStoredPayload(in: defaults)
                if let path = ShareHandoff.firstFilePath(from: files) {
                    fileURL = ShareHandoff.resolveFileURL(fromPath: path)
                }
            }
        }

        guard let fileURL else {
            // No payload at all: Dart still opened ShareDialog, which showed
            // the empty state (states/share.dart:36-38 → widgets/share.dart:13).
            Task { await presentWhenReady(entries: []) }
            return
        }

        Task { [fileURL] in
            // File read + XML parse off the main actor.
            let entries = await Task.detached(priority: .userInitiated) {
                (try? OPMLParser.parse(fileURL: fileURL)) ?? []
            }.value
            await presentWhenReady(entries: entries)
        }
    }

    /// Cold-start parity: Dart delayed the dialog 2 s after launch
    /// (states/share.dart:52-56); here the retry loop waits for the scene's
    /// window instead, capped at the same 2 s.
    private func presentWhenReady(entries: [OPMLParser.Entry], attempt: Int = 0) async {
        if let presenter {
            let dialog = ShareDialogViewController(context: context, entries: entries)
            currentDialog = dialog
            presenter.present(dialog, animated: true)
            return
        }
        guard attempt < 10 else {
            // No silent drop: after the 2 s presenter-retry cap the handoff
            // never reaches a presenter — leave an error-level trace.
            Self.logger.error(
                "Share handoff dropped: no window presenter after \(attempt) retries (\(entries.count) parsed entries)"
            )
            return
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        await presentWhenReady(entries: entries, attempt: attempt + 1)
    }

    /// The top-most presenter over the key window of a foreground-ACTIVE
    /// scene — sheets stack (03 §1.2), and the handoff must cover whatever
    /// is on screen. Filtering the activation state keeps an unactivated
    /// iPad window from stealing the presentation.
    private var presenter: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
            ?? scenes.first?.keyWindow
        return window?.rootViewController?.topMostPresented()
    }

    // MARK: - DEBUG fixture handoff

    #if DEBUG
    /// Local stand-in for the (device-only) extension handoff:
    /// `-t9-share-handoff-fixture <path.opml>` feeds a fixture OPML through
    /// the exact same coordinator path. DEBUG builds only.
    private static let debugFixtureFlag = "-t9-share-handoff-fixture"
    #endif

    private func consumeDebugLaunchArgument() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: Self.debugFixtureFlag),
              arguments.indices.contains(index + 1)
        else { return }
        beginHandoff(fixtureURL: URL(fileURLWithPath: arguments[index + 1]))
        #endif
    }
}
