import UIKit
import SafariServices

/// The "What's in Plus" sheet stacked over the paywall: the four feature
/// rows, the Today / Day 5 / Day 7 trial timeline (only when the user is
/// trial-eligible on Yearly), and the Terms and Privacy links. It shows a
/// snapshot of the paywall model taken when it opens.
final class PaywallDetailsViewController: UIViewController {

    private let model: PaywallModel

    init(model: PaywallModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Spacing.sectionGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        stack.addArrangedSubview(section(label: PaywallModel.featuresLabel, rows: model.features.map { feature in
            PaywallInfoRowView(
                leading: .image(Self.icon(feature.icon)), title: feature.title, subtitle: feature.subtitle
            )
        }))
        let timeline = model.timeline
        if !timeline.isEmpty {
            stack.addArrangedSubview(section(label: PaywallModel.timelineLabel, rows: timeline.map { step in
                PaywallInfoRowView(
                    leading: .dot(filled: step.isCurrent), title: step.title, subtitle: step.subtitle
                )
            }))
        }
        stack.addArrangedSubview(PaywallLinksView.make(
            presenter: self, terms: PaywallModel.termsLongTitle, privacy: PaywallModel.privacyLongTitle
        ))

        let close = AnycastIconButton(style: .glass, icon: AppIcons.close, accessibilityLabel: "Close")
        close.accessibilityIdentifier = "paywall-details-close"
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        view.addSubview(close)

        let inset = Spacing.sheetContent
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.topAnchor, constant: Spacing.pageH),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            scrollView.topAnchor.constraint(equalTo: close.bottomAnchor, constant: Spacing.xs),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -inset),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Spacing.large),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * inset),
        ])
    }

    private static func icon(_ icon: PaywallModel.Feature.Icon) -> UIImage? {
        switch icon {
        case .subtitles: UIImage(systemName: "sparkles")
        case .transcripts: AppIcons.aiTranscript
        case .ask: AppIcons.aiChat
        case .export: AppIcons.newDoc
        }
    }

    private func section(label text: String, rows: [UIView]) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = TypographyV2.meta.font()
        label.textColor = Theme.onSurfaceVariant
        label.adjustsFontForContentSizeCategory = true
        let labelWrap = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        labelWrap.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: labelWrap.topAnchor),
            label.bottomAnchor.constraint(equalTo: labelWrap.bottomAnchor, constant: -Spacing.md),
            label.leadingAnchor.constraint(equalTo: labelWrap.leadingAnchor, constant: Spacing.pageHeader),
            label.trailingAnchor.constraint(equalTo: labelWrap.trailingAnchor, constant: -Spacing.pageHeader),
        ])
        label.accessibilityTraits = .header
        let column = UIStackView(arrangedSubviews: [labelWrap, AccountPlateView(fill: Theme.surface, rows: rows)])
        column.axis = .vertical
        return column
    }
}

/// "Terms · Privacy" links that open in Safari view controllers.
@MainActor
enum PaywallLinksView {

    /// A centered row of two links separated by a middle dot.
    static func make(presenter: UIViewController, terms termsTitle: String, privacy privacyTitle: String) -> UIView {
        let terms = link(termsTitle, url: LoginPageModel.termsOfUseURL, presenter: presenter)
        let privacy = link(privacyTitle, url: LoginPageModel.privacyPolicyURL, presenter: presenter)
        let separator = UILabel()
        separator.text = "·"
        separator.font = TypographyV2.meta.font()
        separator.textColor = Theme.onSurfaceVariant
        separator.isAccessibilityElement = false
        let row = UIStackView(arrangedSubviews: [terms, separator, privacy])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Spacing.xs
        let wrapper = UIStackView(arrangedSubviews: [UIView(), row, UIView()])
        wrapper.distribution = .equalCentering
        return wrapper
    }

    private static func link(_ title: String, url: URL, presenter: UIViewController) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = Theme.onSurfaceVariant
        configuration.contentInsets = NSDirectionalEdgeInsets(top: Spacing.xs, leading: Spacing.xs, bottom: Spacing.xs, trailing: Spacing.xs)
        var attributes = AttributeContainer()
        attributes.font = TypographyV2.meta.font()
        attributes.underlineStyle = .single
        configuration.attributedTitle = AttributedString(title, attributes: attributes)
        let button = UIButton(configuration: configuration)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityIdentifier = "paywall-link-\(url == LoginPageModel.termsOfUseURL ? "terms" : "privacy")"
        button.accessibilityTraits = .link
        button.addAction(UIAction { [weak presenter] _ in
            presenter?.present(SFSafariViewController(url: url), animated: true)
        }, for: .touchUpInside)
        return button
    }
}
