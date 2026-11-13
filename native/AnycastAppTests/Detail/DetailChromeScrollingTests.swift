import UIKit
import Testing
@testable import Anycast

/// Pinning transcript + Play is a function of the identity and the notes,
/// not of the Play capsule alone. A shorter capped capsule must not pin a
/// short sheet and open a blank band above the controls.
struct DetailChromeScrollingTests {

    private let fade: CGFloat = 40

    @Test("Long notes stay pinned when the identity fits above the chrome")
    func pinsWhenNotesFill() {
        let scroll = DetailChromeScrolling.shouldScroll(
            identityBottom: 300,
            notesHeight: 500,
            pinnedScrollHeight: 480,
            fadeHeight: fade
        )
        #expect(scroll == false)
    }

    @Test("The identity scrolling out from under the fade unpins the chrome")
    func scrollsWhenIdentityDoesNotFit() {
        // visible bottom is 420 - 40 = 380. The date sits past it.
        let scroll = DetailChromeScrolling.shouldScroll(
            identityBottom: 390,
            notesHeight: 500,
            pinnedScrollHeight: 420,
            fadeHeight: fade
        )
        #expect(scroll == true)
    }

    @Test("Short notes keep the chrome in the scroll flow")
    func scrollsWhenNotesAreShort() {
        // Visible bottom 440, notes end at 400: 40 pt of empty sheet, past
        // the 28 pt slack, so pinning would open a hole above Play.
        let scroll = DetailChromeScrolling.shouldScroll(
            identityBottom: 300,
            notesHeight: 400,
            pinnedScrollHeight: 480,
            fadeHeight: fade
        )
        #expect(scroll == true)
    }

    @Test("Capping Play does not pin a sheet that was scrolling")
    func cappedChromeDoesNotPinShortNotes() {
        let notesHeight: CGFloat = 400
        let identityBottom: CGFloat = 390
        // Taller chrome (uncapped Play): the date does not fit, so the
        // controls already scroll with the notes.
        let uncapped = DetailChromeScrolling.shouldScroll(
            identityBottom: identityBottom,
            notesHeight: notesHeight,
            pinnedScrollHeight: 420,
            fadeHeight: fade
        )
        // Capped Play shortens the chrome, the scroll view grows, and the
        // date now fits. The notes are still short, so the controls stay
        // with the notes instead of jumping to the bottom.
        let capped = DetailChromeScrolling.shouldScroll(
            identityBottom: identityBottom,
            notesHeight: notesHeight,
            pinnedScrollHeight: 480,
            fadeHeight: fade
        )
        #expect(uncapped == true)
        #expect(capped == true)
    }

    @Test("A few points of slack under the fade still pins")
    func smallSlackStaysPinned() {
        // Visible bottom 440, notes end at 430: 10 pt, inside the slack.
        let scroll = DetailChromeScrolling.shouldScroll(
            identityBottom: 300,
            notesHeight: 430,
            pinnedScrollHeight: 480,
            fadeHeight: fade
        )
        #expect(scroll == false)
    }
}
