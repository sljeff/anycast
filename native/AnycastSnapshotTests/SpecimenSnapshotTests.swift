import UIKit
import Testing
@testable import Anycast

/// One specimen snapshot proving the L4 baseline infrastructure (05 §6.1):
/// a dark-theme composition of an EpisodeCardCell + UnderlineTabBarView +
/// GradientTextLabel, recorded per iOS major version. Later M3 tasks grow
/// this suite screen by screen (S1–S21).
@MainActor
struct SpecimenSnapshotTests {

    @Test("Specimen: card + underline tab bar + gradient title")
    func specimen() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 320))
        Theme.installDarkBase(on: container)

        let title = GradientTextLabel()
        title.text = "Anycast"
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        let tabBar = UnderlineTabBarView(titles: ["Inbox", "Subscriptions"])
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabBar)
        NSLayoutConstraint.activate([
            tabBar.heightAnchor.constraint(equalToConstant: 40),
        ])

        let card = EpisodeCardCell(
            frame: CGRect(x: 16, y: 160, width: 358, height: EpisodeCardCell.cardRowHeight)
        )
        card.configure(
            EpisodeCardContent(
                title: "Episode title specimen",
                channelTitle: "Channel name",
                rightText: "42m • just now",
                descriptionHTML: "<p>Two line description specimen with <b>markup</b> stripped by htmlToText.</p>",
                imageURL: nil,
                descriptionPlainText: "Two line description specimen with markup stripped by htmlToText."
            ),
            actions: [
                EpisodeCardAction(icon: AppIcons.play, accessibilityLabel: "Play") {},
                EpisodeCardAction(icon: AppIcons.addToList, accessibilityLabel: "Add to playlist") {},
                EpisodeCardAction(icon: AppIcons.remove, accessibilityLabel: "Remove") {},
            ]
        )
        card.setExpanded(false)
        container.addSubview(card)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            tabBar.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
        ])

        container.setNeedsLayout()
        container.layoutIfNeeded()

        try SnapshotBaseline.assertSnapshot(of: container, named: "specimen-dark")
    }
}
