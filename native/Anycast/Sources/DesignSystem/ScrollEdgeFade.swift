import UIKit

/// A non-interactive scrim that keeps scrolled content from being hard-cut
/// at a fixed edge (G-7): a `fadeLength` gradient from the page background
/// to clear at its inner edge, solid page background everywhere beyond it.
/// `.top` sits under a fixed header (solid side up), `.bottom` above a
/// bottom bar (solid side down). Colors re-resolve on trait changes
/// (CGColor is frozen at assignment).
@MainActor
final class ScrollEdgeFade: UIView {

    enum Edge { case top, bottom }

    static let fadeLength: CGFloat = 16

    private let edge: Edge
    private let color: UIColor
    private let gradient = CAGradientLayer()

    init(edge: Edge, color: UIColor = Theme.background) {
        self.edge = edge
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        backgroundColor = .clear
        // Vertical gradient, y grows downward in the layer's unit space.
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradient)
        updateColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.updateColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        // The ramp spans exactly `fadeLength` at the inner edge; a view no
        // taller than that is a pure gradient.
        let height = bounds.height
        let fraction = height > Self.fadeLength ? Self.fadeLength / height : 1
        switch edge {
        case .top:
            // Opaque from the top down to the ramp, clear at the bottom.
            gradient.locations = [NSNumber(value: 1 - fraction), 1]
        case .bottom:
            // Clear at the top, opaque after the ramp to the bottom.
            gradient.locations = [0, NSNumber(value: fraction)]
        }
        CATransaction.commit()
    }

    private func updateColors() {
        let resolved = color.resolvedColor(with: traitCollection)
        let opaque = resolved.withAlphaComponent(1).cgColor
        let clear = resolved.withAlphaComponent(0).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = edge == .top ? [opaque, clear] : [clear, opaque]
        CATransaction.commit()
    }
}

/// One component for "scroll content fades out behind fixed chrome instead
/// of being hard-cut" (a pinned page header, a sheet title row, a bottom
/// action row or input bar). The scroll view extends under the chrome —
/// the caller keeps the resting layout with `contentInset` — and this
/// helper adds the fade, with an OS branch inside the one component:
/// - every OS: a `ScrollEdgeFade` in the surface colour, solid across the
///   chrome's footprint and ramping to clear over a short band past it,
///   behind the chrome and above the scroll view. Nothing legible ever
///   shows behind chrome text.
/// - iOS 26+: additionally a `UIScrollEdgeElementContainerInteraction` on
///   the chrome, so the system scroll edge effect (blur + fade) reads in
///   the ramp band below/above the chrome, as it does for system bars.
@MainActor
enum ScrollEdgeChrome {

    /// Chosen by comparing on device: `.soft` is the progressive blur that
    /// reads as content melting under the chrome; `.automatic` resolves to
    /// the hard style here (a hairline plus a hard cut at the chrome edge).
    @available(iOS 26.0, *)
    static let edgeEffectStyle: UIScrollEdgeEffect.Style = .soft

    /// Points an attached chrome at another scroll view (paged hosts swap
    /// the visible list). iOS 26+ only; the fade needs no scroll view.
    static func retarget(chrome: UIView, to scrollView: UIScrollView, edge: UIRectEdge) {
        guard #available(iOS 26.0, *) else { return }
        for case let interaction as UIScrollEdgeElementContainerInteraction in chrome.interactions {
            interaction.scrollView = scrollView
        }
        let effect = edge == .top ? scrollView.topEdgeEffect : scrollView.bottomEdgeEffect
        effect.isHidden = false
        effect.style = edgeEffectStyle
    }

