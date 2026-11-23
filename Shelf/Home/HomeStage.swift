import SwiftUI
import UIKit

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
/// - the wallpaper;
/// - the Home Screen proper (`HomeView`: pages, dock, edit mode); search's
///   backdrop (the Home Screen blurred and darkened), its list and its
///   glass; and the overlay a lifted icon and its menu rise into, all of
///   which scale back while an app is open;
/// - the blur and dim an app's card is seen over: a backdrop of its own,
///   blurring the wallpaper and the Home Screen as one picture;
/// - the cards, each with its live app above it.
///
/// It follows `HomeModel` in `updateProperties()`, which UIKit tracks for
/// observation: what is open, searching, editing, the page dots.
@MainActor
final class StageController: UIViewController, UIGestureRecognizerDelegate {
    private let model: HomeModel
    private let library: LibraryStore
    private let settings: ShelfSettings
    private(set) var geometry = HomeGeometry(size: .zero, safeTop: 0, labelHeight: 0)
    private var labelSize = HomeMetrics.labelSize

    private var wallpaper: WallpaperView!
    /// Everything that scales back behind an open app.
    private let home = UIView()
    private var homeView: HomeView!
    private let overlay = HomeOverlay()
    private let backdrop = BackdropView()
    private var list: SearchList!
    private let search = SearchBar()
    /// How dark search's backdrop gets: App Library's, or darker over a
    /// bright wallpaper (`searchBackdrop()`).
    private var backdropColors = (scale: SearchMetrics.backdropScale, offset: SearchMetrics.backdropOffsetDark)
    /// The Home Screen behind an app's card, blurred and darkened by how
    /// open the card is. At half resolution: its blur goes down to a point
    /// or two as the card lands, which a quarter-size copy would smear.
    private let cardBackdrop = BackdropView(resolution: 0.5)
    private let cardsView = PassthroughView()
    private var cards: [AppCard] = []
    /// Each app's last snapshot, which its card opens on (plan §0.8).
    private lazy var snapshots = LaunchSnapshotStore(files: library.snapshots)
    private var heldCard: AppCard?
    private var displayLink: CADisplayLink?
    private var openRun: HomeModel.Run?
    private var shownDots: (shown: Bool, count: Int, page: Int)?
    private var warmedUp = false
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

        view.addSubview(home)
        homeView = HomeView(model: model, library: library, overlay: overlay)
        homeView.onPressApp = { [unowned self] slug in
            LaunchTiming.mark("press", slug)
            prefetchSnapshot(slug)
            prebuild(slug)
        }
        home.addSubview(homeView)
        home.addSubview(backdrop)
        list = SearchList(model: model, library: library)
        list.alpha = 0
        list.isHidden = true
        list.isUserInteractionEnabled = false
        list.onOpen = { [unowned self] id in
            // The keyboard goes on the tap, before any download, as App Library's does.
            search.dismissKeyboard()
            Task { await model.open(id, in: library) }
        }
        list.onClose = { [unowned self] velocity in
            // Pulled down: the warp goes back with the finger's speed.
            search.close(velocity: -velocity / SearchMetrics.pullDistance)
            model.endSearch()
        }
        home.addSubview(list)
        search.onTapPill = { [unowned self] in
            guard canOpenSearch else { return }
            openSearch()
            model.beginSearch()
        }
        search.onQuery = { [unowned self] in model.query = $0 }
        search.onSubmit = { [unowned self] in
            // Return opens the best match.
            guard let best = SearchSections.topMatch(library.items, query: model.query) else { return }
            search.dismissKeyboard()
            Task { await model.open(best.id, in: library) }
        }
        search.onClose = { [unowned self] in model.endSearch() }
        search.onProgress = { [unowned self] p in followWarp(p) }
        search.onOpenChanged = { [unowned self] open in
            homeView.isUserInteractionEnabled = !open
            list.isUserInteractionEnabled = open
        }
        search.onFieldMoved = { [unowned self] top in list.fieldTop = top }
        home.addSubview(search)
        home.addSubview(overlay)
        // Rows going under the field fade softly, as App Library's do under its own.
        let edge = UIScrollEdgeElementContainerInteraction()
        edge.scrollView = list.collectionView
        edge.edge = .bottom
        search.edgeContainer.addInteraction(edge)

