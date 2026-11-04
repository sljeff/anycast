import UIKit

/// Whether the detail sheet's transcript row and Play scroll with the notes.
///
/// Pinned chrome stays at the bottom of the sheet. That is right when the
/// notes fill the space above it. Short notes would leave a blank band
/// between the text and the pinned controls; those controls then stay in
/// the scroll flow, directly under the notes. Capping Play shortens the
/// chrome and must not, by itself, pin a short sheet and open that band.
nonisolated enum DetailChromeScrolling {

    /// Empty space above this, between the notes and a bottom-pinned
    /// transcript + Play, is a hole rather than the designed fade.
    static let maximumPinnedSlack: CGFloat = Spacing.sectionGap

    /// `notesHeight` is the header and the notes only, in scroll-content
    /// coordinates. `pinnedScrollHeight` is the scroll view's height when
    /// the chrome is pinned, so the check does not depend on the live frame
    /// (that frame grows once scrolling turns on).
    static func shouldScroll(
        identityBottom: CGFloat,
        notesHeight: CGFloat,
        pinnedScrollHeight: CGFloat,
        fadeHeight: CGFloat,
        maximumPinnedSlack: CGFloat = DetailChromeScrolling.maximumPinnedSlack
    ) -> Bool {
        guard pinnedScrollHeight > 1 else { return true }
        let visibleBottom = pinnedScrollHeight - fadeHeight
        let identityDoesNotFit = identityBottom > visibleBottom + 0.5
        let slack = visibleBottom - notesHeight
        let shortNotes = slack > maximumPinnedSlack
        return identityDoesNotFit || shortNotes
    }
}
