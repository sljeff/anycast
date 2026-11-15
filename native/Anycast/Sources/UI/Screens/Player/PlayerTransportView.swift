import UIKit
import AnycastKit

/// The player's scrubber + transport block (progress bar with its state
/// message, replay 10 / play-pause / forward 30), shared by the main page
/// and the transcript page so play/pause is one component everywhere. It owns its
/// own playback observation (episode, position, playing, loading) and the
/// loading/disabled gating; hosts only place it and, optionally, pin
/// accessory buttons to the ends of the transport row.
final class PlayerTransportView: UIView {

    enum Layout {
        /// The transport's touch slots (UI kit `playerControls` container).
        static let transportSlot: CGFloat = 72
        /// The round accessory buttons at the row ends (speed, sleep).
        static let accessorySlot = AnycastIconButton.standardDiameter
        /// The one vertical rhythm, measured between VISIBLE edges (see the
        /// main page): time labels → transport glyphs.
        static let rhythm: CGFloat = 28
        /// Frame-to-ink slack hidden inside the time-label band and the
        /// 72 pt transport slot.
        static let scrubberToTransport = rhythm - 28
        /// Transport glyphs → page selector (13 pt of slot padding hidden).
        static let toSelector = rhythm - 13
        /// Line height of the scrubber's time labels at the default size.
        static let timeLabelLine: CGFloat = 16
        /// How far a scrubber footer tucks up into the empty band under the
        /// time labels (the scrubber frame runs ~12 pt past their ink).
        static let footerTuck: CGFloat = 4
        /// Footer → transport glyphs (14 pt of slot padding hidden).
        static let footerToTransport = rhythm - 14
    }

    private let context: UIContext
    private let observation = ObservationLoop()

    private let progressBar = PlayerProgressBarView()
    private let replayButton = AnycastIconButton(
        style: .plain, icon: AppIcons.replay10, accessibilityLabel: "Seek back 10 seconds",
        diameter: Layout.transportSlot, glyphSize: IconStyle.playerTransport.pointSize,
        glyphWeight: IconStyle.playerTransport.weight, metrics: TypographyV2.headlineMedium
    )
    private let playPauseButton = UIButton(type: .custom)
    private let playPauseIcon = PlayPauseIconControl(size: IconStyle.playerPrimary.pointSize)
    private let forwardButton = AnycastIconButton(
        style: .plain, icon: AppIcons.forward30, accessibilityLabel: "Seek forward 30 seconds",
        diameter: Layout.transportSlot, glyphSize: IconStyle.playerTransport.pointSize,
        glyphWeight: IconStyle.playerTransport.weight, metrics: TypographyV2.headlineMedium
    )
    private var playSlotConstraints: [NSLayoutConstraint] = []
    private var playGlyphConstraints: [NSLayoutConstraint] = []
    private let controlsRow = UIView()
    private let stack = UIStackView()
    private var scrubberFooter: UIView?

    /// When set, the play button runs this instead of toggling the current
    /// item. The transcript page uses it to adopt a browsed episode without
    /// the button pausing whatever is already playing.
    var onPlay: (() -> Void)?

