import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// The Library sheet (Shows, Moments, Recently played) and the kept-line mark
/// in the transcript, hosted in a 402 x 874 window over the live app context
/// with synthetic data: a temporary history database and a temporary moment
/// file, so the app's own data is never touched. Also writes the review
/// screenshots (`library-sheet.png`, `transcript-kept-line.png`).
@MainActor
struct LibrarySheetTests {

    // MARK: - Fixture

    private struct Fixture {
        let context: UIContext
        let database: AppDatabase
        let momentStore: MomentStore
        let directory: URL
        let window: UIWindow
        let appKeyWindow: UIWindow?

        func cleanUp() {
            appKeyWindow?.makeKey()
            window.rootViewController = nil
            window.isHidden = true
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static let shows: [SubscriptionRow] = [
        "Night Kitchen", "The Long Now", "Small Things", "Radio Atlas", "Slow Burn Weekly",
    ].map { name in
        SubscriptionRow(rssFeedUrl: "https://example.test/\(name).xml", title: name)
    }

    private static func makeFixture(moments: Bool = true, history: Int = 5) async throws -> Fixture? {
        guard let context = await liveContext() else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-sheet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try await AppDatabase.openAt(
            directory.appendingPathComponent("db.sqlite"), localeIdentifier: "en_US"
        )
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for index in 1...max(history, 1) where index <= history {
            try await database.historyRepository().insert(HistoryEpisodeRow(
                title: ["Why the bakery opens at four", "A brief history of salt", "Notes from the night shift",
                        "The map is not the territory", "Ten minutes on sourdough", "An older episode"][(index - 1) % 6],
                enclosureUrl: "https://example.test/history-\(index).mp3",
                channelTitle: shows[(index - 1) % shows.count].title,
                lastPlayedAt: now - Int64(index) * 3_600_000
            ))
        }
        let store = MomentStore(fileURL: directory.appendingPathComponent("moments.json"))
        if moments {
            let texts = [
                "We tend to remember the first line of a story and forget the last.",
                "Most of what looks like talent is a long habit of paying attention, repeated until it stops feeling like effort.",
                "The interesting part is not that the system failed. The interesting part is that nobody noticed for eleven years, because every dashboard they trusted was measuring the thing that had already been fixed, and the thing that was actually broken had no dashboard at all.",
            ]
            for (index, text) in texts.enumerated() {
                store.add(Moment(
                    enclosureURL: "https://example.test/history-\(index + 1).mp3",
                    episodeTitle: "Episode \(index + 1)",
                    showTitle: shows[index].title ?? "",
                    startMilliseconds: [12 * 60_000 + 40_000, 5 * 60_000 + 3_000, 61 * 60_000 + 9_000][index],
                    text: text,
                    createdAt: Date(timeIntervalSince1970: 1_000 + Double(index))
                ))
            }
        }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let appKey = scene?.keyWindow
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let root = UIViewController()
        root.view.backgroundColor = Theme.background
        window.rootViewController = root
        window.isHidden = false
        return Fixture(
            context: context, database: database, momentStore: store,
            directory: directory, window: window, appKeyWindow: appKey
        )
    }

    private static func present(
        _ sheet: UIViewController, in fixture: Fixture, style: UIModalPresentationStyle = .pageSheet
    ) async throws {
        sheet.modalPresentationStyle = style
        fixture.window.rootViewController?.present(sheet, animated: false)
        fixture.appKeyWindow?.makeKey()
        try await Task.sleep(for: .milliseconds(1200))
        fixture.window.layoutIfNeeded()
    }

    private static func liveContext() async -> UIContext? {
        for _ in 0..<40 {
            if let context = (UIApplication.shared.delegate as? AppDelegate)?.environment.uiContext {
                return context
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    private static func capture(_ window: UIWindow, name: String) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("[library-visual] wrote \(url.path)")
    }

    private static func collectionView(in sheet: LibrarySheetViewController) -> UICollectionView? {
        sheet.view.subviews.compactMap { $0 as? UICollectionView }.first
    }

    private static func allViews(in view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + allViews(in: $0) }
    }

    /// Labels that are actually showing (no hidden ancestor, e.g. a cell
    /// parked for reuse).
    private static func texts(in view: UIView) -> [String] {
        allViews(in: view).compactMap { candidate -> String? in
            guard let label = candidate as? UILabel else { return nil }
            var node: UIView? = label
            while let current = node {
                if current.isHidden || current.alpha == 0 { return nil }
                node = current.superview
            }
            return label.text
        }
    }

    // MARK: - Library

    @Test("Library: Shows, Moments and Recently played in order, on the 16 + 16 edge")
    func libraryContentAndEdges() async throws {
        guard let fixture = try await Self.makeFixture() else { return }
        defer { fixture.cleanUp() }
        let sheet = LibrarySheetViewController(
            context: fixture.context, shows: Self.shows,
            database: fixture.database, momentStore: fixture.momentStore
        )
        try await Self.present(sheet, in: fixture)
        sheet.sheetPresentationController?.selectedDetentIdentifier = .large
        try await Task.sleep(for: .milliseconds(800))
        sheet.view.layoutIfNeeded()
        Self.capture(fixture.window, name: "library-sheet")

        let grid = try #require(Self.collectionView(in: sheet))
        // Scroll to the end so every row is realised, then look again.
        grid.setContentOffset(CGPoint(x: 0, y: grid.contentSize.height - grid.bounds.height + grid.contentInset.bottom), animated: false)
        try await Task.sleep(for: .milliseconds(500))
        sheet.view.layoutIfNeeded()
        Self.capture(fixture.window, name: "library-sheet-end")
        let texts = Self.texts(in: sheet.view)
        #expect(texts.contains("Library"))
        let order = ["Moments", "Recently played", "All history"].compactMap { texts.firstIndex(of: $0) }
        #expect(order.count == 3 && order == order.sorted(), "sections out of order: \(texts)")
        #expect(sheet.moments.count == 3)
        #expect(sheet.recent.count == LibrarySheetViewController.recentLimit)
        #expect(grid.numberOfItems(inSection: 1) == Self.shows.count)

        // Edges, in sheet coordinates: titles, covers and row text at 32;
        // plates at 16.
        let sheetEdge: (UIView) -> CGFloat = { $0.convert($0.bounds, to: sheet.view).minX }
        let titleLabels = Self.allViews(in: grid).compactMap { $0 as? UILabel }
            .filter { ["Moments", "Recently played"].contains($0.text ?? "") }
        #expect(titleLabels.count == 2)
        for label in titleLabels { #expect(abs(sheetEdge(label) - 32) < 0.5, "\(label.text ?? "") at \(sheetEdge(label))") }

        let momentCells = Self.allViews(in: grid).compactMap { $0 as? MomentRowCell }
        #expect(momentCells.count >= 1)
        for cell in momentCells {
            #expect(abs(sheetEdge(cell.quoteLabel) - 32) < 0.5)
            #expect(abs(sheetEdge(cell.metaLabel) - 32) < 0.5)
            #expect(cell.playButton.bounds.width >= 44 && cell.playButton.bounds.height >= 44)
            #expect(cell.quoteLabel.numberOfLines == 3)
        }
        let metas = Set(momentCells.compactMap(\.metaLabel.text))
        #expect(metas.isSubset(of: ["Night Kitchen · 12:40", "The Long Now · 05:03", "Small Things · 1:01:09"]), "\(metas)")

        let plates = Self.allViews(in: grid).filter { $0 is GroupedPlateView }
        #expect(plates.count >= 1)
        for plate in plates {
            let frame = plate.convert(plate.bounds, to: sheet.view)
            #expect(abs(frame.minX - 16) < 0.5 && abs(frame.maxX - (sheet.view.bounds.width - 16)) < 0.5)
        }
        let historyCells = Self.allViews(in: grid).compactMap { $0 as? HistoryRowCell }
        #expect(historyCells.count == LibrarySheetViewController.recentLimit)
        for cell in historyCells { #expect(abs(sheetEdge(cell.titleLabel) - (16 + 16 + 44 + 12)) < 0.5) }

        // Three text styles only: 17 semibold, 15 regular.
        for case let label as UILabel in Self.allViews(in: sheet.view) where label.text?.isEmpty == false {
            let size = label.font.pointSize
            #expect(size == 17 || size == 15, "\(label.text ?? "") is \(size) pt")
        }
    }

    @Test("Library: no moments means no Moments section; no history means no Recently played")
    func hidesEmptySections() async throws {
        guard let fixture = try await Self.makeFixture(moments: false, history: 0) else { return }
        defer { fixture.cleanUp() }
        let sheet = LibrarySheetViewController(
            context: fixture.context, shows: Self.shows,
            database: fixture.database, momentStore: fixture.momentStore
        )
        try await Self.present(sheet, in: fixture)
        let texts = Self.texts(in: sheet.view)
        #expect(texts.contains("Shows"))
        #expect(!texts.contains("Moments"))
        #expect(!texts.contains("Recently played"))
        #expect(!texts.contains("All history"))
    }

    @Test("Library: deleting a moment removes its row and the section when the last goes")
    func deletingMoments() async throws {
        guard let fixture = try await Self.makeFixture(history: 0) else { return }
        defer { fixture.cleanUp() }
        let sheet = LibrarySheetViewController(
            context: fixture.context, shows: Self.shows,
            database: fixture.database, momentStore: fixture.momentStore
        )
        try await Self.present(sheet, in: fixture)
        let grid = try #require(Self.collectionView(in: sheet))

        for _ in 0..<2 {
            let text = try #require(sheet.moments.first?.text)
            let cell = try #require(Self.allViews(in: grid).compactMap { $0 as? MomentRowCell }
                .first { $0.quoteLabel.text == text && !$0.isHidden })
            cell.onDelete?()
            try await Task.sleep(for: .milliseconds(300))
        }
        #expect(sheet.moments.count == 1)
        #expect(fixture.momentStore.all.count == 1)
        let lastText = try #require(sheet.moments.first?.text)
        let last = try #require(Self.allViews(in: grid).compactMap { $0 as? MomentRowCell }
            .first { $0.quoteLabel.text == lastText && !$0.isHidden })
        last.onDelete?()
        try await Task.sleep(for: .milliseconds(300))
        #expect(sheet.moments.isEmpty)
        #expect(!Self.texts(in: sheet.view).contains("Moments"))
    }

    // MARK: - Transcript

    #if DEBUG
    @Test("Transcript: Keep moment marks the line without moving the text, and Remove clears it")
    func keptLineMark() async throws {
        guard let fixture = try await Self.makeFixture(moments: false, history: 0) else { return }
        defer { fixture.cleanUp() }
        let page = SubtitlesPageViewController(context: fixture.context)
        page.momentStore = fixture.momentStore
        page.loadViewIfNeeded()
        page.activateDemoDocument()
        // The player page is drawn on the always-dark player backdrop.
        fixture.window.rootViewController?.view.backgroundColor = Theme.playerBackground
        try await Self.present(page, in: fixture, style: .overFullScreen)

        let lines = page.demoLines
        let index = try #require(lines.indices.first { $0 >= 2 && !lines[$0].text.isEmpty })
        page.toggleMoment(at: index)
        try await Task.sleep(for: .milliseconds(600))

        #expect(fixture.momentStore.contains(episode: "demo://t5", start: lines[index].startMilliseconds))
        #expect(page.demoLyricsView.keptStarts == [lines[index].startMilliseconds])
        let cells = Self.allViews(in: page.demoLyricsView).compactMap { $0 as? LyricLineCell }
        let kept = try #require(cells.first { $0.showsKeptMark })
        #expect(cells.filter(\.showsKeptMark).count == 1, "a spacer sharing the stamp is not marked")
        let other = try #require(cells.first { !$0.showsKeptMark })
        #expect(kept.keptMarkFrame.width == 2)
        #expect(kept.keptMarkFrame.maxX <= 0, "the bar sits left of the text column")
        #expect(kept.textFrame.minX == other.textFrame.minX, "the text did not move")
        #expect(!page.demoLyricsView.isHidden)
        Self.capture(fixture.window, name: "transcript-kept-line")

        page.toggleMoment(at: index)
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.momentStore.all.isEmpty)
        #expect(page.demoLyricsView.keptStarts.isEmpty)
    }
    #endif
}
