import SwiftUI
import UIKit

/// Where search results are, for the SwiftUI results the stage hosts until
/// search is rebuilt in UIKit (PLAN.md §0.3).
@MainActor
@Observable
final class ResultsLayout {
    var geometry = HomeGeometry(size: .zero, safeTop: 0, displayRadius: 0, labelHeight: 0)
    var labelSize = HomeMetrics.labelSize
    /// From the bottom of the screen to just above the search field.
    var resultsBottom: CGFloat = 0
    /// Results whose app's card stands in for them.
    var cardIcons: Set<String> = []
    /// Where each result's artwork is, in the stage's coordinates, as last
    /// laid out: what a card opened from search grows out of.
    @ObservationIgnored var frames: [String: CGRect] = [:]
}

/// The Home Screen and the apps that open over it, in UIKit, where every
/// motion can follow a finger and be caught mid-flight.
struct HomeStage: UIViewControllerRepresentable {
    var model: HomeModel
    var library: LibraryStore
    var settings: ShelfSettings

    func makeUIViewController(context: Context) -> StageController {
        StageController(model: model, library: library, settings: settings)
    }

    // The stage follows the models itself, in `updateProperties()`.
    func updateUIViewController(_ controller: StageController, context: Context) {}
}

/// The stage, back to front:
///
/// - the wallpaper, and the dim search lays over it;
/// - the Home Screen proper (`HomeView`: pages, dock, edit mode), search's
///   results and glass, and the overlay a lifted icon and its menu rise
///   into, all of which scale back while an app is open;
/// - the blur and dim an app's card is seen over;
/// - the cards, each with its live app above it.
///
/// It follows `HomeModel` in `updateProperties()`, which UIKit tracks for
/// observation: what is open, searching, editing, the page dots.
@MainActor
final class StageController: UIViewController, UIGestureRecognizerDelegate {
    private let model: HomeModel
    private let library: LibraryStore
    private let settings: ShelfSettings
    let layout = ResultsLayout()

    private var wallpaper: WallpaperView!
    private let searchDim = UIView()
    /// Everything that scales back behind an open app.
    private let home = UIView()
    private var homeView: HomeView!
    private let overlay = HomeOverlay()
    private var results: UIHostingController<ResultsLayer>!
    private var search: SearchBar!
    private let backdropDim = UIView()
    private let backdropBlur = UIVisualEffectView(effect: nil)
    private let cardsView = PassthroughView()
    private var cards: [AppCard] = []
    private var heldCard: AppCard?
    private var displayLink: CADisplayLink?
    private var openRun: HomeModel.Run?
    private var shownDots: (shown: Bool, count: Int, page: Int)?
    private lazy var launchImpact = UIImpactFeedbackGenerator(style: .light, view: view)

    private let edgePan = UIPanGestureRecognizer()
    private let stripPan = UIPanGestureRecognizer()
    private let grab = ImmediatePanGestureRecognizer()
    private let pull = UIPanGestureRecognizer()

