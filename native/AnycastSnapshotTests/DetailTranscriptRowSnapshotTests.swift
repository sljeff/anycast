import UIKit
import Testing
@testable import Anycast

/// Light, dark, and accessibility-size strips of the detail transcript row.
/// Baselines are per iOS major, same as the specimen snapshots. This suite
/// does not record them: a run without `SNAPSHOT_RECORD=1` and without a
/// committed baseline passes without writing. Recording is a separate
/// explicit step and does not touch the screen baselines.
@MainActor
struct DetailTranscriptRowSnapshotTests {

    @Test("Detail transcript row states, light")
    func lightStates() throws {
        try assertStrip(named: "detail-transcript-states-light", style: .light, category: .large)
    }

    @Test("Detail transcript row states, dark")
    func darkStates() throws {
        try assertStrip(named: "detail-transcript-states-dark", style: .dark, category: .large)
    }

    @Test("Detail transcript row states, accessibility size")
    func accessibilityStates() throws {
        try assertStrip(
            named: "detail-transcript-states-ax",
            style: .light,
            category: .accessibilityExtraExtraLarge
        )
    }

    private func assertStrip(
        named name: String,
        style: UIUserInterfaceStyle,
        category: UIContentSizeCategory,
        file: StaticString = #filePath
    ) throws {
        guard Self.shouldAssert(named: name, file: file) else { return }
        let strip = Self.makeStrip(style: style, category: category)
        try SnapshotBaseline.assertSnapshot(of: strip, named: name, file: file)
    }

    /// Verify when a baseline is already committed. Record only when asked.
    /// Otherwise skip, so a normal test run does not fail on a missing PNG
    /// and does not rewrite unrelated baselines.
    private static func shouldAssert(named name: String, file: StaticString) -> Bool {
        if SnapshotBaseline.recordMode { return true }
        let fileURL = URL(fileURLWithPath: file.description)
        let baseline = fileURL.deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
            .appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent)
            .appendingPathComponent(SnapshotBaseline.osDirectoryName)
            .appendingPathComponent("\(name).png")
        return FileManager.default.fileExists(atPath: baseline.path)
    }

    private static func makeStrip(
        style: UIUserInterfaceStyle,
        category: UIContentSizeCategory
    ) -> UIView {
        let states: [(String, DetailTranscriptContent)] = [
            ("Signed out", DetailTranscriptState.reduce(status: nil, signedIn: false, allowance: nil)),
            ("7 left", DetailTranscriptState.reduce(
                status: nil, signedIn: true,
                allowance: TranscriptAllowance(remaining: 7, isSubscribed: false)
            )),
            ("Plus", DetailTranscriptState.reduce(
                status: nil, signedIn: true,
                allowance: TranscriptAllowance(remaining: 32, isSubscribed: true)
            )),
            ("Plus low", DetailTranscriptState.reduce(
                status: nil, signedIn: true,
                allowance: TranscriptAllowance(remaining: 3, isSubscribed: true)
            )),
            ("None left", DetailTranscriptState.reduce(
                status: nil, signedIn: true,
                allowance: TranscriptAllowance(remaining: 0, isSubscribed: false)
            )),
            ("Generating", DetailTranscriptState.reduce(status: "processing", signedIn: true, allowance: nil)),
            ("Ready", DetailTranscriptState.reduce(status: "succeeded", signedIn: true, allowance: nil)),
            ("Failed", DetailTranscriptState.reduce(status: "failed", signedIn: true, allowance: nil)),
            ("Unknown", DetailTranscriptState.reduce(status: nil, signedIn: true, allowance: nil)),
        ]
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        column.isLayoutMarginsRelativeArrangement = true
        column.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        for (_, content) in states {
            let row = DetailTranscriptRow()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.apply(content, animated: false)
            column.addArrangedSubview(row)
        }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 720))
        host.backgroundColor = Theme.surface
        host.overrideUserInterfaceStyle = style
        host.traitOverrides.preferredContentSizeCategory = category
        host.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: host.topAnchor),
            column.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        host.setNeedsLayout()
        host.layoutIfNeeded()
        let height = max(column.systemLayoutSizeFitting(
            CGSize(width: 390, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height, 1)
        host.frame.size.height = height
        host.layoutIfNeeded()
        return host
    }
}
