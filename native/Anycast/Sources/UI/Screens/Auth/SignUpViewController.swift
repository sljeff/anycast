import UIKit
import AnycastKit

/// The v2 Sign-up UI (Figma 131:2540 — 09 §4, V2 scope). UI ONLY: the
/// submit does not create an account — `registerWithEmail` is dead code on
/// the Flutter line and product has not enabled registration (09 §8). The
/// TODO stays until that decision lands; the screen exists so the flow,
/// layout, and tokens are reviewable and testable.
@MainActor
final class SignUpViewController: UIViewController {

    private let context: UIContext

    private let emailField = AuthFieldView(label: "Email")
    private let passwordField = AuthFieldView(label: "Password", secure: true)
    private let confirmField = AuthFieldView(label: "Confirm password", secure: true)

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
        buildNavigation()
        buildForm()
    }

    private func buildNavigation() {
        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
            forImageIn: .normal
        )
        back.tintColor = Theme.onSurface
        back.accessibilityLabel = "Back"
        back.accessibilityIdentifier = "signup-back"
        back.addAction(
            UIAction { [weak self] _ in self?.dismiss(animated: true) },
            for: .touchUpInside
        )
        back.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(back)
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            back.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Spacing.xs),
            back.widthAnchor.constraint(equalToConstant: 44),
            back.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func buildForm() {
        let wordmark = UILabel()
        wordmark.text = "anycast"
        wordmark.font = TypographyV2.displaySmall.font()
        wordmark.adjustsFontForContentSizeCategory = true
        wordmark.textColor = Theme.onSurface
        wordmark.accessibilityIdentifier = "signup-wordmark"

        let tagline = UILabel()
        tagline.text = "next gen ai-power podcast"
        tagline.font = TypographyV2.bodySmall.font()
        tagline.textColor = Theme.onSurfaceVariant

        let brand = UIStackView(arrangedSubviews: [wordmark, tagline])
        brand.axis = .vertical
        brand.spacing = Spacing.xxs
        brand.alignment = .leading

        let submit = UIButton(type: .system)
        var submitConfig = UIButton.Configuration.filled()
        submitConfig.title = "Sign up"
        submitConfig.baseBackgroundColor = Theme.primary
        submitConfig.baseForegroundColor = Theme.onPrimary
        submitConfig.cornerStyle = .capsule
        submitConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 18, leading: Spacing.pageH, bottom: 18, trailing: Spacing.pageH
        )
        submit.configuration = submitConfig
        submit.titleLabel?.font = TypographyV2.titleMedium.font()
        submit.accessibilityIdentifier = "signup-submit"
        submit.addAction(
            UIAction { [weak self] _ in self?.submitTapped() },
            for: .touchUpInside
        )
        submit.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let signInLabel = UILabel()
        signInLabel.text = "Already have an account?"
        signInLabel.font = TypographyV2.bodySmall.font()
        signInLabel.textColor = AnycastColor.sand11

        let signInButton = UIButton(type: .system)
        signInButton.setTitle("Sign in", for: .normal)
        signInButton.setTitleColor(AnycastColor.grass9, for: .normal)
        signInButton.titleLabel?.font = TypographyV2.bodySmall.font()
        signInButton.accessibilityIdentifier = "signup-signin"
        signInButton.addAction(
            UIAction { [weak self] _ in self?.dismiss(animated: true) },
            for: .touchUpInside
        )

        let linkRow = UIStackView(arrangedSubviews: [signInLabel, signInButton])
        linkRow.axis = .horizontal
        linkRow.spacing = Spacing.xs

        let form = UIStackView(arrangedSubviews: [
            brand, emailField, passwordField, confirmField, submit, linkRow,
        ])
        form.axis = .vertical
        form.spacing = Spacing.pageHeader
        form.alignment = .fill
        form.setCustomSpacing(Spacing.sectionGap, after: brand)
        form.setCustomSpacing(Spacing.row, after: confirmField)
        form.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(form)

        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            form.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            form.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Spacing.sectionGap
            ),
        ])
    }

    /// Registration is NOT wired (09 §8): the Flutter `registerWithEmail`
    /// path is commented-out dead code; enabling account creation is a
    /// product decision. TODO(auth): wire to the register endpoint when
    /// product green-lights it.
    private func submitTapped() {
        let alert = UIAlertController(
            title: "Sign-up isn’t available yet",
            message: "Account creation hasn’t been enabled for this build.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

/// One Figma `AuthInput` (134:2531): a label row over a 48 pt rounded
/// field — surfaceContainer fill (the cream `.03` input role mapped per
/// 09 §6a), sandAlpha4 hairline, radius 12.
@MainActor
final class AuthFieldView: UIControl {

    private let field = UITextField()

    init(label: String, secure: Bool = false) {
        super.init(frame: .zero)

        let labelView = UILabel()
        labelView.text = label
        labelView.font = TypographyV2.bodySmall.font()
        labelView.textColor = Theme.onSurfaceVariant

        field.isSecureTextEntry = secure
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardType = secure ? .default : .emailAddress
        field.returnKeyType = .done
        field.font = TypographyV2.bodyLarge.font()
        field.textColor = Theme.onSurface
        field.backgroundColor = Theme.surfaceContainer
        field.layer.borderColor = AnycastColor.sandAlpha4.cgColor
        field.layer.borderWidth = 0.5
        field.layer.cornerRadius = Radius.sm + Spacing.xs
        field.layer.cornerCurve = .continuous
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: Spacing.pageH, height: 1))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: Spacing.chip, height: 1))
        field.rightViewMode = .always
        field.accessibilityLabel = label
        field.translatesAutoresizingMaskIntoConstraints = false

        let column = UIStackView(arrangedSubviews: [labelView, field])
        column.axis = .vertical
        column.spacing = Spacing.xxs
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
    }

    var text: String? { field.text }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The hairline runs through `layer.borderColor` (CGColor freeze —
    /// 09 §9a).
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? false {
            field.layer.borderColor = AnycastColor.sandAlpha4.cgColor
        }
    }
}
