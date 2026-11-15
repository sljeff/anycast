import UIKit
import ObjectiveC

/// Skeleton text for loading rows: the loading rule's static bars, no
/// shimmer. A bar is an attributed string of invisible glyphs in the
/// label's own font over a `sandAlpha4` fill, so it sizes the row exactly
/// like the real content.
///
/// Assigning that string through `attributedText` is why the pair below
/// exists: the assignment rewrites the label's `font` and `textColor`
/// style properties from the attributes at character 0 (the color becomes
/// `.clear`), and a later plain `text =` assignment inherits the previous
/// string's attributes — so a cell reused from a skeleton row goes on
/// drawing bars where real content was set, while covers set on a separate
/// image view load fine. Both sides of the transition therefore go through
/// this extension: `setSkeletonBar(_:)` remembers the label's base font
/// and color before painting the bar, and `setRealText(_:)` clears the
/// bar and restores them. Never assign `text` directly on a label that
/// has shown a bar.
extension UILabel {

    /// What the label wore before its bar, and whether it wears one now.
    /// A bar may be repainted any number of times before the content
    /// arrives (the pasted-address row renders its loading bar from both
    /// `viewDidLoad` and `load`), so the base style is captured only on
    /// the first bar of a run — repainting would otherwise capture the
    /// previous bar's `.clear` as the "base" color.
    private final class SkeletonState {
        var baseFont: UIFont?
        var baseColor: UIColor?
        var isShowingBar = false
    }

    private enum SkeletonStateKey {
        nonisolated(unsafe) static var address: UInt8 = 0
    }

    private var skeletonState: SkeletonState {
        if let stored = objc_getAssociatedObject(self, &SkeletonStateKey.address) as? SkeletonState {
            return stored
        }
        let fresh = SkeletonState()
        objc_setAssociatedObject(self, &SkeletonStateKey.address, fresh, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return fresh
    }

    /// Draws `placeholder` as a skeleton bar, remembering the label's
    /// current font and text color (on the first bar of a run) as the base
    /// style to restore when the real content arrives.
    func setSkeletonBar(_ placeholder: String) {
        let state = skeletonState
        if !state.isShowingBar {
            state.baseFont = font
            state.baseColor = textColor
        }
        state.isShowingBar = true
        attributedText = NSAttributedString(string: placeholder, attributes: [
            .font: font, .foregroundColor: UIColor.clear, .backgroundColor: AnycastColor.sandAlpha4,
        ])
    }

    /// Sets real text on a label that is showing (or has shown) a skeleton
    /// bar: drops the attributed string, re-applies the remembered base
    /// style, then assigns `text` — no clear foreground or fill leaks into
    /// the content.
    func setRealText(_ text: String) {
        let state = skeletonState
        attributedText = nil
        if let baseFont = state.baseFont { font = baseFont }
        if let baseColor = state.baseColor { textColor = baseColor }
        state.isShowingBar = false
        self.text = text
    }
}