    /// Attaches the fade for `chrome` (a view inside `host`) at `edge`
    /// (`.top` or `.bottom`) of `scrollView`. `fadeColor` is the surface
    /// colour behind the chrome (page background or sheet surface).
    /// `restingGap` is the room between the chrome and the first/last row
    /// at rest: the ramp never reaches into it, so resting content is not
    /// veiled. `reach` is the outer edge the fade stretches to when the
    /// scroll view runs past the chrome (under the status bar, for
    /// instance); it defaults to the chrome's own outer edge. Returns the
    /// fade view.
    @discardableResult
    static func attach(
        chrome: UIView,
        to scrollView: UIScrollView,
        edge: UIRectEdge,
        in host: UIView,
        fadeColor: UIColor = Theme.background,
        restingGap: CGFloat = ScrollEdgeFade.fadeLength,
        reach: NSLayoutYAxisAnchor? = nil
    ) -> ScrollEdgeFade {
        precondition(edge == .top || edge == .bottom, "ScrollEdgeChrome supports .top and .bottom")
        // Siblings stack scroll view < fade < chrome; with the scroll view
        // elsewhere in the tree (paged hosts) the caller keeps the chrome on top.
        let scrollIsSibling = scrollView.superview === host
        if scrollIsSibling, chrome.superview === host {
            host.insertSubview(chrome, aboveSubview: scrollView)
        }
        if #available(iOS 26.0, *) {
            let interaction = UIScrollEdgeElementContainerInteraction()
            interaction.edge = edge
            chrome.addInteraction(interaction)
            retarget(chrome: chrome, to: scrollView, edge: edge)
        }
        let isTop = edge == .top
        let ramp = min(max(restingGap, 0), ScrollEdgeFade.fadeLength)
        let fade = ScrollEdgeFade(edge: isTop ? .top : .bottom, color: fadeColor)
        if scrollIsSibling {
            host.insertSubview(fade, aboveSubview: scrollView)
        } else {
            host.insertSubview(fade, belowSubview: chrome)
        }
        NSLayoutConstraint.activate([
            fade.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            isTop
                ? fade.topAnchor.constraint(equalTo: reach ?? chrome.topAnchor)
                : fade.bottomAnchor.constraint(equalTo: reach ?? chrome.bottomAnchor),
            isTop
                ? fade.bottomAnchor.constraint(equalTo: chrome.bottomAnchor, constant: ramp)
                : fade.topAnchor.constraint(equalTo: chrome.topAnchor, constant: -ramp),
        ])
        return fade
    }

    /// The bottom edge of a sheet or page with no bottom chrome of its own:
    /// content melts away at the screen edge (the home-indicator band)
    /// instead of being cut. A clear, touch-transparent strip pinned to
    /// `host`'s bottom stands in as the chrome; it is at least `minimumHeight`
    /// tall and covers the bottom safe area. Returns the strip.
    @discardableResult
    static func attachBottomEdge(
        to scrollView: UIScrollView,
        in host: UIView,
        fadeColor: UIColor = Theme.background,
        minimumHeight: CGFloat = 24
    ) -> UIView {
        let strip = EdgeStripView()
        strip.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            strip.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            strip.topAnchor.constraint(lessThanOrEqualTo: host.safeAreaLayoutGuide.bottomAnchor),
            strip.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight),
        ])
        let preferred = strip.heightAnchor.constraint(equalToConstant: 0)
        preferred.priority = .defaultLow
        preferred.isActive = true
        // The ramp stays inside the strip: rows rest right above it.
        attach(
            chrome: strip, to: scrollView, edge: .bottom, in: host, fadeColor: fadeColor, restingGap: 0
        )
        return strip
    }

    /// The top edge of a sheet or page whose title row is plain views: a
    /// clear strip from `host`'s top (the grabber and status bar included)
    /// down to `anchor` stands in as the chrome, so the fade covers the
    /// whole band. The caller brings the title views to the front.
    /// `restingGap` is the room between `anchor` and the first row at rest;
    /// the band covers it, so nothing is veiled at rest.
    @discardableResult
    static func attachTopBand(
        to scrollView: UIScrollView,
        in host: UIView,
        below anchor: NSLayoutYAxisAnchor,
        fadeColor: UIColor = Theme.background,
        restingGap: CGFloat = ScrollEdgeFade.fadeLength
    ) -> UIView {
        let band = EdgeStripView()
        band.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(band)
        NSLayoutConstraint.activate([
            band.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            band.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            band.topAnchor.constraint(equalTo: host.topAnchor),
            // The band runs on to where the first row rests, so the system
            // effect has room to fade content out under the whole title row.
            band.bottomAnchor.constraint(equalTo: anchor, constant: restingGap),
        ])
        attach(
            chrome: band, to: scrollView, edge: .top, in: host, fadeColor: fadeColor,
            restingGap: 0
        )
        return band
    }

    /// Keeps a scroll view that runs under top chrome resting exactly as if
    /// it started below it: `chromeBottomY` is where the first row should
    /// begin, in the scroll view's superview coordinates. Adjusts only
    /// `contentInset.top` (the safe-area share is left to the system) and
    /// follows the offset when the list is resting at its top. Call from
    /// `viewDidLayoutSubviews`.
    static func clearTop(of scrollView: UIScrollView, to chromeBottomY: CGFloat) {
        let safeTop = scrollView.adjustedContentInset.top - scrollView.contentInset.top
        let top = max(0, chromeBottomY - scrollView.frame.minY - safeTop)
        guard abs(scrollView.contentInset.top - top) > 0.5 else { return }
        let wasAtTop = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 0.5
        scrollView.contentInset.top = top
        if wasAtTop { scrollView.contentOffset.y = -scrollView.adjustedContentInset.top }
    }

    /// The top edge of a sheet with no title row (content starts at the
    /// edge): a clear `height` strip at `host`'s top stands in as the chrome,
    /// so content scrolled up melts away under the grabber zone instead of
    /// running into the edge. Nothing shows at rest as long as the content
    /// starts at least `restingGap` below the strip.
    @discardableResult
    static func attachTopEdge(
        to scrollView: UIScrollView,
        in host: UIView,
        height: CGFloat,
        fadeColor: UIColor = Theme.background,
        restingGap: CGFloat
    ) -> UIView {
        let strip = EdgeStripView()
        strip.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            strip.topAnchor.constraint(equalTo: host.topAnchor),
            strip.heightAnchor.constraint(equalToConstant: height),
        ])
        attach(
            chrome: strip, to: scrollView, edge: .top, in: host, fadeColor: fadeColor,
            restingGap: restingGap
        )
        return strip
    }

    /// The bottom twin of `clearTop`: `chromeTopY` is where the last row
    /// should end, in the scroll view's superview coordinates.
    static func clearBottom(of scrollView: UIScrollView, to chromeTopY: CGFloat) {
        let safeBottom = scrollView.adjustedContentInset.bottom - scrollView.contentInset.bottom
        let bottom = max(0, scrollView.frame.maxY - chromeTopY - safeBottom)
        guard abs(scrollView.contentInset.bottom - bottom) > 0.5 else { return }
        scrollView.contentInset.bottom = bottom
    }
}


/// A clear stand-in chrome for `ScrollEdgeChrome`: invisible, passes every
/// touch through. A label rather than a plain view because the iOS 26 edge
/// effect measured on device only wraps containers that carry content (an
/// empty or transparent plain `UIView` produced no effect).
private final class EdgeStripView: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        text = " "
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}
