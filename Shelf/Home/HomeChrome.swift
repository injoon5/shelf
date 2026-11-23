import UIKit

/// The one glass the Home Screen is made of: the dock, the search pill and
/// field, the edit-mode buttons. One definition, so they always match each
/// other and Springboard's.
///
/// Springboard's dock and pill let the wallpaper through with only a light
/// frost: over black they are 32 of 255 in light mode and 17 in dark, with a
/// bright hairline at the edge. `.regular` turns into a pale grey slab over a
/// dark photo (134 over black); `.clear` measures 32 with the same hairline,
/// and a black tint takes it to Springboard's 17 in dark mode.
@MainActor
enum HomeGlass {
    static func effect(_ traits: UITraitCollection, interactive: Bool = false) -> UIGlassEffect {
        let glass = UIGlassEffect(style: .clear)
        if traits.userInterfaceStyle == .dark { glass.tintColor = HomeMetrics.darkGlassTint }
        glass.isInteractive = interactive
        return glass
    }
}

/// The dock's glass. Its icons sit above it, apart (`HomeView`), so the
/// glass never has to know about them.
///
/// Its outline is set here and nowhere else (§0.6 changes it); the drop
/// target is the same frame (`HomeGeometry.dropSlot`).
final class DockView: UIVisualEffectView {
    init() {
        super.init(effect: nil)
        isUserInteractionEnabled = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (dock: DockView, _) in
            dock.effect = HomeGlass.effect(dock.traitCollection)
        }
        effect = HomeGlass.effect(traitCollection)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func place(_ geometry: HomeGeometry) {
        frame = geometry.dockFrame
        cornerConfiguration = .corners(radius: .fixed(geometry.dockRadius))
    }
}

/// The two buttons edit mode adds, where Springboard puts its own and in the
/// same glass capsules: New App on the left, Done on the right. They fade in
/// as the status bar fades out.
final class EditBar: UIView {
    let newApp = EditButton(symbol: "plus", title: String(localized: "New App"))
    let done = EditButton(symbol: "checkmark", title: String(localized: "Done"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(newApp)
        addSubview(done)
        alpha = 0
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Only the buttons take touches.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    func place(width: CGFloat) {
        let size = HomeMetrics.editButtonSize
        let top = HomeMetrics.editButtonTop
        frame = CGRect(x: 0, y: 0, width: width, height: top + size.height)
        newApp.frame = CGRect(x: HomeMetrics.editButtonInset, y: top, width: size.width, height: size.height)
        done.frame = CGRect(x: width - HomeMetrics.editButtonInset - size.width, y: top, width: size.width, height: size.height)
    }

    func setShown(_ shown: Bool, animated: Bool) {
        guard shown == isHidden || (shown ? alpha < 1 : alpha > 0) else { return }
        if shown { isHidden = false }
        let change = { self.alpha = shown ? 1 : 0 }
        guard animated else {
            change()
            isHidden = !shown
            return
        }
        Motion.editMode.animate(change) { _ in
            if self.alpha == 0 { self.isHidden = true }
        }
    }
}

/// A glass capsule with a bold white glyph, 66 × 28 pt, whose touch target
/// is a finger's height.
final class EditButton: UIButton {
    init(symbol: String, title: String) {
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.clearGlass()
        configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .default)
            .applying(UIImage.SymbolConfiguration(weight: .bold)))
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        self.configuration = configuration
        accessibilityLabel = title
        maximumContentSizeCategory = UIContentSizeCategory(HomeMetrics.textSizeCap)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (button: EditButton, _) in button.restyle() }
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The same glass as the dock's: untinted (a glass button otherwise
    /// takes the accent colour), and tinted dark in dark mode.
    private func restyle() {
        configuration?.baseBackgroundColor = traitCollection.userInterfaceStyle == .dark ? HomeMetrics.darkGlassTint : .clear
    }

    // The capsule is shorter than a finger; the target isn't.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let extra = max(HomeMetrics.minimumHit - bounds.height, 0) / 2
        return bounds.insetBy(dx: 0, dy: -extra).contains(point)
    }
}

