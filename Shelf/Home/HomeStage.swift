import SwiftUI
import UIKit

/// What the SwiftUI side of the Home Screen hands the stage each update.
struct StageInput: Equatable {
    var run: HomeModel.Run?
    var isSearching = false
    var isEditing = false
    var showsPageDots = false
    var pageCount = 1
    var page = 0

    /// Page dots stand in for "Search" in edit mode, and while there are
    /// pages to move between and they are moving.
    var showsDots: Bool { isEditing || (showsPageDots && pageCount > 1) }
}

/// Where the stage has put things, for the SwiftUI views it hosts.
@MainActor
@Observable
final class StageLayout {
    /// The coordinate space icons report their frames in: the stage's own.
    nonisolated static let space = "stage"

    var geometry = HomeGeometry(size: .zero, safeTop: 0, displayRadius: 0, labelHeight: 0)
    var labelSize = HomeMetrics.labelSize
    /// From the bottom of the screen to just above the search field.
    var resultsBottom: CGFloat = 0
    /// Icons whose artwork is hidden because their app's card stands in for
    /// them: open, or in flight. Their labels stay, as on Springboard.
    var cardIcons: Set<String> = []
    /// Where each icon's artwork is, in the stage's coordinates, as last laid
    /// out: what a card grows out of and lands on.
    @ObservationIgnored var iconFrames: [IconKey: CGRect] = [:]

    /// Where a card should grow out of or land on for `slug`: the search
    /// result while searching, otherwise its dock or grid icon.
    func iconFrame(_ slug: String, preferResult: Bool) -> CGRect? {
        if preferResult, let frame = iconFrames[IconKey(slug: slug, place: .result)] { return frame }
        return iconFrames[IconKey(slug: slug, place: .dock)] ?? iconFrames[IconKey(slug: slug, place: .grid)]
    }
}

/// The Home Screen and the apps that open over it, in UIKit, where every
/// motion can follow a finger and be caught mid-flight.
struct HomeStage: UIViewControllerRepresentable {
    var model: HomeModel
    var library: LibraryStore
    var settings: ShelfSettings
    var input: StageInput

    func makeUIViewController(context: Context) -> StageController {
        StageController(model: model, library: library, settings: settings)
    }

    func updateUIViewController(_ controller: StageController, context: Context) {
        controller.apply(input)
    }
}

/// The stage, back to front:
///
/// - the wallpaper, and the dim search lays over it;
/// - the Home Screen proper (grid, dock, search results, the search glass),
///   which scales back while an app is open;
/// - the blur and dim an app's card is seen over;
/// - the cards, each with its live app above it.
///
/// The SwiftUI layers ignore the safe area: the stage gives them the
/// geometry, so scaling them never makes them lay out again.
@MainActor
final class StageController: UIViewController, UIGestureRecognizerDelegate {
    private let model: HomeModel
    private let library: LibraryStore
    private let settings: ShelfSettings
    let layout = StageLayout()

    private var wallpaper: UIHostingController<WallpaperLayer>!
    private let searchDim = UIView()
    /// Everything that scales back behind an open app.
    private let home = UIView()
    private var icons: UIHostingController<IconsLayer>!
    private var results: UIHostingController<ResultsLayer>!
    private var search: SearchBar!
    private let backdropDim = UIView()
    private let backdropBlur = UIVisualEffectView(effect: nil)
    private let cardsView = PassthroughView()
    private var cards: [AppCard] = []
    private var heldCard: AppCard?
    private var displayLink: CADisplayLink?
    private var input = StageInput()

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
        let environment = StageEnvironment(model: model, library: library, settings: settings, layout: layout)

        wallpaper = host(WallpaperLayer(stage: environment), in: view)
        searchDim.backgroundColor = .black
        searchDim.alpha = 0
        searchDim.isUserInteractionEnabled = false
        view.addSubview(searchDim)

        view.addSubview(home)
        icons = host(IconsLayer(stage: environment), in: home)
        results = host(ResultsLayer(stage: environment), in: home)
        results.view.alpha = 0
        results.view.isUserInteractionEnabled = false
        search = SearchBar(fades: .init(home: icons.view, results: results.view, dim: searchDim))
        search.onTapPill = { [unowned self] in
            guard canOpenSearch else { return }
            openSearch()
            model.beginSearch()
        }
        search.onQuery = { [unowned self] in model.query = $0 }
        search.onSubmit = { [unowned self] in
            // Return opens the best match.
            guard let best = library.apps.matching(model.query).first else { return }
            Task { await model.open(best.slug, in: library) }
        }
        search.onFieldMoved = { [unowned self] top in placeResults(aboveFieldAt: top) }
        home.addSubview(search)

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

