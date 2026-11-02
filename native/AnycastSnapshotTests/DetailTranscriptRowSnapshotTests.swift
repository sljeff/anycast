import UIKit
import Testing
@testable import Anycast

/// Light, dark, and accessibility-size strips of the detail transcript row.
/// The host is in a window so `overrideUserInterfaceStyle` and the content
/// size category reach `TypographyV2.font(traits:)`. Missing baselines fail;
/// record with `SNAPSHOT_RECORD=1`. These files are separate from the S5
/// screen baseline.
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
        let strip = Self.makeStrip(style: style, category: category)
        defer { strip.window.isHidden = true }
        try SnapshotBaseline.assertSnapshot(of: strip.host, named: name, file: file)
    }

    private static func makeStrip(
        style: UIUserInterfaceStyle,
        category: UIContentSizeCategory
    ) -> (host: UIView, window: UIWindow) {
        let states: [DetailTranscriptContent] = [
            DetailTranscriptState.reduce(status: nil, signedIn: false, allowance: nil),
            DetailTranscriptState.reduce(
                status: nil, signedIn: true,
                allowance: TranscriptAllowance(remaining: 7, isSubscribed: false)
            ),
            DetailTranscriptState.reduce(
                status: nil, signedIn: true,
                allowance: TranscriptAllowance(remaining: 32, isSubscribed: true)
            ),
            DetailTranscriptState.reduce(
                status: nil, signedIn: true,
                allowance: TranscriptAllowance(remaining: 3, isSubscribed: true)
            ),
            DetailTranscriptState.reduce(
                status: nil, signedIn: true,
                allowance: TranscriptAllowance(remaining: 0, isSubscribed: false)
            ),
            DetailTranscriptState.reduce(status: "processing", signedIn: true, allowance: nil),
            DetailTranscriptState.reduce(status: "succeeded", signedIn: true, allowance: nil),
            DetailTranscriptState.reduce(status: "failed", signedIn: true, allowance: nil),
            DetailTranscriptState.reduce(status: nil, signedIn: true, allowance: nil),
        ]
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = Spacing.gap
        column.translatesAutoresizingMaskIntoConstraints = false
        column.isLayoutMarginsRelativeArrangement = true
        column.layoutMargins = UIEdgeInsets(
            top: Spacing.pageH, left: Spacing.pageH, bottom: Spacing.pageH, right: Spacing.pageH
        )
        var rows: [DetailTranscriptRow] = []
        for content in states {
            let row = DetailTranscriptRow()
            row.translatesAutoresizingMaskIntoConstraints = false
            column.addArrangedSubview(row)
            rows.append(row)
        }
        let host = UIView()
        host.backgroundColor = Theme.surface
        host.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: host.topAnchor),
            column.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            host.widthAnchor.constraint(equalToConstant: 390),
        ])

        let root = UIViewController()
        root.view.backgroundColor = Theme.surface
        root.overrideUserInterfaceStyle = style
        root.traitOverrides.preferredContentSizeCategory = category
        host.overrideUserInterfaceStyle = style
        host.traitOverrides.preferredContentSizeCategory = category
        root.view.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: root.view.topAnchor),
            host.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
        ])

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 1200))
        window.windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        window.overrideUserInterfaceStyle = style
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.frame = window.bounds
        root.view.setNeedsLayout()
        root.view.layoutIfNeeded()

        for (row, content) in zip(rows, states) {
            row.overrideUserInterfaceStyle = style
            row.traitOverrides.preferredContentSizeCategory = category
            row.apply(content, animated: false)
            row.relayoutForCurrentTraits()
        }
        root.view.layoutIfNeeded()
        let height = host.systemLayoutSizeFitting(
            CGSize(width: 390, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        host.frame = CGRect(x: 0, y: 0, width: 390, height: max(height, 1))
        host.layoutIfNeeded()
        return (host, window)
    }
}
