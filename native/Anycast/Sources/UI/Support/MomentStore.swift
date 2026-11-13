import Foundation

/// A sentence the user kept from a transcript: the quote, where it came
/// from, and the position that replays it.
struct Moment: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    /// The episode's audio URL: the identity of the episode everywhere else
    /// in the app.
    var enclosureURL: String
    var rssFeedURL: String?
    var episodeTitle: String
    var showTitle: String
    var artworkURL: String?
    /// Where the sentence starts in the episode.
    var startMilliseconds: Int
    var text: String
    /// The aligned translation line, when the transcript had one.
    var translation: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        enclosureURL: String,
        rssFeedURL: String? = nil,
        episodeTitle: String,
        showTitle: String,
        artworkURL: String? = nil,
        startMilliseconds: Int,
        text: String,
        translation: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.enclosureURL = enclosureURL
        self.rssFeedURL = rssFeedURL
        self.episodeTitle = episodeTitle
        self.showTitle = showTitle
        self.artworkURL = artworkURL
        self.startMilliseconds = startMilliseconds
        self.text = text
        self.translation = translation
        self.createdAt = createdAt
    }
}

/// The user's kept moments: one versioned JSON file in Application Support.
///
/// Moments are user content that can grow, so they live in a file of their
/// own rather than in `UserDefaults`, and they stay out of the SQLite
/// database (no schema change). The file is `{"version": 1, "moments": [...]}`,
/// newest first, written atomically after every change.
///
/// A file that cannot be read (corrupt JSON, or a `version` this build does
/// not know) is never overwritten: it is renamed aside next to the original
/// (`moments.unreadable-<timestamp>.json`) and the store starts empty.
final class MomentStore {

    static let currentVersion = 1

    /// Posted on the main thread after the list changes.
    static let didChange = Notification.Name("MomentStore.didChange")

    enum AddResult: Equatable {
        case added
        /// The same episode and start are already kept.
        case duplicate
        /// The file could not be written; nothing was kept.
        case failed
    }

    /// The app's store, at `Application Support/Moments/moments.json`.
    static let shared = MomentStore(fileURL: defaultFileURL)

    static var defaultFileURL: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Moments", isDirectory: true)
            .appendingPathComponent("moments.json")
    }

    private struct File: Codable {
        var version: Int
        var moments: [Moment]
    }

    /// Only the version, so a file written by a newer build is recognised
    /// even when its moments no longer decode.
    private struct Header: Decodable {
        var version: Int
    }

    private let fileURL: URL

    /// Every kept moment, newest first.
    private(set) var all: [Moment] = []

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    func contains(episode enclosureURL: String, start startMilliseconds: Int) -> Bool {
        all.contains { $0.enclosureURL == enclosureURL && $0.startMilliseconds == startMilliseconds }
    }

    /// Keeps `moment` at the top. A moment with the same episode and start
    /// is not kept twice.
    @discardableResult
    func add(_ moment: Moment) -> AddResult {
        guard !contains(episode: moment.enclosureURL, start: moment.startMilliseconds) else {
            return .duplicate
        }
        return commit(all.inserting(moment, at: 0)) ? .added : .failed
    }

    @discardableResult
    func remove(id: Moment.ID) -> Bool {
        guard all.contains(where: { $0.id == id }) else { return false }
        return commit(all.filter { $0.id != id })
    }

    @discardableResult
    func remove(episode enclosureURL: String, start startMilliseconds: Int) -> Bool {
        let kept = all.filter { !($0.enclosureURL == enclosureURL && $0.startMilliseconds == startMilliseconds) }
        guard kept.count != all.count else { return false }
        return commit(kept)
    }

    // MARK: - File

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = Self.decoder
        guard let header = try? decoder.decode(Header.self, from: data),
              header.version == Self.currentVersion,
              let file = try? decoder.decode(File.self, from: data)
        else {
            setUnreadableFileAside()
            return
        }
        all = file.moments.sorted { $0.createdAt > $1.createdAt }
    }

    private func setUnreadableFileAside() {
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = fileURL.deletingLastPathComponent()
            .appendingPathComponent("moments.unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: aside)
    }

    /// Writes `moments`, and only on success makes them current.
    private func commit(_ moments: [Moment]) -> Bool {
        do {
            let data = try Self.encoder.encode(File(version: Self.currentVersion, moments: moments))
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return false
        }
        all = moments
        NotificationCenter.default.post(name: Self.didChange, object: self)
        return true
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

private extension Array {
    func inserting(_ element: Element, at index: Int) -> [Element] {
        var copy = self
        copy.insert(element, at: index)
        return copy
    }
}
