import UIKit
import Kingfisher
import AnycastKit

/// Full-screen viewer for a show-notes inline image. Presented over the
/// full screen (not a sheet) with a fade; the already-loaded inline bitmap
/// seeds the view instantly while Kingfisher pulls the original from the
/// disk cache (the inline load stored it via `.cacheOriginalImage`).
///
/// Zoom model: scroll-view zoom clamped to [1, 4], double-tap toggling
/// 1x / 2.5x centered on the tapped point, content centered through
/// `contentInset` whenever it is smaller than the bounds. A single tap on
/// the surrounding background or the close button dismisses, as does the
/// accessibility escape gesture. With Reduce Motion on, zoom changes are
/// applied without animation.
final class ZoomingImageViewController: UIViewController, UIScrollViewDelegate {

    /// Double-tap target scale (inside the 4x zoom ceiling).
    private static let doubleTapZoomScale: CGFloat = 2.5

    private let thumbnail: UIImage?
    private let imageURL: URL?
    private let alt: String?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private var lastLayoutBounds: CGRect = .zero

    init(thumbnail: UIImage?, imageURL: URL?, alt: String?) {
        self.thumbnail = thumbnail
        self.imageURL = imageURL
        self.alt = alt
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Presentation

    /// Builds and presents the viewer from the top-most presented
    /// controller above `presenter` (sheets stack; the repository's
    /// `topMostPresented()` extension walks the chain safely).
    static func present(
        thumbnail: UIImage?,
        imageURL: URL?,
        alt: String?,
        from presenter: UIViewController
    ) {
        let viewer = ZoomingImageViewController(
            thumbnail: thumbnail,
            imageURL: imageURL,
            alt: alt
        )
        presenter.topMostPresented().present(viewer, animated: true)
    }

    // MARK: - Lifecycle

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.image = thumbnail
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = alt
        scrollView.addSubview(imageView)

        // Double-tap zooms (toggle 1x / 2.5x around the tapped point); the
        // single-tap dismissal requires it to fail first so a double-tap
        // never dismisses.
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        configureChromeButton(closeButton, symbol: "xmark", label: "Close")
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(closeButton)

        configureChromeButton(retryButton, symbol: "arrow.clockwise", label: "Retry")
        retryButton.addTarget(self, action: #selector(retryLoad), for: .touchUpInside)
        retryButton.isHidden = true
        view.addSubview(retryButton)

        activityIndicator.color = .white
        view.addSubview(activityIndicator)

        if imageURL != nil {
            loadFullImage()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        positionChrome()
        guard view.bounds != lastLayoutBounds else { return }
        lastLayoutBounds = view.bounds
        layoutImageView()
    }

    override func accessibilityPerformEscape() -> Bool {
        dismiss(animated: true)
        return true
    }

    // MARK: - Chrome

    private func configureChromeButton(_ button: UIButton, symbol: String, label: String) {
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = label
        button.backgroundColor = UIColor(white: 0, alpha: 0.55)
        button.layer.cornerRadius = 22
        button.layer.masksToBounds = true
    }

    private func positionChrome() {
        let safe = view.safeAreaInsets
        let side: CGFloat = 44
        closeButton.frame = CGRect(x: 16, y: safe.top + 12, width: side, height: side)
        retryButton.frame = CGRect(
            x: view.bounds.width - 16 - side,
            y: safe.top + 12,
            width: side,
            height: side
        )
        activityIndicator.center = CGPoint(
            x: view.bounds.midX,
            y: view.bounds.midY
        )
    }

    // MARK: - Image layout

    /// Frames the current image with the shared aspect-fit helper and
    /// resets the zoom; called on arrival of the thumbnail/origin and on
    /// bounds changes.
    private func layoutImageView() {
        guard let image = imageView.image else {
            imageView.frame = .zero
            scrollView.contentSize = .zero
            return
        }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        scrollView.zoomScale = 1
        let fitted = ImageFit.aspectFitRect(imageSize: size, in: view.bounds).size
        // Content-space origin must stay .zero: the letterbox offset that
        // aspectFitRect carries in its ORIGIN would double up with the
        // contentInset centering below (and shift under zooming). Only the
        // fitted SIZE is used; the inset does the centering.
        imageView.frame = CGRect(origin: .zero, size: fitted)
        scrollView.contentSize = fitted
        centerImageView()
    }

    /// Centers the (possibly zoomed) content whenever it is smaller than
    /// the scroll-view bounds, via content inset.
    private func centerImageView() {
        let boundsSize = scrollView.bounds.size
        let contentSize = imageView.frame.size
        let horizontal = max(0, (boundsSize.width - contentSize.width) / 2)
        let vertical = max(0, (boundsSize.height - contentSize.height) / 2)
        scrollView.contentInset = UIEdgeInsets(
            top: vertical,
            left: horizontal,
            bottom: vertical,
            right: horizontal
        )
    }

    // MARK: - Original image load

    private func loadFullImage() {
        guard let imageURL else { return }
        retryButton.isHidden = true
        activityIndicator.startAnimating()
        imageView.kf.setImage(
            with: imageURL,
            options: [
                .cacheOriginalImage,
                .backgroundDecode,
                // Without this Kingfisher nils the image view the moment
                // the load starts — the inline thumbnail would vanish and
                // a failure would leave a black screen instead of the
                // "keep the thumbnail" contract.
                .keepCurrentImageWhileLoading,
                .scaleFactor(UIScreen.main.scale),
            ]
        ) { [weak self] result in
            guard let self else { return }
            activityIndicator.stopAnimating()
            switch result {
            case .success:
                retryButton.isHidden = true
                layoutImageView()
            case .failure:
                // Keep whatever is on screen (the inline thumbnail, if it
                // existed) and surface a retry in the chrome area.
                retryButton.isHidden = false
            }
        }
    }

    // MARK: - Actions

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func retryLoad() {
        loadFullImage()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: imageView)
        let targetScale = scrollView.zoomScale > 1
            ? scrollView.minimumZoomScale
            : Self.doubleTapZoomScale
        // A rect that maps to the full bounds at `targetScale`, centered on
        // the tap point, clamped to the image so the zoom keeps the tapped
        // content visible.
        let targetSize = CGSize(
            width: scrollView.bounds.width / targetScale,
            height: scrollView.bounds.height / targetScale
        )
        let imageBounds = CGRect(origin: .zero, size: imageView.bounds.size)
        var rect = CGRect(
            x: point.x - targetSize.width / 2,
            y: point.y - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        ).intersection(imageBounds)
        if rect.isNull || rect.width <= 0 || rect.height <= 0 {
            rect = imageBounds
        }
        scrollView.zoom(to: rect, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        // Only the surrounding background dismisses; the image area is kept
        // clear so double-tap aiming never dismisses by accident.
        let point = gesture.location(in: scrollView)
        let hitSlop: CGFloat = 18
        guard !imageView.frame.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point) else { return }
        close()
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageView()
    }
}
