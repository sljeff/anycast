import UIKit
import AnycastKit

/// Interim search entry sheet behind the pill bar's search circle
/// (09 §3.1: first version taps push the Search screen; the "ask
/// anything" combined input stays pending a product call). Presents a
/// v2-styled field whose submit opens the existing global search sheet —
/// the same submit semantics the v1 AppBar field had. The full v2 search
/// screen (browse list, 1243:8561) is the V3 batch-4 scope and replaces
/// this entry wholesale.
@MainActor
final class SearchEntryViewController: UIViewController {

    private let context: UIContext
    private let searchField = UITextField()

    init(context: UIContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)
        sheetPresentationController?.prefersGrabberVisible = true

        let icon = UIImageView(image: AppIcons.search)
        icon.tintColor = Theme.onSurfaceVariant
        icon.contentMode = .center
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18)
        icon.translatesAutoresizingMaskIntoConstraints = false

        searchField.leftView = icon
        searchField.leftViewMode = .always
        // 09 §3.1 activeTab prototype placeholder text.
        searchField.placeholder = "search | ask anything"
        searchField.font = TypographyV2.bodyLarge.font()
        searchField.adjustsFontForContentSizeCategory = true
        searchField.textColor = Theme.onSurface
        searchField.attributedPlaceholder = NSAttributedString(
            string: searchField.placeholder ?? "",
            attributes: [.foregroundColor: Theme.onSurfaceVariant]
        )
        searchField.backgroundColor = Theme.surfaceContainer
        searchField.layer.cornerRadius = Radius.md
        searchField.layer.cornerCurve = .continuous
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.clearButtonMode = .whileEditing
        searchField.accessibilityIdentifier = "search-entry-field"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.addTarget(
            self, action: #selector(searchSubmitted), for: .primaryActionTriggered
        )

        view.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            searchField.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Spacing.gap
            ),
            searchField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchField.becomeFirstResponder()
    }

    /// Non-empty submit opens the global search sheet (the v1 AppBar
    /// submit semantics, appbar.dart:97-107).
    @objc private func searchSubmitted() {
        let text = (searchField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searchField.resignFirstResponder()
        SearchPageViewController.present(from: self, context: context, searchText: text)
    }
}
