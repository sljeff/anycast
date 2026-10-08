import UIKit
import AnycastKit

/// The v2 Welcome screen (Figma 131:2742 — 09 §4 S17, V2 scope): the
/// pre-auth marketing entry. Mail opens the existing email login sheet;
/// Apple and the sign-up link are UI-only until product enables them
/// (09 §8: `registerWithEmail` is dead code on the Flutter line — auth
/// wiring deliberately left as TODO, not silently enabled). The display
/// face (Young Serif/Instrument Serif in Figma) is undecided (09 §0) —
/// system-font placeholders until that call lands.
@MainActor
final class WelcomeViewController: UIViewController {

    private let context: UIContext

    init(context: UIContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let wordmark = UILabel()
        wordmark.text = "anycast"
        wordmark.font = TypographyV2.displayMedium.font()
        wordmark.adjustsFontForContentSizeCategory = true
        wordmark.textColor = Theme.onSurface
        wordmark.accessibilityIdentifier = "welcome-wordmark"

        let tagline = UILabel()
        tagline.text = "next gen ai-power podcast"
        tagline.font = TypographyV2.bodySmall.font()
        tagline.adjustsFontForContentSizeCategory = true
        tagline.textColor = Theme.onSurfaceVariant

        let brand = UIStackView(arrangedSubviews: [wordmark, tagline])
        brand.axis = .vertical
        brand.spacing = Spacing.xxs
        brand.alignment = .leading

        let marketingTitle = UILabel()
        marketingTitle.text = "Unlock global knowledge through ai-power podcast"
        marketingTitle.font = TypographyV2.displayLarge.font()
        marketingTitle.adjustsFontForContentSizeCategory = true
        marketingTitle.textColor = Theme.onSurface
        marketingTitle.numberOfLines = 0

        let marketingSubtitle = UILabel()
        marketingSubtitle.text = "explore global wisdom cross many languages*"
        marketingSubtitle.font = TypographyV2.bodyLarge.font()
        marketingSubtitle.adjustsFontForContentSizeCategory = true
        marketingSubtitle.textColor = Theme.onSurface
        marketingSubtitle.numberOfLines = 0

        let column = UIStackView(arrangedSubviews: [
            brand, marketingTitle, marketingSubtitle,
        ])
        column.axis = .vertical
        column.spacing = Spacing.sectionGap
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)

        let continueButton = buildContinueButton()
        let authRow = buildAuthRow()
        // Both must join the hierarchy BEFORE the constraints activate —
        // pinning views with no common ancestor throws.
        view.addSubview(continueButton)
        view.addSubview(authRow)

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            column.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Spacing.sectionGap
            ),

            continueButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            continueButton.bottomAnchor.constraint(
                equalTo: authRow.topAnchor, constant: -Spacing.gap
            ),
            authRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            authRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            authRow.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Spacing.gap
            ),
        ])
    }

    // MARK: - The 96 pt dark-gradient forward CTA (Figma 131:2782)

    private func buildContinueButton() -> UIView {
        let button = UIButton(type: .custom)
        button.accessibilityIdentifier = "welcome-continue"
        button.accessibilityLabel = "Continue"

        let gradient = CAGradientLayer()
        gradient.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
        gradient.cornerRadius = 48
        gradient.colors = [
            AnycastColor.sandAlpha12.cgColor,
            AnycastColor.sandAlpha11.cgColor,
        ]
        gradient.locations = [0, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        button.layer.insertSublayer(gradient, at: 0)
        button.layer.cornerRadius = 48
        button.layer.cornerCurve = .continuous
        button.layer.borderColor = AnycastColor.sandAlpha4.cgColor
        button.layer.borderWidth = Spacing.hairline
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.1
        button.layer.shadowOffset = CGSize(width: 0, height: 20)
        button.layer.shadowRadius = 20
        button.setImage(UIImage(systemName: "arrow.forward"), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 32, weight: .medium),
            forImageIn: .normal
        )
        button.tintColor = .white
        // Entering without an account (the pre-auth bypass the v1 app had).
        button.addAction(
            UIAction { [weak self] _ in self?.dismiss(animated: true) },
            for: .touchUpInside
        )
        button.widthAnchor.constraint(equalToConstant: 96).isActive = true
        button.heightAnchor.constraint(equalToConstant: 96).isActive = true
        return button
    }

    // MARK: - Mail entry + sign-up link (Apple stays TODO, 09 §8)

    private func buildAuthRow() -> UIView {
        let mailButton = UIButton(type: .system)
        var mailConfig = UIButton.Configuration.plain()
        mailConfig.image = AppIcons.email
        mailConfig.imagePadding = Spacing.md
        mailConfig.title = "Continue with email"
        mailConfig.baseForegroundColor = Theme.onSurface
        mailConfig.background.backgroundColor = Theme.surfaceContainer
        mailConfig.background.cornerRadius = Radius.pill
        mailConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 14, leading: Spacing.pageH, bottom: 14, trailing: Spacing.pageH
        )
        mailButton.configuration = mailConfig
        mailButton.accessibilityIdentifier = "welcome-email"
        mailButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                AppSheets.presentExpand(
                    EmailLoginViewController(context: self.context), from: self
                )
            },
            for: .touchUpInside
        )
        mailButton.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let appleButton = UIButton(type: .system)
        var appleConfig = UIButton.Configuration.plain()
        appleConfig.image = AppIcons.appleLogo
        appleConfig.imagePadding = Spacing.md
        appleConfig.title = "Continue with Apple"
        appleConfig.baseForegroundColor = Theme.onSurface
        appleConfig.background.backgroundColor = Theme.surfaceContainer
        appleConfig.background.cornerRadius = Radius.pill
        appleConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 14, leading: Spacing.pageH, bottom: 14, trailing: Spacing.pageH
        )
        appleButton.configuration = appleConfig
        appleButton.accessibilityIdentifier = "welcome-apple"
        appleButton.addAction(
            UIAction { [weak self] _ in
                // TODO(auth): Apple sign-in is not implemented on the v1
                // line either — wired when product enables it (09 §8).
                self?.notifyUnavailable("Apple sign-in")
            },
            for: .touchUpInside
        )
        appleButton.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let buttonRow = UIStackView(arrangedSubviews: [appleButton, mailButton])
        buttonRow.axis = .vertical
        buttonRow.spacing = Spacing.md

        let questionLabel = UILabel()
        questionLabel.text = "New here?"
        questionLabel.font = TypographyV2.bodySmall.font()
        questionLabel.textColor = AnycastColor.sand11

        let signUpButton = UIButton(type: .system)
        signUpButton.setTitle("Sign up", for: .normal)
        signUpButton.setTitleColor(AnycastColor.grass9, for: .normal)
        signUpButton.titleLabel?.font = TypographyV2.bodySmall.font()
        signUpButton.accessibilityIdentifier = "welcome-signup"
        signUpButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                let signUp = SignUpViewController(context: self.context)
                signUp.modalPresentationStyle = .fullScreen
                self.present(signUp, animated: true)
            },
            for: .touchUpInside
        )

        let linkRow = UIStackView(arrangedSubviews: [questionLabel, signUpButton])
        linkRow.axis = .horizontal
        linkRow.spacing = Spacing.xs
        linkRow.alignment = .center

        let column = UIStackView(arrangedSubviews: [buttonRow, linkRow])
        column.axis = .vertical
        column.spacing = Spacing.gap
        column.alignment = .center
        column.translatesAutoresizingMaskIntoConstraints = false
        return column
    }

    private func notifyUnavailable(_ what: String) {
        let alert = UIAlertController(
            title: what, message: "Isn’t available yet.", preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