/// A glass capsule that drops from the top when a sync fails, like a system
/// banner, and leaves on its own.
final class SyncBannerView: UIButton {
    private(set) var banner: LibraryStore.Banner?
    var onTap: (LibraryStore.Banner) -> Void = { _ in }

    init() {
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.glass()
        configuration.cornerStyle = .capsule
        configuration.imagePadding = 6
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 18)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .medium)
            return attributes
        }
        self.configuration = configuration
        maximumContentSizeCategory = UIContentSizeCategory(ShelfMetrics.textSizeCap)
        addAction(UIAction { [unowned self] _ in if let banner { onTap(banner) } }, for: .primaryActionTriggered)
        alpha = 0
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Shows `banner` dropping in from above `top`, or takes it away.
    func show(_ banner: LibraryStore.Banner?, top: CGFloat, width: CGFloat) {
        guard banner != self.banner else { return }
        let showing = banner != nil
        if let banner {
            self.banner = banner
            configuration?.title = banner == .tokenExpired ? String(localized: "Token Expired") : String(localized: "Offline")
            configuration?.image = UIImage(systemName: banner == .tokenExpired ? "key.slash" : "exclamationmark.icloud")
            let size = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            let height = max(size.height, HomeMetrics.minimumHit)
            bounds = CGRect(x: 0, y: 0, width: min(size.width, width - 32), height: height)
            center = CGPoint(x: width / 2, y: top + height / 2)
            if isHidden {
                isHidden = false
                transform = CGAffineTransform(translationX: 0, y: -(top + height))
            }
        } else {
            self.banner = nil
        }
        Motion.editMode.animate({
            self.alpha = showing ? 1 : 0
            self.transform = showing ? .identity : CGAffineTransform(translationX: 0, y: -(self.frame.maxY))
        }, completion: { _ in
            if self.banner == nil { self.isHidden = true }
        })
    }
}

/// What stands in for the grid when there are no apps: still loading, failed
/// to load, or really empty.
final class EmptyLibraryView: UIView {
    enum State: Equatable {
        case loading, failed(API.Failure), empty
    }

    private(set) var state: State?
    var onAction: (State) -> Void = { _ in }
    private let content = UIContentUnavailableView(configuration: UIContentUnavailableConfiguration.empty())
    private var spinnerTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // The wallpaper is dark in both modes; draw on it as on a dark surface.
        overrideUserInterfaceStyle = .dark
        maximumContentSizeCategory = UIContentSizeCategory(ShelfMetrics.textSizeCap)
        addSubview(content)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.frame = bounds
    }

    func show(_ state: State?) {
        guard state != self.state else { return }
        self.state = state
        spinnerTask?.cancel()
        isHidden = state == nil
        guard let state else { return }
        switch state {
        case .loading:
            // Nothing that loads shows a spinner before `spinnerDelay`.
            content.configuration = UIContentUnavailableConfiguration.empty()
            spinnerTask = Task { [weak self] in
                try? await Task.sleep(for: Motion.spinnerDelay)
                guard !Task.isCancelled, let self, self.state == .loading else { return }
                UIView.transition(with: self.content, duration: Motion.fadeDuration, options: .transitionCrossDissolve) {
                    self.content.configuration = UIContentUnavailableConfiguration.loading()
                }
            }
        case .failed(let failure):
            let expired = failure == .unauthorized
            content.configuration = configuration(
                symbol: expired ? "key" : "wifi.slash",
                text: expired ? String(localized: "Token Expired") : String(localized: "Can't Reach Server"),
                button: expired ? String(localized: "Open Settings") : String(localized: "Try Again"), state: state)
        case .empty:
            content.configuration = configuration(symbol: "square.grid.2x2", text: String(localized: "No Apps"),
                                                  button: String(localized: "New App"), state: state)
        }
    }

    private func configuration(symbol: String, text: String, button: String, state: State) -> UIContentUnavailableConfiguration {
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: symbol)
        configuration.text = text
        configuration.button = .prominentGlass()
        configuration.button.title = button
        configuration.buttonProperties.primaryAction = UIAction { [unowned self] _ in onAction(state) }
        return configuration
    }
}
