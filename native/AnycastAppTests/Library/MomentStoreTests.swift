import Foundation
import Testing
@testable import Anycast

/// Kept moments: a versioned JSON file that round-trips, never keeps the
/// same sentence twice, and never overwrites a file it cannot read.
@MainActor
struct MomentStoreTests {

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("moment-store-\(UUID().uuidString)", isDirectory: true)
    }

    private func moment(
        _ text: String = "A sentence worth keeping.",
        episode: String = "https://example.test/one.mp3",
        start: Int = 12_000,
        at created: TimeInterval = 1_000
    ) -> Moment {
        Moment(
            enclosureURL: episode,
            rssFeedURL: "https://example.test/feed.xml",
            episodeTitle: "Episode One",
            showTitle: "Night Kitchen",
            artworkURL: "https://example.test/cover.jpg",
            startMilliseconds: start,
            text: text,
            translation: "一句值得留下的话。",
            createdAt: Date(timeIntervalSince1970: created)
        )
    }

    private func asideFiles(in directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix("moments.unreadable-") }
            .map { directory.appendingPathComponent($0) }
    }

    @Test("A moment round-trips through the file with every field")
    func roundTrip() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("moments.json")

        let store = MomentStore(fileURL: file)
        #expect(store.all.isEmpty)
        let kept = moment()
        #expect(store.add(kept) == .added)

        let reopened = MomentStore(fileURL: file)
        #expect(reopened.all == [kept])
        #expect(reopened.contains(episode: kept.enclosureURL, start: kept.startMilliseconds))
        #expect(!reopened.contains(episode: kept.enclosureURL, start: 1))
    }

    @Test("The file carries its version")
    func fileIsVersioned() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("moments.json")
        MomentStore(fileURL: file).add(moment())

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        #expect(json?["version"] as? Int == MomentStore.currentVersion)
        #expect((json?["moments"] as? [Any])?.count == 1)
    }

    @Test("Newest first, and the order survives a reopen")
    func newestFirst() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("moments.json")

        let store = MomentStore(fileURL: file)
        store.add(moment("first", start: 1_000, at: 100))
        store.add(moment("second", start: 2_000, at: 200))
        store.add(moment("third", start: 3_000, at: 300))
        #expect(store.all.map(\.text) == ["third", "second", "first"])
        #expect(MomentStore(fileURL: file).all.map(\.text) == ["third", "second", "first"])
    }

    @Test("The same episode and start are kept once; other episodes and starts are separate")
    func dedupes() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MomentStore(fileURL: directory.appendingPathComponent("moments.json"))

        #expect(store.add(moment()) == .added)
        #expect(store.add(moment("Same place, new id")) == .duplicate)
        #expect(store.add(moment(start: 13_000)) == .added)
        #expect(store.add(moment(episode: "https://example.test/two.mp3")) == .added)
        #expect(store.all.count == 3)
    }

    @Test("Remove by id and by episode and start; unknown ones change nothing")
    func removes() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("moments.json")
        let store = MomentStore(fileURL: file)
        let first = moment("one", start: 1_000)
        let second = moment("two", start: 2_000)
        store.add(first)
        store.add(second)

        #expect(store.remove(id: UUID()) == false)
        #expect(store.remove(episode: "https://example.test/one.mp3", start: 99) == false)
        #expect(store.remove(id: first.id))
        #expect(store.remove(episode: second.enclosureURL, start: 2_000))
        #expect(store.all.isEmpty)
        #expect(MomentStore(fileURL: file).all.isEmpty)
    }

    @Test("Changes post a notification")
    func notifies() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MomentStore(fileURL: directory.appendingPathComponent("moments.json"))
        var count = 0
        let token = NotificationCenter.default.addObserver(
            forName: MomentStore.didChange, object: store, queue: nil
        ) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        let kept = moment()
        store.add(kept)
        store.add(kept)
        store.remove(id: kept.id)
        #expect(count == 2, "a duplicate add changes nothing")
    }

    @Test("A corrupt file reads as empty, is kept aside, and is not overwritten by new moments")
    func corruptFile() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("moments.json")
        let garbage = Data("{ this is not json".utf8)
        try garbage.write(to: file)

        let store = MomentStore(fileURL: file)
        #expect(store.all.isEmpty)
        let aside = asideFiles(in: directory)
        #expect(aside.count == 1)
        #expect(try aside.first.map { try Data(contentsOf: $0) } == garbage, "the old bytes are kept")

        #expect(store.add(moment()) == .added)
        #expect(try aside.first.map { try Data(contentsOf: $0) } == garbage, "still untouched")
        #expect(MomentStore(fileURL: file).all.count == 1)
    }

    @Test("A file from a newer version reads as empty and is kept aside intact")
    func unknownVersion() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("moments.json")
        let future = Data(#"{"version": 99, "moments": [{"shape": "unknown"}]}"#.utf8)
        try future.write(to: file)

        let store = MomentStore(fileURL: file)
        #expect(store.all.isEmpty)
        let aside = asideFiles(in: directory)
        #expect(aside.count == 1)
        #expect(try aside.first.map { try Data(contentsOf: $0) } == future)
        #expect(!FileManager.default.fileExists(atPath: file.path), "nothing is rewritten in place")
    }

    @Test("An unwritable location fails the add without changing the list")
    func writeFailure() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A regular file where the store's folder should be.
        let blocker = directory.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let store = MomentStore(fileURL: blocker.appendingPathComponent("moments.json"))

        #expect(store.add(moment()) == .failed)
        #expect(store.all.isEmpty)
    }
}
