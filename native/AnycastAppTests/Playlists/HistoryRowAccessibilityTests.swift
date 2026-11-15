import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// The history row cell is the row's single accessibility element, so the
/// 40 pt delete button folded into it is unreachable by VoiceOver — the
/// delete must also ride as a custom action on the element itself.
@MainActor
struct HistoryRowAccessibilityTests {

    @Test("configured row exposes Delete as a custom action")
    func deleteCustomActionExposed() {
        let cell = HistoryRowCell(frame: .zero)
        cell.configure(HistoryEpisodeRow(
            title: "Episode title",
            imageUrl: nil,
            channelTitle: "Channel"
        ))

        let actions = cell.accessibilityCustomActions ?? []
        #expect(actions.count == 1, "expected exactly the Delete action, got \(actions.map(\.name))")
        #expect(actions.first?.name == "Delete")
        #expect(cell.isAccessibilityElement, "the cell must remain the row's element")
    }
}
