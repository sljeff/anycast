import UIKit

/// Placeholder rows shown in place of a blank full-page spinner. The blocks
/// match the real row metrics (episode card, grouped channel row, channel
/// episode row). Reduce Motion holds them still; otherwise they breathe.
@MainActor
final class SkeletonListView: UIView {

    enum Style {
        case episodeCards
        case channelRows
        case channelEpisodes
    }

    private var bones: [UIView] = []
    private var watchingMotion = false
    /// A dismiss fade is in flight; callers must not force-hide over it.
    private(set) var isDismissing = false

    init(style: Style) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isHidden = true
        accessibilityLabel = "Loading"
        clipsToBounds = true
        insetsLayoutMarginsFromSafeArea = false
        directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0, leading: Spacing.pageH, bottom: 0, trailing: Spacing.pageH
        )
        build(style)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, !watchingMotion, MotionProto.isEnabled(.reduceMotion) {
            watchingMotion = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(reduceMotionChanged),
                name: Motion.reduceMotionDidChange,
                object: nil
            )
        }
        syncPulse()
    }

    func setShown(_ shown: Bool) {
        guard !isDismissing else { return }
        isHidden = !shown
        isAccessibilityElement = shown
        accessibilityElementsHidden = !shown
        if shown {
            alpha = 1
            syncPulse()
        } else {
            stopPulse()
        }
    }

    /// Fades out, then hides. Opacity only, so it is also the Reduce Motion path.
    func dismissAnimated() {
        guard !isHidden, !isDismissing else {
            isHidden = true
            return
        }
        isDismissing = true
        stopPulse()
        UIView.animate(
            withDuration: Motion.quick,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.alpha = 0
        } completion: { [weak self] _ in
            guard let self else { return }
            self.isHidden = true
            self.alpha = 1
            self.isDismissing = false
            self.isAccessibilityElement = false
        }
    }

    @objc private func reduceMotionChanged() {
        syncPulse()
    }

    private func syncPulse() {
        guard !isHidden, window != nil, !Motion.reduceMotion, !isDismissing else {
            stopPulse()
            return
        }
        guard bones.first?.layer.animation(forKey: "skeletonPulse") == nil else { return }
        for bone in bones {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1
            animation.toValue = 0.45
            animation.duration = 0.9
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bone.layer.add(animation, forKey: "skeletonPulse")
        }
    }

    private func stopPulse() {
        for bone in bones {
            bone.layer.removeAnimation(forKey: "skeletonPulse")
            bone.layer.opacity = 1
        }
    }

    private func build(_ style: Style) {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
        ])

        switch style {
        case .episodeCards:
            stack.spacing = Spacing.gap
            for _ in 0..<5 { stack.addArrangedSubview(episodeCard()) }
        case .channelRows:
            stack.addArrangedSubview(grouped(rows: (0..<6).map { _ in channelRow() }, radius: Radius.card))
        case .channelEpisodes:
            stack.addArrangedSubview(grouped(rows: (0..<8).map { _ in episodeRow() }, radius: Radius.card))
        }
    }

    private func episodeCard() -> UIView {
        let plate = UIView()
        plate.backgroundColor = Theme.surfaceContainer
        plate.layer.cornerRadius = Radius.largeCard
        plate.layer.cornerCurve = .continuous
        plate.translatesAutoresizingMaskIntoConstraints = false
        plate.heightAnchor.constraint(equalToConstant: EpisodeCardCell.cardRowHeight).isActive = true

        let cover = bone()
        cover.layer.cornerRadius = Radius.artwork
        plate.addSubview(cover)
        let lines = textColumn(fractions: [0.72, 0.4, 0.88], spacing: Spacing.sm)
        plate.addSubview(lines)
        NSLayoutConstraint.activate([
            cover.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: Spacing.gap),
            cover.centerYAnchor.constraint(equalTo: plate.centerYAnchor),
            cover.widthAnchor.constraint(equalToConstant: EpisodeCardCell.coverSide),
            cover.heightAnchor.constraint(equalToConstant: EpisodeCardCell.coverSide),
            lines.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: Spacing.gap),
            lines.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -Spacing.gap),
            lines.centerYAnchor.constraint(equalTo: plate.centerYAnchor),
        ])
        return plate
    }

    private func channelRow() -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: PodcastCardCell.rowHeight).isActive = true
        let cover = bone()
        cover.layer.cornerRadius = Radius.sm
        row.addSubview(cover)
        let lines = textColumn(fractions: [0.55, 0.86], spacing: Spacing.xs)
        row.addSubview(lines)
        NSLayoutConstraint.activate([
            cover.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Spacing.gap),
            cover.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            cover.widthAnchor.constraint(equalToConstant: PodcastCardCell.coverSide),
            cover.heightAnchor.constraint(equalToConstant: PodcastCardCell.coverSide),
            lines.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: Spacing.gap),
            lines.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Spacing.gap),
            lines.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func episodeRow() -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: ChannelEpisodeRowCell.minimumHeight).isActive = true
        let lines = textColumn(fractions: [0.7, 0.38], spacing: Spacing.xs)
        row.addSubview(lines)
        NSLayoutConstraint.activate([
            lines.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Spacing.gap),
            lines.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Spacing.gap),
            lines.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func grouped(rows: [UIView], radius: CGFloat) -> UIView {
        let plate = UIView()
        plate.backgroundColor = Theme.surfaceContainer
        plate.layer.cornerRadius = radius
        plate.layer.cornerCurve = .continuous
        plate.clipsToBounds = true
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: plate.topAnchor),
            stack.leadingAnchor.constraint(equalTo: plate.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: plate.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: plate.bottomAnchor),
        ])
        return plate
    }

    private func bone() -> UIView {
        let view = UIView()
        view.backgroundColor = Theme.surfaceContainerHighest
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isAccessibilityElement = false
        bones.append(view)
        return view
    }

    /// Leading-aligned bars whose widths are fractions of the column. The
    /// column itself is pinned by the caller, so the fractions are not ambiguous.
    private func textColumn(fractions: [CGFloat], spacing: CGFloat) -> UIStackView {
        let lines = UIStackView()
        lines.axis = .vertical
        lines.alignment = .leading
        lines.spacing = spacing
        lines.translatesAutoresizingMaskIntoConstraints = false
        for fraction in fractions {
            let view = bone()
            view.layer.cornerRadius = Spacing.xs
            lines.addArrangedSubview(view)
            view.heightAnchor.constraint(equalToConstant: 10).isActive = true
            view.widthAnchor.constraint(equalTo: lines.widthAnchor, multiplier: fraction).isActive = true
        }
        return lines
    }
}
