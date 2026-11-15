import UIKit
import AnycastKit

/// Export subscriptions: the OPML of the shows followed, written to
/// Documents as "Anycast Subscriptions.opml" and handed to the share sheet.
/// Playlist, history and transcripts are not part of it.
@MainActor
enum SubscriptionExport {

    /// Writes the file; nil when the subscriptions cannot be read or the
    /// file cannot be written (sharing an empty or stale file would look
    /// like a valid backup).
    static func makeFile(database: AppDatabase, directory: URL) async -> URL? {
        guard let subscriptions = try? await database.subscriptionRepository().listAll(),
              !subscriptions.isEmpty
        else { return nil }
        let fileURL = directory.appendingPathComponent(ImportCopy.exportFileName)
        let written = await Task.detached(priority: .userInitiated) { () -> Bool in
            let opml = OPMLWriter.document(subscriptions: subscriptions)
            do {
                try opml.data(using: .utf8)?.write(to: fileURL, options: .atomic)
                return true
            } catch {
                return false
            }
        }.value
        return written ? fileURL : nil
    }

    /// Creates the file and opens the share sheet over `presenter`; a
    /// failure is reported with `onFailure`.
    static func present(
        from presenter: UIViewController,
        context: UIContext,
        sourceView: UIView,
        onFailure: @escaping @MainActor () -> Void
    ) {
        Task {
            guard let fileURL = await makeFile(database: context.database, directory: context.paths.documents) else {
                onFailure()
                return
            }
            let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = sourceView
            activity.popoverPresentationController?.sourceRect = sourceView.bounds
            presenter.present(activity, animated: true)
        }
    }
}