    init(context: UIContext) {
        self.context = context
        super.init(frame: .zero)
        build()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.updateScrubberSpacing()
            self.applyTransportMetrics()
        }
        progressBar.onSeek = { [weak self] position in
            guard let self else { return }
            Task { await self.context.playback.seek(position) }
        }
        render()
        observation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.context.playback.currentEpisodeContent
                _ = self.context.playback.positionData
                _ = self.context.playback.isPlaying
                _ = self.context.playback.isLoading
            },
            onChange: { [weak self] in self?.render() }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Accessories

    /// Pins round accessory buttons to the leading / trailing ends of the
    /// transport row, centered on the play button. The skip slots are
    /// 72 pt wide with the glyph centered, so a 44 pt accessory at the row
    /// end clears the glyph ink.
    func setAccessories(leading: UIView?, trailing: UIView?) {
        for (view, isLeading) in [(leading, true), (trailing, false)] {
            guard let view else { continue }
            view.translatesAutoresizingMaskIntoConstraints = false
            controlsRow.addSubview(view)
            NSLayoutConstraint.activate([
                view.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
                isLeading
                    ? view.leadingAnchor.constraint(equalTo: controlsRow.leadingAnchor)
                    : view.trailingAnchor.constraint(equalTo: controlsRow.trailingAnchor),
            ])
        }
    }

    /// A line under the scrubber's time labels (the main page's current
    /// chapter); nil removes it.
    func setScrubberFooter(_ footer: UIView?) {
        scrubberFooter?.removeFromSuperview()
        scrubberFooter = footer
        if let footer {
            stack.insertArrangedSubview(footer, at: stack.arrangedSubviews.firstIndex(of: progressBar)! + 1)
        }
        updateScrubberSpacing()
    }

    /// Marks chapter starts on the scrubber.
    func setChapterMarks(_ startsMilliseconds: [Int64]) {
        progressBar.setChapterMarks(startsMilliseconds)
    }

    // MARK: - Build

    private func build() {
        progressBar.setContentCompressionResistancePriority(UILayoutPriority(800), for: .vertical)
        buildControls()

        stack.axis = .vertical
        for view in [progressBar, controlsRow] {
            stack.addArrangedSubview(view)
        }
        updateScrubberSpacing()
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    /// The scrubber's time labels hang below its fixed-height frame, so the
    /// gap to the transport grows with the label font to keep the visible
    /// gap at the rhythm under Dynamic Type.
    private func updateScrubberSpacing() {
        let metrics = UIFontMetrics(forTextStyle: .footnote)
        let growth = metrics.scaledValue(for: Layout.timeLabelLine, compatibleWith: traitCollection) - Layout.timeLabelLine
        if let scrubberFooter {
            // The footer sits in the band the time labels leave below them.
            stack.setCustomSpacing(growth - Layout.footerTuck, after: progressBar)
            stack.setCustomSpacing(Layout.footerToTransport, after: scrubberFooter)
        } else {
            stack.setCustomSpacing(Layout.scrubberToTransport + growth, after: progressBar)
        }
    }

    /// replay_10 / play-pause / forward_30 (player.dart:1303-1367); the
    /// −10 s / +30 s deltas are the Dart Controls' seekByRelative values.
    /// UI kit transport: bare glyphs, play exactly centered with the skips
    /// placed symmetrically (their glyph widths differ, so no spacers).
    private func buildControls() {
        replayButton.addAction(
            UIAction { [weak self] _ in self?.context.playback.seekByRelative(-10_000) },
            for: .touchUpInside
        )
        forwardButton.addAction(
            UIAction { [weak self] _ in self?.context.playback.seekByRelative(30_000) },
            for: .touchUpInside
        )
        replayButton.accessibilityIdentifier = "player-replay-10"
        forwardButton.accessibilityIdentifier = "player-forward-30"
        for button in [replayButton, forwardButton] {
            button.configuration?.baseForegroundColor = Theme.playerText
        }

        playPauseButton.isAccessibilityElement = true
        playPauseButton.accessibilityLabel = "Play or pause"
        playPauseButton.enableIconLargeContentViewer()
        // The button is the accessible control. The icon only draws.
        playPauseIcon.isUserInteractionEnabled = false
        playPauseIcon.isAccessibilityElement = false
        playPauseIcon.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.addSubview(playPauseIcon)
        playPauseButton.addPressFeedback(scale: Motion.pressScaleStrong)
        playPauseButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                if let onPlay = self.onPlay {
                    onPlay()
                    return
                }
                Task { await self.context.playback.togglePlay() }
            },
            for: .touchUpInside
        )

        for button in [replayButton, playPauseButton, forwardButton] as [UIView] {
            button.translatesAutoresizingMaskIntoConstraints = false
            controlsRow.addSubview(button)
        }
        let leadingSpan = UILayoutGuide()
        let trailingSpan = UILayoutGuide()
        controlsRow.addLayoutGuide(leadingSpan)
        controlsRow.addLayoutGuide(trailingSpan)
        let playWidth = playPauseButton.widthAnchor.constraint(equalToConstant: Layout.transportSlot)
        let playHeight = playPauseButton.heightAnchor.constraint(equalToConstant: Layout.transportSlot)
        let glyphWidth = playPauseIcon.widthAnchor.constraint(equalToConstant: IconStyle.playerPrimary.pointSize)
        let glyphHeight = playPauseIcon.heightAnchor.constraint(equalToConstant: IconStyle.playerPrimary.pointSize)
        playSlotConstraints = [playWidth, playHeight]
        playGlyphConstraints = [glyphWidth, glyphHeight]
        NSLayoutConstraint.activate([
            playPauseButton.centerXAnchor.constraint(equalTo: controlsRow.centerXAnchor),
            playPauseButton.topAnchor.constraint(equalTo: controlsRow.topAnchor),
            playPauseButton.bottomAnchor.constraint(equalTo: controlsRow.bottomAnchor),
            playWidth, playHeight,
            playPauseIcon.centerXAnchor.constraint(equalTo: playPauseButton.centerXAnchor),
            playPauseIcon.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            // Explicit size: the loading lottie's canvas must never be able
            // to stretch the control past its slot (R2).
            glyphWidth, glyphHeight,

            // Five controls on equal centers: each skip sits midway between
            // the play button and the row-end accessory slot.
            leadingSpan.leadingAnchor.constraint(equalTo: controlsRow.leadingAnchor, constant: Layout.accessorySlot / 2),
            leadingSpan.trailingAnchor.constraint(equalTo: playPauseButton.centerXAnchor),
            trailingSpan.leadingAnchor.constraint(equalTo: playPauseButton.centerXAnchor),
            trailingSpan.trailingAnchor.constraint(equalTo: controlsRow.trailingAnchor, constant: -Layout.accessorySlot / 2),
            replayButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            replayButton.centerXAnchor.constraint(equalTo: leadingSpan.centerXAnchor),
            forwardButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            forwardButton.centerXAnchor.constraint(equalTo: trailingSpan.centerXAnchor),
        ])
        applyTransportMetrics()
    }

    /// Skip slots and the center play glyph grow together with headline
    /// metrics. At the default content size the slots stay 72 and the
    /// glyph stays 56.
    private func applyTransportMetrics() {
        let side = IconMetrics.diameter(
            Layout.transportSlot,
            style: TypographyV2.headlineMedium,
            compatibleWith: traitCollection
        )
        let glyph = side * (IconStyle.playerPrimary.pointSize / Layout.transportSlot)
        for constraint in playSlotConstraints { constraint.constant = side }
        for constraint in playGlyphConstraints { constraint.constant = glyph }
    }

    // MARK: - Rendering (ObservationLoop-driven)

    /// Everything the controls show besides the position. Position ticks
    /// arrive twice a second; only the scrubber moves with them, so the
    /// buttons, glyph and accessibility are re-applied only when this
    /// changes.
    private struct ControlState: Equatable {
        var visual: PlayerProgressVisualState
        var controlsEnabled: Bool
        var enclosureURL: String?
        var isPlaying: Bool
        var isLoading: Bool
    }

    private var renderedControlState: ControlState?

    private func render() {
        let playback = context.playback
        let episode = playback.currentEpisode
        let position = playback.positionData

        progressBar.update(
            positionMilliseconds: position.positionMilliseconds,
            bufferedMilliseconds: position.bufferedMilliseconds,
            durationMilliseconds: position.durationMilliseconds
        )

        let hasEpisode = episode?.enclosureUrl?.isEmpty == false
        let state = ControlState(
            visual: PlayerProgressVisualState.resolve(
                hasEpisode: hasEpisode,
                isLoading: playback.isLoading,
                durationMilliseconds: position.durationMilliseconds
            ),
            // Dart gates every control on loading + having an episode
            // (Controls, player.dart:1310-1313); disabled tints to 38%.
            controlsEnabled: !playback.isLoading && hasEpisode,
            enclosureURL: episode?.enclosureUrl,
            isPlaying: playback.isPlaying,
            isLoading: playback.isLoading
        )
        guard state != renderedControlState else { return }
        renderedControlState = state

        progressBar.setAllowsSeek(state.visual.allowsSeek, statusMessage: state.visual.message)

        replayButton.isEnabled = state.controlsEnabled
        forwardButton.isEnabled = state.controlsEnabled
        playPauseButton.isEnabled = state.controlsEnabled
        let alpha: CGFloat = state.controlsEnabled ? 1 : 0.38
        replayButton.alpha = alpha
        forwardButton.alpha = alpha
        playPauseButton.alpha = alpha

        playPauseIcon.update(
            snapshot: .init(
                enclosureURL: state.enclosureURL,
                currentEnclosureURL: state.enclosureURL,
                isPlaying: state.isPlaying,
                isLoading: state.isLoading
            ),
            tint: Theme.playerText
        )
    }
}
