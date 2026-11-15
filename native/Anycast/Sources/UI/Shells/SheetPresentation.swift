import UIKit

/// Canonical sheet presentations (03 §1.3, 07 §1.2 A2/A3): the
/// full-screen "expand" modal sheets of the Flutter line map to page
/// sheets with the system grabber; the sticky 90%/80% close thresholds
/// are an accepted adaptation (A3 — system default). Most expand sheets
/// are full-height `.large()`; list sheets that need a drag-to-resize
/// affordance (SearchPage) pass extra detents. Screens call these helpers
/// instead of configuring their own presentation controllers.
enum AppSheets {

    /// Expand sheet (modal_bottom_sheet `expand: true`): Settings,
    /// SearchPage, Channel, ChannelSearch, ChatPage, LoginPage, PlayerPage
    /// (03 §1.3 rows 1-9).
    ///
    /// `detents` defaults to a single `.large()` (the full-height expand).
    /// A multi-detent caller (SearchPage passes `[.medium(), .large()]`)
    /// additionally gets `prefersScrollingExpandsWhenScrolledToEdge = false`
    /// so the sheet's own drag owns the top edge — at the default, an
    /// embedded scroll view at its top swallows the pull-down and shows
    /// elastic blank space instead of resizing the sheet.
    ///
    /// `completion` runs after the presentation animation finishes, when
    /// the sheet's presentation controller exists for sure — the hook the
    /// login prompt uses to attach its interactive-dismiss delegate.
    /// Optional and defaulted so every existing call site is unchanged.
    static func presentExpand(
        _ controller: UIViewController,
        from presenter: UIViewController,
        animated: Bool = true,
        detents: [UISheetPresentationController.Detent] = [.large()],
        completion: (() -> Void)? = nil
    ) {
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = detents
            sheet.prefersGrabberVisible = true
            if detents.count > 1 {
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            }
        }
        presenter.present(controller, animated: animated, completion: completion)
    }

    /// Non-expand form sheet (03 §1.3 row 10 — EmailLogin is the one sheet
    /// without `expand`): medium detent, grows to large when content
    /// needs it.
    static func presentForm(
        _ controller: UIViewController,
        from presenter: UIViewController,
        animated: Bool = true
    ) {
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(controller, animated: animated)
    }
}

extension UIViewController {

    /// The top-most presented view controller above this one — sheets
    /// stack (03 §1.2), and every "present from wherever we are" entry
    /// point (login on 401, share handoff) needs this walk.
    func topMostPresented() -> UIViewController {
        var top = self
        // A controller that is itself dismissing cannot present anything:
        // presenting from it fails silently. Walk to the presenting
        // chain's root first, then descend — the descent skips presented
        // controllers that are dismissing, so the result is the top-most
        // controller that can actually anchor a presentation.
        if top.isBeingDismissed {
            while let presenting = top.presentingViewController {
                top = presenting
            }
        }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

extension UIView {

    /// The nearest owning view controller via the responder chain — used
    /// by views that trigger presentation (the mini player bar).
    var containingViewController: UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller
            }
            responder = current.next
        }
        return nil
    }
}
