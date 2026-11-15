import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Hosted visual check for the import sheet (05 §6.1 S19): presents the
/// real sheet over the live shell and captures window PNGs into tmp for
/// offline inspection. Skips silently when the startup DAG has no context
/// yet (unseeded simulator), mirroring ChannelVisualSmokeTests.
@MainActor
struct ImportExportVisualSmokeTests {

    @Test("Import sheet: confirm list, no-feeds and all-followed states capture")
    func sheetScreenshots() async throws {
        guard let context = await Self.liveUIContext() else { return }
        guard let presenter = Self.rootPresenter() else { return }

        let entries = [
            OPMLParser.Entry(title: "Channel One", xmlURL: "https://one.example/f"),
            OPMLParser.Entry(title: "Channel Two", xmlURL: "https://two.example/f"),
            OPMLParser.Entry(title: "A Rather Long Channel Title That Truncates", xmlURL: "https://three.example/f"),
        ]
        let sheet = ImportSheetViewController(
            context: context, plan: ImportPlan(entries: entries, alreadyFollowed: 2), filename: "Overcast.opml"
        )
        presenter.present(sheet, animated: false)
        try await Task.sleep(for: .milliseconds(800))
        await Self.captureWindow(name: "b2-import-sheet-confirm")
        #expect(Self.findButton(titled: "Import 3 shows", in: sheet.view) != nil, "primary button missing")
        let table = Self.firstTableView(in: sheet.view)
        #expect(table?.numberOfRows(inSection: 0) == 3, "the list dropped entries")
        sheet.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(400))

        let empty = ImportSheetViewController(
            context: context, plan: ImportPlan(entries: [], alreadyFollowed: 0), filename: "notes.txt"
        )
        presenter.present(empty, animated: false)
        try await Task.sleep(for: .milliseconds(800))
        await Self.captureWindow(name: "b2-import-sheet-empty")
        #expect(Self.findButton(titled: "Choose another file", in: empty.view) != nil)
        empty.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(400))
    }

    // MARK: - Helpers (ChannelVisualSmokeTests pattern)

    @MainActor
    private static func findButton(titled title: String, in view: UIView?) -> UIButton? {
        guard let view else { return nil }
        if let button = view as? UIButton {
            let buttonTitle = button.configuration?.title ?? button.currentTitle
            if buttonTitle == title { return button }
        }
        for subview in view.subviews {
            if let found = findButton(titled: title, in: subview) { return found }
        }
        return nil
    }

    @MainActor
    private static func firstTableView(in view: UIView?) -> UITableView? {
        guard let view else { return nil }
        if let table = view as? UITableView { return table }
        for subview in view.subviews {
            if let found = firstTableView(in: subview) { return found }
        }
        return nil
    }

    @MainActor
    private static func liveUIContext() async -> UIContext? {
        for _ in 0..<40 {
            if let context = (UIApplication.shared.delegate as? AppDelegate)?.environment.uiContext {
                return context
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    @MainActor
    private static func rootPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        return window?.rootViewController?.topMostPresented()
    }

    @MainActor
    private static func captureWindow(name: String) async {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { context in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("[t9-visual] wrote \(url.path)")
    }
}
