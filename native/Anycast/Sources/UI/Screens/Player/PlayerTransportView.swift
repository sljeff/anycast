import UIKit
import AnycastKit

/// The player's scrubber + transport block (state message, progress bar,
/// replay 10 / play-pause / forward 30), shared by the main page and the
/// transcript page so play/pause is one component everywhere. It owns its
/// own playback observation (episode, position, playing, loading) and the
/// loading/disabled gating; hosts only place it and, optionally, pin
/// accessory buttons to the ends of the transport row.
final class PlayerTransportView: UIView {

    enum Layout {
        /// The transport's touch slots (UI kit `playerControls` container).
        static let transportSlot: CGFloat = 72
        /// Gap between the play slot and the skip slots (glyph centers
        /// ~100 pt apart, as in the UI kit).
        static let transportGap = Spacing.sectionGap
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

    private let stateMessageLabel = UILabel()
    private let progressBar = PlayerProgressBarView()
    private let replayButton = AnycastIconButton(
        style: .plain, icon: AppIcons.replay10, accessibilityLabel: "Seek back 10 seconds",
        diameter: Layout.transportSlot, glyphSize: IconStyle.playerTransport.pointSize
    )
    private let playPauseButton = UIButton(type: .custom)
    private let playPauseIcon = PlayPauseIconControl(size: IconStyle.playerPrimary.pointSize)
    private let forwardButton = AnycastIconButton(
        style: .plain, icon: AppIcons.forward30, accessibilityLabel: "Seek forward 30 seconds",
        diameter: Layout.transportSlot, glyphSize: IconStyle.playerTransport.pointSize
    )
    private let controlsRow = UIView()
    private let stack = UIStackView()
    private var scrubberFooter: UIView?

    /// Play-to-skip slot gap; pages with row-end accessories pass a tighter
    /// one so the skip glyphs clear the 44 pt accessory buttons.
    private let transportGap: CGFloat

    init(context: UIContext, transportGap: CGFloat = Layout.transportGap) {
        self.context = context
        self.transportGap = transportGap
        super.init(frame: .zero)
        build()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.updateScrubberSpacing()
        }
        progressBar.onSeek = { [weak self] position in
            guard let self else { return }
            Task { await self.context.playback.seek(position) }
        }
        render()
        observation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.context.playback.currentEpisode
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
        stateMessageLabel.font = TypographyV2.meta.font()
        stateMessageLabel.textColor = Theme.playerSecondary
        stateMessageLabel.textAlignment = .center
        stateMessageLabel.adjustsFontForContentSizeCategory = true
        stateMessageLabel.isHidden = true

        progressBar.setContentCompressionResistancePriority(UILayoutPriority(800), for: .vertical)
        buildControls()

        stack.axis = .vertical
        for view in [stateMessageLabel, progressBar, controlsRow] {
            stack.addArrangedSubview(view)
        }
        stack.setCustomSpacing(Spacing.xs, after: stateMessageLabel)
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
        playPauseIcon.isUserInteractionEnabled = false
        playPauseIcon.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.addSubview(playPauseIcon)
        playPauseButton.addPressFeedback(scale: Motion.pressScaleStrong)
        playPauseButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                Task { await self.context.playback.togglePlay() }
            },
            for: .touchUpInside
        )

        for button in [replayButton, playPauseButton, forwardButton] as [UIView] {
            button.translatesAutoresizingMaskIntoConstraints = false
            controlsRow.addSubview(button)
        }
        NSLayoutConstraint.activate([
            playPauseButton.centerXAnchor.constraint(equalTo: controlsRow.centerXAnchor),
            playPauseButton.topAnchor.constraint(equalTo: controlsRow.topAnchor),
            playPauseButton.bottomAnchor.constraint(equalTo: controlsRow.bottomAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: Layout.transportSlot),
            playPauseButton.heightAnchor.constraint(equalToConstant: Layout.transportSlot),
            playPauseIcon.centerXAnchor.constraint(equalTo: playPauseButton.centerXAnchor),
            playPauseIcon.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            // Explicit size: the loading lottie's canvas must never be able
            // to stretch the control past its slot (R2).
            playPauseIcon.widthAnchor.constraint(equalToConstant: IconStyle.playerPrimary.pointSize),
            playPauseIcon.heightAnchor.constraint(equalToConstant: IconStyle.playerPrimary.pointSize),

            replayButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            replayButton.trailingAnchor.constraint(equalTo: playPauseButton.leadingAnchor, constant: -transportGap),
            replayButton.leadingAnchor.constraint(greaterThanOrEqualTo: controlsRow.leadingAnchor),
            forwardButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            forwardButton.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: transportGap),
            forwardButton.trailingAnchor.constraint(lessThanOrEqualTo: controlsRow.trailingAnchor),
        ])
    }

    // MARK: - Rendering (ObservationLoop-driven)

    private func render() {
        let episode = context.playback.currentEpisode
        let position = context.playback.positionData

        let state = PlayerProgressVisualState.resolve(
            hasEpisode: (episode?.enclosureUrl?.isEmpty == false),
            isLoading: context.playback.isLoading,
            durationMilliseconds: position.durationMilliseconds
        )
        if let message = state.message {
            stateMessageLabel.text = message
            stateMessageLabel.isHidden = false
        } else {
            stateMessageLabel.isHidden = true
        }
        progressBar.setAllowsSeek(state.allowsSeek)
        progressBar.update(
            positionMilliseconds: position.positionMilliseconds,
            bufferedMilliseconds: position.bufferedMilliseconds,
            durationMilliseconds: position.durationMilliseconds
        )

        // Dart gates every control on loading + having an episode
        // (Controls, player.dart:1310-1313); disabled tints to 38%.
        let controlsEnabled = !context.playback.isLoading
            && episode?.enclosureUrl?.isEmpty == false
        replayButton.isEnabled = controlsEnabled
        forwardButton.isEnabled = controlsEnabled
        playPauseButton.isEnabled = controlsEnabled
        let alpha: CGFloat = controlsEnabled ? 1 : 0.38
        replayButton.alpha = alpha
        forwardButton.alpha = alpha
        playPauseButton.alpha = alpha

        playPauseIcon.update(
            snapshot: .init(
                enclosureURL: episode?.enclosureUrl,
                currentEnclosureURL: episode?.enclosureUrl,
                isPlaying: context.playback.isPlaying,
                isLoading: context.playback.isLoading
            ),
            tint: Theme.playerText
        )
    }
}