    init(model: HomeModel, library: LibraryStore, settings: ShelfSettings) {
        self.model = model
        self.library = library
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let stage = StageView()
        stage.catches = { [unowned self] point in self.movingCard(at: point) != nil }
        view = stage
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        wallpaper = WallpaperView(settings: settings)
        view.addSubview(wallpaper)
        searchDim.backgroundColor = .black
        searchDim.alpha = 0
        searchDim.isUserInteractionEnabled = false
        view.addSubview(searchDim)

        view.addSubview(home)
        homeView = HomeView(model: model, library: library, overlay: overlay)
        home.addSubview(homeView)
        results = host(ResultsLayer(model: model, library: library, layout: layout), in: home)
        results.view.alpha = 0
        results.view.isUserInteractionEnabled = false
        search = SearchBar(fades: .init(home: homeView, results: results.view, dim: searchDim))
        search.onTapPill = { [unowned self] in
            guard canOpenSearch else { return }
            openSearch()
            model.beginSearch()
        }
        search.onQuery = { [unowned self] in model.query = $0 }
        search.onSubmit = { [unowned self] in
            // Return opens the best match.
            guard let best = library.items.matching(model.query).first else { return }
            Task { await model.open(best.id, in: library) }
        }
        search.onFieldMoved = { [unowned self] top in placeResults(aboveFieldAt: top) }
        home.addSubview(search)
        home.addSubview(overlay)

        for cover in [backdropDim, backdropBlur] {
            cover.isUserInteractionEnabled = false
            view.addSubview(cover)
        }
        backdropDim.backgroundColor = .black
        backdropDim.alpha = 0
        backdropBlur.effect = UIBlurEffect(style: .regular)
        backdropBlur.alpha = 0
        view.addSubview(cardsView)

        edgePan.addTarget(self, action: #selector(closePan(_:)))
        stripPan.addTarget(self, action: #selector(closePan(_:)))
        grab.addTarget(self, action: #selector(grabPan(_:)))
        pull.addTarget(self, action: #selector(pullPan(_:)))
        for recognizer in [edgePan, stripPan, grab, pull] as [UIGestureRecognizer] {
            recognizer.delegate = self
            view.addGestureRecognizer(recognizer)
        }

        // The search pull waits to see whether a touch on an icon is a press.
        pull.require(toFail: homeView.touch)

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (controller: StageController, _) in
            controller.view.setNeedsLayout()
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: StageController, _) in
            controller.holdAppearance()
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        holdAppearance()
        view.window?.windowScene?.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: UIWindowScene, _) in
            self?.holdAppearance()
        }
    }

    /// The appearance the person chose, which no app can change: an app's
    /// `preferredColorScheme` reaches the window and its scene from the
    /// card, but not the screen.
    private var chosenStyle: UIUserInterfaceStyle {
        view.window?.windowScene?.screen.traitCollection.userInterfaceStyle ?? traitCollection.userInterfaceStyle
    }

    /// The Home Screen keeps the chosen appearance behind any app, and so
    /// do icons everywhere: the tone is set once, on the window, so the
    /// grid, the dock, cards' faces and sheets' previews all read the same
    /// value. For now it follows the system; Icon Appearance (§0.5) will
    /// set it from Settings.
    private func holdAppearance() {
        let style = chosenStyle
        if let results, results.overrideUserInterfaceStyle != style { results.overrideUserInterfaceStyle = style }
        for layer in [wallpaper as UIView?, homeView, overlay, search, backdropBlur].compactMap({ $0 }) where layer.overrideUserInterfaceStyle != style {
            layer.overrideUserInterfaceStyle = style
        }
        let tone = IconTone(style)
        // Reading an override that was never set throws, so ask the
        // window's traits instead.
        if let window = view.window, window.traitCollection[IconToneTrait.self] != tone {
            window.traitOverrides.iconTone = tone
        }
    }

    private func host<Root: View>(_ root: Root, in container: UIView) -> UIHostingController<Root> {
        let host = UIHostingController(rootView: root)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        addChild(host)
        container.addSubview(host.view)
        host.didMove(toParent: self)
        return host
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for layer in [wallpaper!, searchDim, home, backdropDim, backdropBlur, cardsView] as [UIView] {
            layer.bounds = bounds
            layer.center = center
        }
        for layer in [homeView!, results.view!, search!, overlay] as [UIView] {
            layer.bounds = home.bounds
            layer.center = center
        }
        for card in cards where card.phase == .open {
            card.host.view.frame = bounds
        }

        let labels = labelMetrics()
        let geometry = HomeGeometry(size: bounds.size, safeTop: view.safeAreaInsets.top,
                                    displayRadius: Display.cornerRadius, labelHeight: labels.height)
        guard geometry.size.width > 0 else { return }
        if geometry != layout.geometry || labels.size != layout.labelSize {
            layout.geometry = geometry
            layout.labelSize = labels.size
            homeView.geometry = geometry
            homeView.labelFont = .systemFont(ofSize: labels.size, weight: .medium)
            search.layout(geometry)
            placeResults(aboveFieldAt: search.restingField.minY)
            shownDots = nil
            setNeedsUpdateProperties()
        }
    }

    /// The label's size and line height, as `@ScaledMetric(relativeTo:
    /// .caption2)` would give them under the Home Screen's text-size cap.
    private func labelMetrics() -> (size: CGFloat, height: CGFloat) {
        var category = traitCollection.preferredContentSizeCategory
        if category == .unspecified { category = .large }
        let traits = UITraitCollection(preferredContentSizeCategory: min(category, UIContentSizeCategory(HomeMetrics.textSizeCap)))
        let size = UIFontMetrics(forTextStyle: .caption2).scaledValue(for: HomeMetrics.labelSize, compatibleWith: traits)
        return (size, UIFont.systemFont(ofSize: size, weight: .medium).lineHeight)
    }

    // MARK: Following the model

    override func updateProperties() {
        super.updateProperties()
        if model.isSearching != search.isOpen {
            if model.isSearching {
                openSearch()
            } else {
                search.close()
            }
        }
        // An app opened from search closes back onto the Home Screen.
        if model.run != nil, model.isSearching { model.endSearch() }

        // Page dots stand in for "Search" in edit mode, and while there are
        // pages to move between and they are moving.
        let count = model.pageCount(library.layout.pages)
        let dots = (shown: model.isEditing || (model.showsPageDots && count > 1), count: count, page: model.page)
        if let shownDots, shownDots != dots {
            search.setDots(dots.shown, count: dots.count, current: dots.page, animated: true)
        } else if shownDots == nil, layout.geometry.size.width > 0 {
            search.setDots(dots.shown, count: dots.count, current: dots.page, animated: false)
        }
        if layout.geometry.size.width > 0 { shownDots = dots }

        if model.run != openRun {
            openRun = model.run
            follow(model.run)
        }
    }

    /// Search opens over a still Home Screen: no app, no edit mode, and
    /// not open already (a tap on its glass would clear what was typed).
    private var canOpenSearch: Bool { cards.isEmpty && !model.isEditing && !search.isOpen }

    private func openSearch() {
        setSearchTone()
        search.open()
    }

    private func placeResults(aboveFieldAt top: CGFloat) {
        layout.resultsBottom = view.bounds.height - top + HomeMetrics.searchResultsGap
    }

    /// The text over the field follows what is behind it there: the
    /// wallpaper, under search's dim.
    private func setSearchTone() {
        let size = view.bounds.size
        guard size.height > 0 else { return }
        let field = search.restingField
        let band = max(field.minY / size.height, 0)...min(field.maxY / size.height, 1)
        search.setTone(Wallpaper.tone(settings, screen: size, band: band, dim: HomeMetrics.searchDim))
    }

    private func follow(_ run: HomeModel.Run?) {
        let active = cards.last { $0.phase == .opening || $0.phase == .open }
        if let run {
            if active?.slug == run.id || heldCard?.slug == run.id { return }
            if let returning = cards.last(where: { $0.slug == run.id && $0.phase == .closing }) {
                returning.open()
                startTicking()
            } else {
                present(run)
            }
        } else if let active {
            close(active)
        }
    }

    // MARK: Cards

    private var iconSize: CGFloat { layout.geometry.iconSize }

    private func present(_ run: HomeModel.Run) {
        let bounds = view.bounds
        let icon = iconFrame(run.id, preferResult: search.isOpen)
        let source = CardMotion.landing(icon: icon, screenWidth: bounds.width,
                                        pill: layout.geometry.pillFrame, iconSize: iconSize).frame
        let card = AppCard(run: run, data: library.data, face: IconFace(run.app.meta), screen: bounds.size, iconSize: iconSize,
                           fullRadius: Display.cornerRadius, from: source)
        launchImpact.impactOccurred(at: CGPoint(x: source.midX, y: source.midY))
        addChild(card.host)
        cardsView.addSubview(card.face)
        card.host.view.frame = bounds
        cardsView.addSubview(card.host.view)
        card.host.didMove(toParent: self)
        cards.append(card)
        card.open()
        setCardIcons()
        startTicking()
    }

    private func close(_ card: AppCard, centerVelocity: CGPoint = .zero, widthVelocity: CGFloat = 0) {
        // An app deleted while its card was up has no icon to land on.
        let icon = library.app(card.slug) == nil ? nil : iconFrame(card.slug, preferResult: false)
        let landing = CardMotion.landing(icon: icon, screenWidth: view.bounds.width,
                                         pill: layout.geometry.pillFrame, iconSize: iconSize)
        card.close(to: landing.frame, fades: landing.fades, centerVelocity: centerVelocity, widthVelocity: widthVelocity)
        startTicking()
    }

    /// Where `slug`'s icon is: the search result's while searching, else
    /// where the layout puts it on the Home Screen, exactly, an icon on
    /// another page a whole page's width off to that side.
    private func iconFrame(_ slug: String, preferResult: Bool) -> CGRect? {
        if preferResult, let result = layout.frames[slug] { return result }
        return homeView.iconFrame(for: slug).map { homeView.convert($0, to: view) }
    }

    /// The icons a card stands in for show no artwork. A landed card and
    /// its icon trade places in one frame: the icon is drawn, and the card
    /// goes, in the same transaction.
    private func setCardIcons() {
        let slugs = Set(cards.filter { $0.phase != .landed }.map(\.slug))
        homeView.cardIcons = slugs
        if layout.cardIcons != slugs { layout.cardIcons = slugs }
    }

    private func land(_ card: AppCard) {
        remove(card)
    }

    private func remove(_ card: AppCard) {
        card.host.willMove(toParent: nil)
        card.host.view.removeFromSuperview()
        card.host.removeFromParent()
        card.face.removeFromSuperview()
        cards.removeAll { $0 === card }
        setCardIcons()
        if cards.isEmpty { setBackdrop(0) }
        coverChanged()
    }

    /// While an app is open, VoiceOver stays in it: the Home Screen behind
    /// is out of sight, so it is out of reach too.
    private func coverChanged() {
        let covered = cards.contains { $0.phase == .open }
        for layer in [wallpaper!, home] where layer.accessibilityElementsHidden != covered {
            layer.accessibilityElementsHidden = covered
        }
    }

    /// The topmost card that is open and at rest.
    private var openCard: AppCard? {
        guard let card = cards.last, card.phase == .open else { return nil }
        return card
    }

    /// The card in flight under `point`, if any. Its model frame is already
    /// its target, so this asks where it is on screen.
    private func movingCard(at point: CGPoint) -> AppCard? {
        cards.last { card in
            (card.phase == .opening || card.phase == .closing || card.phase == .held)
                && card.face.shownFrame.contains(point)
        }
    }

    // MARK: Every frame

    private func startTicking() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = Motion.frameRate
        link.add(to: .main, forMode: .common)
        displayLink = link
        tick()
    }