    /// The Home Screen keeps the chosen appearance behind any app.
    private func holdAppearance() {
        let style = chosenStyle
        for layer in [wallpaper as UIViewController?, icons, results].compactMap({ $0 }) where layer.overrideUserInterfaceStyle != style {
            layer.overrideUserInterfaceStyle = style
        }
        for layer in [search as UIView?, backdropBlur].compactMap({ $0 }) where layer.overrideUserInterfaceStyle != style {
            layer.overrideUserInterfaceStyle = style
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
        for layer in [wallpaper.view!, searchDim, home, backdropDim, backdropBlur, cardsView] {
            layer.bounds = bounds
            layer.center = center
        }
        for layer in [icons.view!, results.view!, search!] as [UIView] {
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
            search.layout(geometry)
            placeResults(aboveFieldAt: search.restingField.minY)
            search.setDots(input.showsDots, count: input.pageCount, current: input.page, animated: false)
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

    func apply(_ new: StageInput) {
        let old = input
        input = new
        if new.isSearching != search.isOpen {
            if new.isSearching {
                openSearch()
            } else {
                search.close()
            }
        }
        if new.isEditing != old.isEditing || new.showsPageDots != old.showsPageDots
            || new.pageCount != old.pageCount || new.page != old.page {
            search.setDots(new.showsDots, count: new.pageCount, current: new.page, animated: true)
        }
        if new.run != old.run { follow(new.run) }
    }

    /// Search opens over a still Home Screen: no app, no edit mode, and
    /// not open already (a tap on its glass would clear what was typed).
    private var canOpenSearch: Bool { cards.isEmpty && !input.isEditing && !search.isOpen }

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
        let icon = layout.iconFrame(run.id, preferResult: input.isSearching || search.isOpen)
        let source = CardMotion.landing(icon: icon, screenWidth: bounds.width,
                                        pill: layout.geometry.pillFrame, iconSize: iconSize).frame
        let face = CardFace(IconFace(run.app.meta), style: settings.iconStyle,
                            dark: chosenStyle == .dark, iconSize: iconSize)
        let card = AppCard(run: run, data: library.data, face: face, screen: bounds.size, iconSize: iconSize,
                           fullRadius: Display.cornerRadius, from: source)
        addChild(card.host)
        cardsView.addSubview(card.face)
        card.host.view.frame = bounds
        cardsView.addSubview(card.host.view)
        card.host.didMove(toParent: self)
        cards.append(card)
        card.open()
        // Not during this view update: on the next turn of the run loop.
        Task { @MainActor in self.layout.cardIcons.insert(run.id) }
        startTicking()
    }

    private func close(_ card: AppCard, centerVelocity: CGPoint = .zero, widthVelocity: CGFloat = 0) {
        let icon = layout.iconFrame(card.slug, preferResult: false)
        let landing = CardMotion.landing(icon: icon, screenWidth: view.bounds.width,
                                         pill: layout.geometry.pillFrame, iconSize: iconSize)
        card.close(to: landing.frame, fades: landing.fades, centerVelocity: centerVelocity, widthVelocity: widthVelocity)
        startTicking()
    }

    private func land(_ card: AppCard) {
        layout.cardIcons.remove(card.slug)
        // The icon is drawn beneath the card on SwiftUI's next pass; the card
        // stays a moment longer so there is never a frame with neither.
        Task { @MainActor in
            try? await Task.sleep(for: Motion.cardHandoff)
            guard card.phase == .landed else { return }
            self.remove(card)
        }
    }

    private func remove(_ card: AppCard) {
        card.host.willMove(toParent: nil)
        card.host.view.removeFromSuperview()
        card.host.removeFromParent()
        card.face.removeFromSuperview()
        cards.removeAll { $0 === card }
        if cards.isEmpty { setBackdrop(0) }
        coverChanged()
    }

    /// While an app is open, VoiceOver stays in it: the Home Screen behind
    /// is out of sight, so it is out of reach too.
    private func coverChanged() {
        let covered = cards.contains { $0.phase == .open }
        for layer in [wallpaper.view!, home] where layer.accessibilityElementsHidden != covered {
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

    private func reopen(_ card: AppCard, centerVelocity: CGPoint, widthVelocity: CGFloat) {
        card.reopen(centerVelocity: centerVelocity, widthVelocity: widthVelocity)
        if model.run?.id != card.slug { model.reopen(card.run) }
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
