import UIKit
import Testing
import SnapshotTesting

/// Per-OS snapshot baseline helper (05 §6.1): baselines are stored under
/// `__Snapshots__/<SourceFile>/iOS-<major>/<name>.png`, so each iOS release
/// gets its own directory instead of the library's flat default naming.
///
/// Usage:
/// - Record: run the suite with SNAPSHOT_RECORD=1 in the TEST PROCESS env —
///   `TEST_RUNNER_SNAPSHOT_RECORD=1 xcodebuild … test` (xcodebuild forwards
///   TEST_RUNNER_-prefixed variables into the runner).
/// - Verify (default): missing baselines fail; byte differences fail and
///   drop a `<name>.actual.png` next to the baseline for inspection.
///
/// The target links `swift-snapshot-testing` — later screen tasks can use
/// `assertSnapshot` directly when its default naming suffices; this helper
/// exists for the per-OS-directory requirement and deterministic layer
/// rendering (no live-window capture, so output does not depend on the
/// host's screen).
@MainActor
enum SnapshotBaseline {

    static var recordMode: Bool {
        ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
    }

    /// `iOS-26`-style directory component for the running OS.
    static var osDirectoryName: String {
        "iOS-\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)"
    }

    /// Renders `view` (fixed size, dark trait environment) and records or
    /// verifies the baseline named `name`.
    static func assertSnapshot(
        of view: UIView,
        named name: String,
        file: StaticString = #filePath
    ) throws {
        let rendered = render(view)

        let fileURL = URL(fileURLWithPath: file.description)
        let directory = fileURL.deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
            .appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent)
            .appendingPathComponent(osDirectoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let baselineURL = directory.appendingPathComponent("\(name).png")

        if recordMode {
            try rendered.write(to: baselineURL)
            Issue.record("Recorded baseline \(baselineURL.path) — re-run without SNAPSHOT_RECORD to verify.")
            return
        }

        guard FileManager.default.fileExists(atPath: baselineURL.path) else {
            Issue.record("Missing baseline \(baselineURL.path) — run once with SNAPSHOT_RECORD=1.")
            return
        }

        let baseline = try Data(contentsOf: baselineURL)
        if baseline == rendered {
            return
        }
        // Pixel comparison, not byte comparison: ImageIO's PNG encoder
        // output (zlib settings) varies across OS/Xcode versions, which
        // made byte-identical baselines fail after toolchain updates
        // even though the rendered pixels were unchanged.
        guard let baselinePixels = Self.rgba8Pixels(of: baseline) else {
            let actualURL = directory.appendingPathComponent("\(name).actual.png")
            try? rendered.write(to: actualURL)
            Issue.record("Snapshot mismatch: \(name). Baseline \(baselineURL.path) is not decodable; actual \(actualURL.path).")
            return
        }
        guard let renderedPixels = Self.rgba8Pixels(of: rendered),
              baselinePixels == renderedPixels else {
            let actualURL = directory.appendingPathComponent("\(name).actual.png")
            try? rendered.write(to: actualURL)
            Issue.record("Snapshot mismatch: \(name). Baseline \(baselineURL.path), actual \(actualURL.path).")
            return
        }
    }

    /// Decodes PNG data into a canonical premultiplied-RGBA byte buffer.
    private static func rgba8Pixels(of pngData: Data) -> [UInt8]? {
        guard let image = UIImage(data: pngData)?.cgImage else { return nil }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    /// Deterministic layer render at the view's current bounds.
    static func render(_ view: UIView, scale: CGFloat = 3) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: view.bounds.size, format: format)
        let image = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        return image.pngData() ?? Data()
    }
}