    /// Whatever can't be a Core Animation spring of its own follows the
    /// cards' springs here, read from their presentation each frame: the
    /// Home Screen's scale, blur and dim, and each card's picture fading
    /// into its icon.
    @objc private func tick() {
        var openness: CGFloat = 0
        for card in cards {
            card.tick()
            if card.phase != .landed { openness = max(openness, card.progress) }
            if card.phase != .held, card.hasComeToRest(), card.settle() {
                land(card)
            }
        }
        setBackdrop(openness)
        coverChanged()
        if cards.allSatisfy({ $0.phase == .open }) {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func setBackdrop(_ openness: CGFloat) {
        let scale = 1 - (1 - RunnerMetrics.backdropScale) * openness
        home.transform = CGAffineTransform(scaleX: scale, y: scale)
        backdropDim.alpha = openness * RunnerMetrics.backdropDim
        backdropBlur.alpha = openness * RunnerMetrics.backdropBlur
    }

    // MARK: Gestures

    /// Up from the bottom edge, or down from the status bar: the open app
    /// follows the finger, and closes or goes back on release.
    @objc private func closePan(_ recognizer: UIPanGestureRecognizer) {
        let direction: CloseDirection = recognizer === stripPan ? .down : .up
        switch recognizer.state {
        case .began:
            guard let card = openCard else { return }
            heldCard = card
            let start = recognizer.location(in: view) - recognizer.translation(in: view)
            card.hold(finger: start, direction: direction)
            card.move(recognizer.translation(in: view))
            startTicking()
        case .changed:
            heldCard?.move(recognizer.translation(in: view))
        case .ended, .cancelled, .failed:
            release(velocity: recognizer.state == .ended ? recognizer.velocity(in: view) : .zero)
        default:
            break
        }
    }

    /// A finger on a card in flight catches it where it is. Let go without
    /// moving, it opens; moved, it goes where it was thrown.
    @objc private func grabPan(_ recognizer: ImmediatePanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            let point = recognizer.location(in: view)
            guard let card = movingCard(at: point) else { return }
            heldCard = card
            card.hold(finger: point, direction: .up)
            startTicking()
        case .changed:
            heldCard?.move(recognizer.translation(in: view))
        case .ended:
            let moved = recognizer.translation(in: view)
            if hypot(moved.x, moved.y) < RunnerMetrics.tapSlop, let card = heldCard {
                heldCard = nil
                _ = card.release(velocity: .zero)
                reopen(card, centerVelocity: .zero, widthVelocity: 0)
            } else {
                release(velocity: recognizer.velocity(in: view))
            }
        case .cancelled, .failed:
            release(velocity: .zero)
        default:
            break
        }
    }

    private func release(velocity: CGPoint) {
        guard let card = heldCard else { return }
        heldCard = nil
        let release = card.release(velocity: velocity)
        if release.closes {
            close(card, centerVelocity: release.centerVelocity, widthVelocity: release.widthVelocity)
            if model.run?.id == card.slug { model.close() }
        } else {
            reopen(card, centerVelocity: release.centerVelocity, widthVelocity: release.widthVelocity)
        }
    }

    /// Back to full screen, unless the model says the card must land: its
    /// app is gone, or another has opened since.
    private func reopen(_ card: AppCard, centerVelocity: CGPoint, widthVelocity: CGFloat) {
        guard model.reopen(card.run, in: library) else {
            close(card, centerVelocity: centerVelocity, widthVelocity: widthVelocity)
            return
        }
        openRun = model.run
        card.reopen(centerVelocity: centerVelocity, widthVelocity: widthVelocity)
        setCardIcons()
        startTicking()
    }

    /// Down on the Home Screen: the pill stretches toward the field.
    @objc private func pullPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            search.beginPull()
        case .changed:
            search.pull(recognizer.translation(in: view).y)
        case .ended, .cancelled, .failed:
            let velocity = recognizer.state == .ended ? recognizer.velocity(in: view).y : 0
            setSearchTone()
            if search.endPull(velocity: velocity) { model.beginSearch() }
        default:
            break
        }
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: view)
        switch recognizer {
        case edgePan:
            // The home indicator's strip, where the system's own swipe home starts.
            return openCard != nil && point.y > view.bounds.height - max(view.safeAreaInsets.bottom, RunnerMetrics.homeEdge)
        case stripPan:
            return openCard != nil && point.y < max(view.safeAreaInsets.top, RunnerMetrics.dismissStrip)
        case grab:
            return movingCard(at: point) != nil
        case pull:
            return canOpenSearch
        default:
            return true
        }
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        switch recognizer {
        case stripPan, pull:
            let velocity = (recognizer as! UIPanGestureRecognizer).velocity(in: view)
            return velocity.y > abs(velocity.x)
        case edgePan:
            let velocity = edgePan.velocity(in: view)
            return -velocity.y > abs(velocity.x)
        default:
            return true
        }
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        switch recognizer {
        case edgePan, stripPan:
            // The app's own drags wait to see whether this is a close.
            return other.view?.isDescendant(of: cardsView) == true
        case pull:
            // The pages wait to see whether this is a pull down; it decides
            // as soon as the finger has moved, so they lose nothing.
            guard let scroll = other.view as? UIScrollView else { return false }
            return other === scroll.panGestureRecognizer
        default:
            return false
        }
    }
}

/// The stage's root view. A card in flight is never where its model frame
/// says (that is its target), so touches inside one are caught here, by
/// where it is on screen, for the stage's own recognizers.
final class StageView: UIView {
    var catches: (CGPoint) -> Bool = { _ in false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if catches(point) { return self }
        return super.hitTest(point, with: event)
    }
}

/// A view that holds others but takes no touches of its own.
final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

private extension CGPoint {
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}