        view.addSubview(cardBackdrop)
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
        if !warmedUp {
            warmedUp = true
            // Kiln's registry and engine, set up once, after the first frames
            // and long before a finger can open anything: the first app
            // opened then builds as fast as the rest.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Prebuilds.warmUp() }
        }
        #if DEBUG
        if let held = Demo.searchProgress {
            // As a finger holding a pull there would.
            DispatchQueue.main.async { [self] in
                prepareSearch()
                search.beginPull()
                search.pull(held * SearchMetrics.pullDistance)
            }
        }
        #endif
        view.window?.windowScene?.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: UIWindowScene, _) in
            self?.holdAppearance()
            // The screen's traits, which `chosenStyle` reads, change after
            // the scene's: read alone, now, they left the icons a switch
            // behind (dark with the system light, and the other way round).
            DispatchQueue.main.async { self?.holdAppearance() }
        }
    }

    /// The appearance the person chose, which no app can change: an app's
    /// `preferredColorScheme` reaches the window and its scene from the
    /// card, but not the screen.
    private var chosenStyle: UIUserInterfaceStyle {
        view.window?.windowScene?.screen.traitCollection.userInterfaceStyle ?? traitCollection.userInterfaceStyle
    }

    /// The Home Screen keeps the chosen appearance behind any app, and so
    /// do icons everywhere. The icon tone is Icon Appearance resolved
    /// against that appearance, here and nowhere else, and set once, on the
    /// window, so the grid, the dock, search's rows, the lifted and carried
    /// icon, cards' faces and sheets' previews all read the same value.
    /// Labels, the glass and the wallpaper follow the appearance itself.
    private func holdAppearance() {
        let style = chosenStyle
        for layer in [wallpaper as UIView?, homeView, overlay, list, search].compactMap({ $0 }) where layer.overrideUserInterfaceStyle != style {
            layer.overrideUserInterfaceStyle = style
        }
        let tone = settings.iconAppearance.tone(system: style)
        // Reading an override that was never set throws, so ask the
        // window's traits instead.
        if let window = view.window, window.traitCollection[IconToneTrait.self] != tone {
            window.traitOverrides.iconTone = tone
        }
        if model.iconTone != tone { model.iconTone = tone }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for layer in [wallpaper!, home, cardBackdrop, cardsView] as [UIView] {
            layer.bounds = bounds
            layer.center = center
        }
        for layer in [homeView!, backdrop, list!, search, overlay] as [UIView] {
            layer.bounds = home.bounds
            layer.center = center
        }
        for card in cards where card.phase == .open {
            card.host.view.frame = bounds
        }

        let labels = labelMetrics()
        let geometry = HomeGeometry(size: bounds.size, safeTop: view.safeAreaInsets.top, labelHeight: labels.height)
        guard geometry.size.width > 0 else { return }
        if geometry != self.geometry || labels.size != labelSize {
            self.geometry = geometry
            labelSize = labels.size
            homeView.geometry = geometry
            homeView.labelFont = .systemFont(ofSize: labels.size, weight: .medium)
            search.layout(geometry)
            list.top = geometry.safeTop + SearchMetrics.listTop
            list.fieldTop = search.restingField.minY
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
        // It reads Icon Appearance, so the icons follow a change in Settings.
        holdAppearance()
        if model.isSearching != search.isOpen {
            if model.isSearching {
                openSearch()
            } else {
                search.close()
            }
        }
        // Page dots stand in for "Search" in edit mode, and while there are
        // pages to move between and they are moving.
        let count = model.pageCount(library.layout.pages)
        let dots = (shown: model.isEditing || (model.showsPageDots && count > 1), count: count, page: model.page)
        if let shownDots, shownDots != dots {
            search.setDots(dots.shown, count: dots.count, current: dots.page, animated: true)
        } else if shownDots == nil, geometry.size.width > 0 {
            search.setDots(dots.shown, count: dots.count, current: dots.page, animated: false)
        }
        if geometry.size.width > 0 { shownDots = dots }

        if model.run != openRun {
            openRun = model.run
            follow(model.run)
        }
    }

    /// Search opens over a still Home Screen: no app, no edit mode, and
    /// not open already (a tap on its glass would clear what was typed).
    private var canOpenSearch: Bool { cards.isEmpty && !model.isEditing && !search.isOpen }

    private func openSearch() {
        prepareSearch()
        search.open()
    }

    /// Before the warp starts from the pill: the list at its top, and the
    /// backdrop's darkness for this wallpaper.
    private func prepareSearch() {
        guard search.progress <= 0.001 else { return }
        list.scrollToTop()
        backdropColors = searchBackdrop()
    }

    /// App Library's backdrop is 0.85 of the blurred Home Screen, less a
    /// little; white names read on it over most wallpapers. Over a bright
    /// one that would still be light, so it darkens more there, to
    /// `backdropCeiling` on average.
    private func searchBackdrop() -> (scale: CGFloat, offset: CGFloat) {
        let offset = traitCollection.userInterfaceStyle == .dark ? SearchMetrics.backdropOffsetDark : SearchMetrics.backdropOffsetLight
        let brightness = Wallpaper.brightness(settings, screen: view.bounds.size, dark: traitCollection.userInterfaceStyle == .dark)
        let scale = brightness > 0 ? min(SearchMetrics.backdropScale, (SearchMetrics.backdropCeiling - offset) / brightness) : SearchMetrics.backdropScale
        return (max(scale, 0), offset)
    }

    /// What the stage moves with the warp, at progress `p`: the grid and
    /// the dock blur (under the backdrop) and fade over the first part, the
    /// backdrop blurs and darkens, and the list fades in and rises over the
    /// last part. Nothing is ever in two places: the grid is gone before the
    /// list arrives.
    private func followWarp(_ p: CGFloat) {
        let p = min(max(p, 0), 1)
        homeView.alpha = 1 - SearchMetrics.homeFade.ramp(p)
        let b = SearchMetrics.backdropRamp.ramp(p)
        backdrop.set(radius: SearchMetrics.blurSigma * b, scale: 1 - (1 - backdropColors.scale) * b, offset: backdropColors.offset * b)
        let shown = SearchMetrics.listFade.ramp(p)
        list.alpha = shown
        list.isHidden = shown <= 0
        list.transform = CGAffineTransform(translationX: 0, y: SearchMetrics.listRise * (1 - shown))
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

    private var iconSize: CGFloat { geometry.iconSize }

    private func present(_ run: HomeModel.Run) {
        LaunchTiming.mark("present", run.id)
        let bounds = view.bounds
        // From search, the card grows out of the row's icon, and the
        // keyboard goes; search stays under the card until it comes back.
        let row = model.isSearching ? list.iconFrame(for: run.id, in: home) : nil
        if model.isSearching { search.dismissKeyboard() }
        let icon = row ?? iconFrame(run.id)
        let size = row == nil ? iconSize : SearchMetrics.iconSize
        let source = CardMotion.landing(icon: icon, screenWidth: bounds.width,
                                        pill: geometry.pillFrame, iconSize: size).frame
        let key = snapshotKey(run.source)
        let cached = snapshots.cached(run.id, key)
        let card = AppCard(run: run, runHost: library.host, permissions: library.permissions.forApp(run.app.meta),
                           face: IconFace(run.app.meta),
                           surface: cached.map(Self.snapshotView) ?? launchSurface(run.source), screen: bounds.size,
                           iconSize: size, fullRadius: Display.cornerRadius, from: source)
        card.keepsPicture = { [unowned self, slug = run.id, source = run.source] picture in
            // Under the appearance and text size it was taken in.
            snapshots.save(picture, for: slug, snapshotKey(source))
        }
        if cached == nil {
            // Off the main thread: usually here while the icon still covers
            // the surface.
            let scale = traitCollection.displayScale
            Task { [weak card, snapshots] in
                guard let picture = await snapshots.load(run.id, key, scale: scale) else { return }
                card?.showSnapshot(picture)
            }
        }
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

    /// Reads `slug`'s launch snapshot into memory while a finger is down on
    /// its icon, so a tap opens on it from the card's first frame. Read on
    /// the tap instead, it arrived a few frames into the growth on a cold
    /// open, after the plain surface had already shown.
    private func prefetchSnapshot(_ slug: String) {
        guard cards.isEmpty, let source = library.source(for: slug) else { return }
        let key = snapshotKey(source)
        guard snapshots.cached(slug, key) == nil else { return }
        let scale = traitCollection.displayScale
        Task { [snapshots] in _ = await snapshots.load(slug, key, scale: scale) }
    }

    /// Starts building `slug` while a finger is down on its icon (plan §0.8
    /// item 5): its source is parsed off the main thread, and its data's
    /// pull from the server begins, so both are usually done by the time
    /// the card comes to rest.
    private func prebuild(_ slug: String) {
        guard cards.isEmpty, let source = library.source(for: slug) else { return }
        Prebuilds.shared.prepare(slug, source: source)
        let data = library.data
        Task { await data.prefetch(slug) }
    }

    /// What a snapshot of an app with `source` must match to be shown now:
    /// the appearance the person chose (not one an app forced) and the
    /// text size.
    private func snapshotKey(_ source: String) -> LaunchSnapshots.Key {
        let traits = traitCollection.modifyingTraits { $0.userInterfaceStyle = chosenStyle }
        return LaunchSnapshots.Key(source: source, traits: traits)
    }

    /// The surface an app opens on with no snapshot: shaped like its first
    /// screen, in the chosen appearance unless the app forces one.
    private func launchSurface(_ source: String) -> UIView {
        let layout = LaunchLayout(source: source)
        let surface = LaunchSurfaceView(layout: layout, top: view.safeAreaInsets.top)
        if layout.dark == nil { surface.overrideUserInterfaceStyle = chosenStyle }
        return surface
    }

    private static func snapshotView(_ picture: UIImage) -> UIView {
        let view = UIImageView(image: picture)
        view.contentMode = .scaleToFill
        return view
    }

    private func close(_ card: AppCard, velocity: CardVelocity? = nil) {
        let landing = landing(for: card.slug)
        card.close(to: landing.frame, fades: landing.fades, velocity: velocity)
        startTicking()
    }

    /// Where a card for `slug` lands: on its icon (its row, opened from
    /// search), past the side of the screen its page is on, or in the pill
    /// when it has no icon (an app deleted while its card was up). Asked
    /// every frame of the landing, so the card follows its icon if the
    /// pages turn under it.
    func landing(for slug: String) -> (frame: CGRect, fades: Bool) {
        let row = model.isSearching ? list.iconFrame(for: slug, in: home) : nil
        let icon = library.app(slug) == nil ? nil : row ?? iconFrame(slug)
        return CardMotion.landing(icon: icon, screenWidth: view.bounds.width,
                                  pill: geometry.pillFrame, iconSize: row == nil ? iconSize : SearchMetrics.iconSize)
    }

    /// Where `slug`'s icon is on the Home Screen, exactly as the layout puts
    /// it, an icon on another page a whole page's width off to that side.
    ///
    /// Icon frames are taken in `home`'s own space, which is the screen's
    /// once it is at full size: a card lands where the icon will be when the
    /// Home Screen has grown back from behind it, not where its scaled-down
    /// picture is as the close begins.
    private func iconFrame(_ slug: String) -> CGRect? {
        homeView.iconFrame(for: slug).map { homeView.convert($0, to: home) }
    }

    /// The icons a card stands in for show no artwork. A landed card and
    /// its icon trade places in one frame: the icon is drawn, and the card
    /// goes, in the same transaction.
    private func setCardIcons() {
        let slugs = Set(cards.filter { $0.phase != .landed }.map(\.slug))
        homeView.cardIcons = slugs
        list.cardIcons = slugs
    }

    private func land(_ card: AppCard) {
        remove(card)
    }

    private func remove(_ card: AppCard) {
        // The card has landed: the app stops (plan §1.7, §7).
        card.tearDown()
        card.host.willMove(toParent: nil)
        card.host.view.removeFromSuperview()
        card.host.removeFromParent()
        card.face.removeFromSuperview()
        cards.removeAll { $0 === card }
        setCardIcons()
        if cards.isEmpty {
            setBackdrop(0)
            // Opening an app closes search: once its card is back in its
            // row, search warps home too.
            if model.isSearching, model.run == nil { model.endSearch() }
        }
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

    /// The card in flight under `point`, if any, by where it is on screen.
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

    /// The cards' flights, placed for the frame about to be shown, and
    /// whatever follows them: the Home Screen's scale, blur and dim, and
    /// each card's picture fading into its icon. A closing card heads for
    /// wherever its icon is this frame, so the pages can be turned under it.
    @objc private func tick() {
        // One transaction for the whole frame: a card's outline, its
        // picture and its fade, and the Home Screen behind, all reach the
        // screen together. Committed separately, the outline showed a frame
        // behind the picture, a rim of tile around a shrinking app.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let time = displayLink?.targetTimestamp ?? CACurrentMediaTime()
        var openness: CGFloat = 0
        var look: CardLook?
        for card in cards {
            if card.phase == .closing {
                let landing = landing(for: card.slug)
                card.follow(landing: landing.frame, fades: landing.fades)
            }
            let arrived = card.phase != .held && card.step(at: time)
            card.tick()
            if card.phase != .landed, card.progress >= openness {
                openness = card.progress
                look = card.look
            }
            if arrived, card.settle() {
                land(card)
            }
        }
        setBackdrop(openness, look: look)
        coverChanged()
        if cards.allSatisfy({ $0.phase == .open }) {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    /// The Home Screen behind the card that is most open, at `openness`,
    /// blurred and dimmed by that card's `look`: a real radius and a dim
    /// that come in late as it grows and go late as it lands, as
    /// Springboard's. With no card, itself.
    func setBackdrop(_ openness: CGFloat, look: CardLook? = nil) {
        let scale = 1 - (1 - RunnerMetrics.backdropScale) * openness
        home.transform = CGAffineTransform(scaleX: scale, y: scale)
        let look = look ?? CardMotion.look(progress: openness, opening: false)
        cardBackdrop.set(radius: look.blur, scale: 1 - look.dim, offset: 0)
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
                reopen(card, velocity: .zero)
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
            close(card, velocity: release.velocity)
            if model.run?.id == card.slug { model.close() }
        } else {
            reopen(card, velocity: release.velocity)
        }
    }

    /// Back to full screen, unless the model says the card must land: its
    /// app is gone, or another has opened since.
    private func reopen(_ card: AppCard, velocity: CardVelocity) {
        guard model.reopen(card.run, in: library) else {
            close(card, velocity: velocity)
            return
        }
        openRun = model.run
        card.reopen(velocity: velocity)
        setCardIcons()
        startTicking()
    }

    /// Down on the Home Screen: the pill stretches toward the field.
    @objc private func pullPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            prepareSearch()
            search.beginPull()
        case .changed:
            search.pull(recognizer.translation(in: view).y)
        case .ended, .cancelled, .failed:
            let velocity = recognizer.state == .ended ? recognizer.velocity(in: view).y : 0
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

/// The stage's root view. A card's face is artwork and takes no touches,
/// and the live app above it is hidden while it moves, so touches inside a
/// moving card are caught here, by where it is on screen, for the stage's
/// own recognizers. Everywhere else, the Home Screen gets them: its pages
/// can be turned while a card lands, and the card follows its icon.
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
