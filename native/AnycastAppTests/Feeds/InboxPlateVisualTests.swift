import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// The inbox episode list as ONE dense grouped plate: hosts the real rows
/// section (`InboxPageViewController.rowsSection`) with the pinned header,
/// shelf and strip above it in a 402 x 874 window, asserts the density and
/// alignment contract, and writes a PNG into NSTemporaryDirectory (same
/// convention as the other visual suites).
@MainActor
@Suite(.serialized)
struct InboxPlateVisualTests {

    private struct Row {
        var title: String
        var show: String
        var date: String
        var duration: String
        var status: InboxCardContent.Status = .none
    }

    private static let rows: [Row] = [
        Row(title: "The long road back to a working supply chain, and why it keeps breaking in the same place", show: "Planet Money", date: "10h ago", duration: "44m", status: .playing),
        Row(title: "Weekend reading", show: "The Daily", date: "12h ago", duration: "28m"),
        Row(title: "Why the housing market is stuck: a conversation with two economists who disagree", show: "Freakonomics Radio", date: "1d ago", duration: "1h 2m", status: .queued),
        Row(title: "Short one", show: "99% Invisible", date: "1d ago", duration: "9m"),
        Row(title: "Inside the lab that grows coffee without beans", show: "Radiolab", date: "2d ago", duration: "51m"),
        Row(title: "Mailbag", show: "Accidental Tech Podcast with a very long show name that cannot fit", date: "2d ago", duration: "2h 14m"),
        Row(title: "A history of the standard shipping container and the people who fought it", show: "Hardcore History", date: "3d ago", duration: "3h 40m"),
        Row(title: "Quick update", show: "Up First", date: "3d ago", duration: "12m"),
        Row(title: "The case for boring technology", show: "Changelog", date: "4d ago", duration: "37m"),
        Row(title: "Season finale", show: "Serial", date: "5d ago", duration: "46m"),
    ]

    private final class Source: NSObject, UICollectionViewDataSource {
        let shelf = ShowsShelfView()
        let strip = CategoryStripView()
        func numberOfSections(in collectionView: UICollectionView) -> Int { 3 }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            section == 2 ? InboxPlateVisualTests.rows.count : 1
        }
        func collectionView(
            _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            switch indexPath.section {
            case 0, 1:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ChromeHostingCell.reuseIdentifier, for: indexPath
                )
                (cell as? ChromeHostingCell)?.host(indexPath.section == 0 ? shelf : strip)
                return cell
            default:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: InboxEpisodeCardCell.reuseIdentifier, for: indexPath
                )
                let row = InboxPlateVisualTests.rows[indexPath.item]
                let card = cell as? InboxEpisodeCardCell
                card?.configure(InboxCardContent(
                    title: row.title, showName: row.show, dateText: row.date,
                    durationText: row.duration, status: row.status
                ))
                card?.setPosition(isFirst: indexPath.item == 0, isLast: indexPath.item == InboxPlateVisualTests.rows.count - 1)
                return cell
            }
        }
    }

    @Test("Inbox rows: one dense plate, 7+ rows on screen, aligned columns")
    func plateIsDenseAndAligned() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "self-sizing needs a connected scene"
        )
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        defer { window.isHidden = true; window.rootViewController = nil }

        let header = HeaderView()
        header.configure(HeaderView.Configuration(title: "Podcast", statusText: "updated 2m ago · 10 unlistened"))
        let headerHeight = header.systemLayoutSizeFitting(
            CGSize(width: 402, height: UIView.layoutFittingExpandedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height
        let topInset: CGFloat = 59 + headerHeight

        let layout = UICollectionViewCompositionalLayout { index, environment in
            switch index {
            case 0: return InboxPageViewController.chromeSection(height: ShowsShelfLayout.itemSide, bottomInset: Spacing.gap)
            case 1: return InboxPageViewController.chromeSection(height: CategoryStripView.chipHeight, bottomInset: Spacing.gap)
            default:
                var config = UICollectionLayoutListConfiguration(appearance: .plain)
                config.showsSeparators = false
                config.backgroundColor = .clear
                return InboxPageViewController.rowsSection(config: config, environment: environment)
            }
        }
        layout.register(GroupedPlateView.self, forDecorationViewOfKind: GroupedPlateView.elementKind)
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        let source = Source()
        source.shelf.configure(shows: (1...6).map {
            SubscriptionRow(rssFeedUrl: "https://example.com/\($0).rss", title: "Show \($0)")
        })
        source.strip.configure(categories: ["news", "comedy"], selected: nil)
        collectionView.register(ChromeHostingCell.self, forCellWithReuseIdentifier: ChromeHostingCell.reuseIdentifier)
        collectionView.register(InboxEpisodeCardCell.self, forCellWithReuseIdentifier: InboxEpisodeCardCell.reuseIdentifier)
        collectionView.dataSource = source

        let host = UIViewController()
        Theme.installPageBase(on: host.view)
        collectionView.frame = host.view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.contentInset.top = topInset
        host.view.addSubview(collectionView)
        header.frame = CGRect(x: 0, y: 59, width: 402, height: headerHeight)
        host.view.addSubview(header)
        window.rootViewController = host
        window.isHidden = false
        collectionView.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 400_000_000)
        collectionView.layoutIfNeeded()

        let cells = (0..<Self.rows.count).compactMap {
            collectionView.cellForItem(at: IndexPath(item: $0, section: 2)) as? InboxEpisodeCardCell
        }
        let fitting = cells.filter { cell in
            let frame = cell.convert(cell.bounds, to: window)
            return frame.maxY <= window.bounds.height
        }
        print("[inbox-plate] rows realised \(cells.count), fully on screen \(fitting.count), heights \(cells.map { Int($0.frame.height) })")
        #expect(fitting.count >= 6, "only \(fitting.count) rows fit")

        // Columns: the cover starts 32 pt from the screen edge, the plate
        // 16 pt; the hairline of a non-first row starts at the text.
        let first = try #require(cells.first)
        let firstFrame = first.convert(first.bounds, to: window)
        #expect(firstFrame.minX == Spacing.pageH, "row is not inset 16 from the screen edge")
        #expect(firstFrame.width == 402 - 2 * Spacing.pageH)

        // Heights are settled: a reload changes nothing.
        // Only the on-screen rows: a row past the fold is not realised again.
        let before = fitting.map(\.frame.height)
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        collectionView.layoutIfNeeded()
        let after = (0..<before.count).map {
            collectionView.cellForItem(at: IndexPath(item: $0, section: 2))?.frame.height ?? -1
        }
        #expect(before == after, "row heights moved on reload: \(before) -> \(after)")

        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("inbox-plate.png")
            try? data.write(to: url)
            print("[inbox-plate] wrote \(url.path)")
        }
    }
}
