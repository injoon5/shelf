import UIKit

/// The Home Screen proper: the pages of icons, the dock, edit mode's
/// buttons, the sync banner and the empty library, over the wallpaper.
///
/// It follows `HomeModel` and `LibraryStore` by reading them where UIKit
/// tracks observation: `updateProperties()` for what each thing shows (which
/// icons exist, what they say, the jiggle, the badges), `layoutSubviews()`
/// for where everything goes. A change to either model invalidates only the
/// pass that read it.
///
/// Every icon is a sibling at an exact point, the grid's in the paging scroll
/// view and the dock's above the dock's glass, so a reorder is nothing more
/// than points changing. When the layout changes (a hover, a drop, a sync),
/// the new points are set inside a spring, and UIKit's additive animations
/// carry each icon from wherever it is on screen.
@MainActor
final class HomeView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let model: HomeModel
    private let library: LibraryStore
    private let overlay: HomeOverlay

    let pages = UIScrollView()
    private let dock = DockView()
    private let dockIcons = PassthroughView()
    private let editBar = EditBar()
    private let banner = SyncBannerView()
    private let empty = EmptyLibraryView()
    /// Every touch that lands on an icon, from press to drop.
    let touch = IconTouchRecognizer()
    private let wallpaperPress = UILongPressGestureRecognizer()
    private let wallpaperTap = UITapGestureRecognizer()
    private lazy var lightImpact = UIImpactFeedbackGenerator(style: .light, view: self)
    private lazy var mediumImpact = UIImpactFeedbackGenerator(style: .medium, view: self)

    private var icons: [String: IconView] = [:]
    /// Icons whose app has gone, shrinking away (`IconView.leave`). One
    /// whose app comes back before it has gone turns around where it is.
    private var leaving: [String: IconView] = [:]
    /// Until when the icons after a deleted one hold still: they close up
    /// only once it has shrunk away, as on Springboard.
    private var closeUpAt: CFTimeInterval = 0
    /// The next reflow is the close-up after an icon left, or the room made
    /// for one coming back, on `Motion.iconCloseUp`.
    private var closesUp = false
    /// The app the delete alert on screen is for.
    private var alertFor: String?
    /// Icons out of the grid and the dock for now, in the overlay: lifted,
    /// carried, or on their way home. Layout passes leave them be.
    private var held: Set<String> = []
    /// Per held icon, the flight home it is on, so a flight that a new pickup
    /// interrupted doesn't put the icon back when it ends.
    private var flights: [String: Int] = [:]
    private var flightCount = 0

    private struct Lift {
        var icon: IconView
        var menu: IconMenuView
        var finger: CGPoint
    }
    private var lift: Lift?

    private struct Drag {
        var icon: IconView
        /// From the finger to the artwork's centre, kept for the whole drag
        /// so the icon never jumps to the finger.
        var offset: CGPoint
        var pending: (slot: Layout.Slot, task: Task<Void, Never>)?
    }
    private var drag: Drag?

    private var placedLayout: Layout?
    private var placedGeometry: HomeGeometry?
    private var appliedRequest = 0
    private var shownRefusals: [String: Int]?
    private var wasEditing = false

    var geometry = HomeGeometry(size: .zero, safeTop: 0, displayRadius: 0, labelHeight: 0) {
        didSet {
            guard geometry != oldValue else { return }
            setNeedsUpdateProperties()
            setNeedsLayout()
        }
    }
    var labelFont = UIFont.systemFont(ofSize: HomeMetrics.labelSize, weight: .medium) {
        didSet { if labelFont != oldValue { placedGeometry = nil; setNeedsLayout() } }
    }
    /// Icons whose app's card stands in for them: their artwork isn't drawn.
    var cardIcons: Set<String> = [] {
        didSet { for icon in icons.values { icon.hidesArt = cardIcons.contains(icon.id) } }
    }
    /// A tap on a minus badge: the app asks to be deleted, and the alert
    /// (`DeleteAlert`) asks the person.
    lazy var onDelete: (String) -> Void = { [unowned self] id in model.askToDelete(id) }
    /// A finger has come down on an app's icon, which a tap would open:
    /// the stage starts reading its launch snapshot (`StageController`).
    var onPressApp: (String) -> Void = { _ in }
    private lazy var deleteImpact = UIImpactFeedbackGenerator(style: HomeMetrics.deleteImpact, view: self)

    init(model: HomeModel, library: LibraryStore, overlay: HomeOverlay) {
        self.model = model
        self.library = library
        self.overlay = overlay
        super.init(frame: .zero)

        pages.isPagingEnabled = true
        pages.showsHorizontalScrollIndicator = false
        pages.showsVerticalScrollIndicator = false
        pages.alwaysBounceHorizontal = true
        pages.contentInsetAdjustmentBehavior = .never
        // Springboard darkens an icon the instant it is touched; the scroll
        // view mustn't hold the touch back to see whether it scrolls.
        pages.delaysContentTouches = false
        pages.scrollsToTop = false
        pages.delegate = self
        addSubview(pages)
        addSubview(dock)
        addSubview(dockIcons)
        addSubview(empty)
        addSubview(editBar)
        addSubview(banner)

        touch.iconAt = { [unowned self] point in icon(at: point) }
        touch.holdDuration = { [unowned self] in model.isEditing ? Motion.pickupHold : Motion.menuHold }
        touch.onPress = { [unowned self] icon, pressed in
            // In edit mode a touch is a pickup, never a press.
            if !pressed || !model.isEditing { icon.setPressed(pressed) }
            if pressed, !model.isEditing, case .app(let app) = icon.item { onPressApp(app.slug) }
        }
        touch.onTap = { [unowned self] icon, point in tapped(icon, at: point) }
        touch.addTarget(self, action: #selector(touched(_:)))
        addGestureRecognizer(touch)
        // A touch that starts on an icon turns the page only once it is
        // clearly not a press.
        pages.panGestureRecognizer.require(toFail: touch)

        wallpaperPress.minimumPressDuration = Motion.menuHold
        wallpaperPress.addTarget(self, action: #selector(pressedWallpaper(_:)))
        wallpaperTap.addTarget(self, action: #selector(tappedWallpaper))
        for recognizer in [wallpaperPress, wallpaperTap] {
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }

        overlay.onTapOutside = { [unowned self] in dismissLift() }
        overlay.onCarry = { [unowned self] recognizer in carried(recognizer) }
        overlay.isOnLiftedIcon = { [unowned self] point in
            guard let lift else { return false }
            return lift.icon.bounds.contains(lift.icon.convert(point, from: overlay))
        }

        editBar.newApp.addAction(UIAction { [unowned self] _ in model.sheet = .newApp }, for: .primaryActionTriggered)
        editBar.done.addAction(UIAction { [unowned self] _ in model.stopEditing() }, for: .primaryActionTriggered)
        banner.onTap = { [unowned self] shown in
            library.hideBanner()
            if shown == .tokenExpired { model.sheet = .settings }
        }
        empty.onAction = { [unowned self] state in
            switch state {
            case .failed(.unauthorized): model.sheet = .settings
            case .failed: Task { await library.sync() }
            case .empty: model.sheet = .newApp
            case .loading: break
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Following the models

    override func updateProperties() {
        super.updateProperties()
        let layout = library.layout
        let ids = Set(layout.dock + layout.pages.joined())
        let downloading = library.downloading
        let iconSize = geometry.iconSize

        // Icons come and go with the layout.
        for (id, icon) in icons where !ids.contains(id) || library.item(id) == nil {
            icons[id] = nil
            remove(icon)
        }
        for id in ids {
            guard let item = library.item(id) else { continue }
            if let icon = icons[id] {
                icon.configure(item, isDownloading: downloading.contains(id))
            } else if let icon = leaving.removeValue(forKey: id) {
                // Back before it had gone (a deletion the server refused):
                // it grows back from where it is, and the others make room.
                icons[id] = icon
                icon.configure(item, isDownloading: downloading.contains(id))
                icon.hidesArt = cardIcons.contains(id)
                icon.comeBack()
                closesUp = true
                setNeedsLayout()
            } else if iconSize > 0 {
                let icon = IconView(item: item, iconSize: iconSize)
                icon.configure(item, isDownloading: downloading.contains(id))
                icon.hidesArt = cardIcons.contains(id)
                icons[id] = icon
                // New to a layout already on screen (an app back after its
                // icon had gone, or one a sync brought): the others make
                // room on the close-up's spring, and it grows in.
                if placedLayout != nil { closesUp = true }
                setNeedsLayout()
            }
        }

        // Edit mode: the jiggle, the badges, the buttons.
        let editing = model.isEditing
        if editing != wasEditing {
            wasEditing = editing
            if editing { mediumImpact.impactOccurred() }
        }
        for icon in icons.values {
            icon.setJiggling(editing && !held.contains(icon.id))
            icon.setBadge(editing, animated: window != nil)
        }
        editBar.setShown(editing, animated: window != nil)

        // An icon that refused to open shakes.
        let refusals = model.refusals
        if let shown = shownRefusals {
            for (id, count) in refusals where count != shown[id] { icons[id]?.shake() }
        }
        shownRefusals = refusals

        pages.isScrollEnabled = !model.isSearching
        pages.isHidden = library.apps.isEmpty
        empty.show(emptyState)
        banner.show(library.banner, top: geometry.safeTop + HomeMetrics.bannerTopGap, width: bounds.width)

        // A drag the model ended (Done, leaving the foreground, its app
        // deleted elsewhere) ends here too.
        if let drag, model.dragging != drag.icon.id { drop(velocity: .zero) }

        askToDelete(model.deleteRequest)
    }

    private var emptyState: EmptyLibraryView.State? {
        guard library.apps.isEmpty else { return nil }
        if let failure = library.loadFailure { return .failed(failure) }
        return library.isSyncing ? .loading : .empty
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard geometry.size.width > 0 else { return }
        let width = geometry.size.width
        let layout = library.layout
        let pageCount = model.pageCount(layout.pages)

        let geometryChanged = geometry != placedGeometry
        if pages.frame != bounds { pages.frame = bounds }
        pages.contentSize = CGSize(width: CGFloat(pageCount) * width, height: bounds.height)
        dock.place(geometry)
        dockIcons.frame = bounds
        editBar.place(width: width)
        empty.frame = CGRect(x: 0, y: geometry.safeTop, width: width, height: geometry.pillFrame.minY - geometry.safeTop)
        if geometryChanged {
            for icon in icons.values {
                icon.setCell(iconSize: geometry.iconSize, labelWidth: geometry.labelWidth,
                             labelHeight: geometry.labelHeight, labelFont: labelFont)
            }
            pages.contentOffset = CGPoint(x: CGFloat(model.page) * width, y: 0)
        }

        // A layout that changed under the same screen moves its icons on a
        // spring; a new screen, or the first pass, puts them in place. After
        // a deletion, the others hold still until the icon has shrunk away.
        let animated = !geometryChanged && placedLayout != nil && placedLayout != layout
        let wait = closeUpAt - CACurrentMediaTime()
        if animated, wait > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.setNeedsLayout() }
        } else {
            place(layout, animated: animated, spring: closesUp ? Motion.iconCloseUp : Motion.iconReorder)
            if animated || geometryChanged { closesUp = false }
            placedLayout = layout
            placedGeometry = geometry
        }

        // Done on edit mode's spare page: the page goes, and the pages slide
        // back to the last one, as Springboard's do.
        if model.page > pageCount - 1, !pages.isTracking {
            model.go(to: pageCount - 1, animated: true)
        }
        if let request = model.pageRequest, request.serial != appliedRequest {
            appliedRequest = request.serial
            let offset = CGPoint(x: CGFloat(min(request.page, pageCount - 1)) * width, y: 0)
            if request.animated, offset != pages.contentOffset, pageCount > 1 { model.pagesMoved(true) }
            pages.setContentOffset(offset, animated: request.animated)
        }
    }

    private func place(_ layout: Layout, animated: Bool, spring: Motion.Spring) {
        for (index, id) in layout.dock.enumerated() {
            guard let icon = icons[id] else { continue }
            put(icon, in: dockIcons, at: geometry.dockCenter(index, of: layout.dock.count), as: .dock, animated: animated, spring: spring)
        }
        for (page, ids) in layout.pages.enumerated() {
            for (index, id) in ids.enumerated() {
                guard let icon = icons[id] else { continue }
                let center = geometry.iconCenter(index)
                put(icon, in: pages, at: CGPoint(x: CGFloat(page) * geometry.size.width + center.x, y: center.y),
                    as: .grid, animated: animated, spring: spring)
            }
        }
    }

    private func put(_ icon: IconView, in container: UIView, at point: CGPoint, as place: IconView.Place,
                     animated: Bool, spring: Motion.Spring) {
        guard !held.contains(icon.id) else { return }
        if icon.bounds.isEmpty {
            icon.setCell(iconSize: geometry.iconSize, labelWidth: geometry.labelWidth,
                         labelHeight: geometry.labelHeight, labelFont: labelFont)
        }
        icon.place = place
        if icon.superview !== container {
            let isNew = icon.superview == nil
            // From the dock to the grid or back: it changes parents where it
            // is on screen, and moves on from there.
            let onScreen = icon.superview.map { $0.convert(icon.layer.presentation()?.position ?? icon.center, to: container) } ?? point
            container.addSubview(icon)
            UIView.performWithoutAnimation {
                icon.layer.removeAnimations(withKeyPrefix: "position")
                icon.center = onScreen
            }
            if isNew, placedLayout != nil { icon.appear() }
        }
        guard icon.center != point else { return }
        if animated {
            spring.animate { icon.center = point }
        } else {
            UIView.performWithoutAnimation { icon.center = point }
        }
    }

    /// An icon whose app has gone (deleted here or elsewhere) shrinks away
    /// where it is, still jiggling in edit mode, and once it has gone the
    /// others close up behind it, as on Springboard.
    private func remove(_ icon: IconView) {
        held.remove(icon.id)
        if drag?.icon === icon { drag = nil }
        // A lifted icon settles first; with no place to settle into, that
        // comes back here, and it is already on its way out.
        if lift?.icon === icon { dismissLift() }
        let id = icon.id
        if icon.isLeaving { return }
        guard window != nil, icon.superview != nil else {
            icon.removeFromSuperview()
            return
        }
        if leaving[id] !== icon { leaving[id]?.removeFromSuperview() }
        leaving[id] = icon
        icon.leave { [weak self, weak icon] in
            guard let self, let icon, self.leaving[id] === icon else { return }
            self.leaving[id] = nil
            icon.removeFromSuperview()
        }
        closeUpAt = CACurrentMediaTime() + Motion.closeUpDelay * Motion.Spring.slowdown
        closesUp = true
    }

    // MARK: Deleting

    /// Shows Delete App's alert for `id`, once per request.
    private func askToDelete(_ id: String?) {
        guard id != alertFor else { return }
        alertFor = id
        guard let id, let item = library.item(id), let presenter = window != nil ? presenter : nil else {
            // Nothing to ask about (its app went meanwhile), or nowhere to ask.
            if id != nil { model.cancelDelete() }
            return
        }
        // Either answer clears the request, and the next pass `alertFor`.
        let alert = DeleteAlert.make(name: item.name, onDelete: { [unowned self] in
            // UIKit calls this once the alert has gone, so the icon starts
            // to leave over a clear Home Screen, as Springboard's does.
            if let icon = icons[id] {
                deleteImpact.impactOccurred(at: convert(icon.center, from: icon.superview))
            }
            Task { await model.confirmDelete(in: library) }
        }, onCancel: { [unowned self] in
            model.cancelDelete()
        })
        presenter.present(alert, animated: true)
    }

    // MARK: Where icons are

    /// The icon for `id`, wherever it is.
    func iconView(_ id: String) -> IconView? { icons[id] }

    /// Where `id`'s artwork sits, in this view's coordinates, as the layout
    /// puts it: the grid's at the pages' current scroll position (an icon on
    /// another page is a whole page off to that side), or the dock's.
    func iconFrame(for id: String) -> CGRect? {
        let layout = library.layout
        guard let slot = layout.slot(of: id), geometry.size.width > 0 else { return nil }
        let frame = geometry.iconFrame(at: slot, dockCount: layout.dock.count, page: 0)
        if case .page = slot { return frame.offsetBy(dx: -pages.contentOffset.x, dy: 0) }
        return frame
    }

    /// The icon a touch at `point` presses, if one can be pressed now.
    private func icon(at point: CGPoint) -> IconView? {
        guard !model.isSearching, lift == nil, drag == nil, !pages.isDecelerating, !pages.isDragging else { return nil }
        for container in [dockIcons, pages] as [UIView] {
            for case let icon as IconView in container.subviews.reversed() where !held.contains(icon.id) && icons[icon.id] === icon {
                if icon.bounds.contains(icon.convert(point, from: self)) { return icon }
            }
        }
        return nil
    }

    // MARK: Touches

    private func tapped(_ icon: IconView, at point: CGPoint) {
        if model.isEditing {
            if icon.badgeContains(icon.convert(point, from: self)) { onDelete(icon.id) }
            return
        }
        if icon.id == Layout.settings, model.run == nil { lightImpact.impactOccurred(at: point) }
        Task { await model.open(icon.id, in: library) }
    }

    @objc private func touched(_ recognizer: IconTouchRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            guard let icon = recognizer.icon else { return }
            if model.isEditing {
                hold(icon)
                startDrag(icon, finger: point)
            } else {
                liftForMenu(icon, finger: point)
            }
        case .changed:
            if drag != nil {
                moveDrag(to: point)
            } else if let lift, hypot(point.x - lift.finger.x, point.y - lift.finger.y) > HomeMetrics.touchSlop {
                carryOn(finger: point)
            }
        case .ended, .cancelled:
            // A lifted icon's menu stays up once the finger lets go.
            if drag != nil { drop(velocity: recognizer.velocity) }
        default:
            break
        }
    }

    /// A finger that comes back down on the lifted icon while its menu is
    /// up, and moves: the same as moving on without letting go.
    private func carried(_ recognizer: UIPanGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began: carryOn(finger: point)
        case .changed: moveDrag(to: point)
        case .ended, .cancelled: drop(velocity: recognizer.velocity(in: nil))
        default: break
        }
    }

    // MARK: Lift and menu

    /// A still finger held on an icon: it lifts, everything else dims, and
    /// its menu opens beside it (`longpress-menu-grid-photos.png`).
    private func liftForMenu(_ icon: IconView, finger: CGPoint) {
        icon.setPressed(false)
        hold(icon)
        icon.setLifted(true)
        mediumImpact.impactOccurred(at: finger)

        let groups = icon.item.menu(model: model, library: library)
        let probe = IconMenuView(groups: groups, upward: false)
        overlay.addSubview(probe)
        let size = probe.fittingSize
        probe.removeFromSuperview()
        let art = icon.artFrame(in: overlay)
        let lifted = art.insetBy(dx: -art.width * (HomeMetrics.liftScale - 1) / 2, dy: -art.height * (HomeMetrics.liftScale - 1) / 2)
        let area = bounds.inset(by: UIEdgeInsets(top: max(safeAreaInsets.top, geometry.safeTop), left: 0,
                                                 bottom: max(safeAreaInsets.bottom, HomeMetrics.menuMargin), right: 0))
        let placement = IconMenuView.placement(size: size, icon: lifted, area: area)
        let menu = IconMenuView(groups: groups, upward: placement.upward)
        menu.onAction = { [unowned self] action in
            dismissLift()
            action.perform()
        }
        // It grows out of the corner nearest the icon.
        let fromLeft = abs(placement.frame.minX - lifted.minX) <= abs(placement.frame.maxX - lifted.maxX)
        menu.layer.anchorPoint = CGPoint(x: fromLeft ? 0 : 1, y: placement.upward ? 1 : 0)
        menu.frame = placement.frame
        overlay.addSubview(menu)
        menu.alpha = 0
        menu.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        Motion.menuOpen.animate {
            menu.alpha = 1
            menu.transform = .identity
        }
        overlay.bringSubviewToFront(icon)
        overlay.setLifted(true)
        lift = Lift(icon: icon, menu: menu, finger: finger)
    }

    /// The menu goes, the dim lifts, and the icon settles back into place.
    private func dismissLift() {
        guard let lift else { return }
        self.lift = nil
        overlay.setLifted(false)
        closeMenu(lift.menu)
        flyHome(lift.icon, velocity: .zero)
    }

    private func closeMenu(_ menu: IconMenuView) {
        Motion.release.animate({
            menu.alpha = 0
            menu.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }, completion: { _ in menu.removeFromSuperview() })
    }

    /// The finger moved on with the icon lifted: the menu goes, edit mode
    /// starts, and the icon is already in the finger's hold, as on
    /// Springboard.
    private func carryOn(finger: CGPoint) {
        guard let lift else { return }
        self.lift = nil
        overlay.setLifted(false)
        closeMenu(lift.menu)
        model.startEditing()
        startDrag(lift.icon, finger: finger)
    }

    // MARK: Drag

    /// Takes `icon` out of the grid or dock into the overlay, where it is on
    /// screen, so nothing else moves it.
    private func hold(_ icon: IconView) {
        held.insert(icon.id)
        flights[icon.id] = nil
        icon.setJiggling(false)
        guard icon.superview !== overlay else { return }
        let shown = icon.layer.presentation()?.position ?? icon.center
        let onScreen = icon.superview?.convert(shown, to: overlay) ?? shown
        overlay.addSubview(icon)
        UIView.performWithoutAnimation {
            icon.layer.removeAnimations(withKeyPrefix: "position")
            icon.center = onScreen
        }
    }

    private func startDrag(_ icon: IconView, finger: CGPoint) {
        model.beginDrag(icon.id)
        icon.setLifted(true)
        let offset = CGPoint(x: icon.center.x - finger.x, y: icon.center.y - finger.y)
        drag = Drag(icon: icon, offset: offset)
        moveDrag(to: finger)
    }

    /// The icon follows the finger exactly; the others make room once it
    /// rests over a new place.
    private func moveDrag(to finger: CGPoint) {
        guard let drag else { return }
        UIView.performWithoutAnimation {
            drag.icon.layer.removeAnimations(withKeyPrefix: "position")
            drag.icon.center = CGPoint(x: finger.x + drag.offset.x, y: finger.y + drag.offset.y)
        }
        hover()
    }

    private func hover() {
        guard let drag else { return }
        let id = drag.icon.id
        let point = drag.icon.center
        let layout = library.layout
        let page = model.page
        if !geometry.dockFrame.contains(point),
           let target = geometry.flipTarget(at: point.x, page: page, pageCount: model.pageCount(layout.pages)) {
            model.holdAtEdge(toward: target)
        } else {
            model.cancelFlip()
        }
        guard let slot = geometry.dropSlot(for: id, at: point, page: page, in: layout), slot != layout.slot(of: id) else {
            self.drag?.pending?.task.cancel()
            self.drag?.pending = nil
            return
        }
        if drag.pending?.slot == slot { return }
        drag.pending?.task.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(for: Motion.reorderDwell)
            guard !Task.isCancelled, let self, self.drag?.icon.id == id else { return }
            self.drag?.pending = nil
            self.library.move(id, to: slot)
        }
        self.drag?.pending = (slot, task)
    }

    /// Let go: the icon takes the place it was over and springs into it,
    /// carrying the finger's speed.
    private func drop(velocity: CGPoint) {
        guard let drag else { return }
        self.drag = nil
        if let pending = drag.pending {
            pending.task.cancel()
            library.move(drag.icon.id, to: pending.slot)
        }
        model.endDrag()
        library.commitLayout()
        lightImpact.impactOccurred(at: drag.icon.center)
        flyHome(drag.icon, velocity: velocity)
    }

    /// Springs a held icon back to its place in the layout and, once it is
    /// there, returns it to the grid or the dock. An icon with no place (its
    /// app deleted meanwhile) fades away instead.
    private func flyHome(_ icon: IconView, velocity: CGPoint) {
        icon.setLifted(false)
        layoutIfNeeded()
        guard let frame = iconFrame(for: icon.id), icons[icon.id] === icon else {
            held.remove(icon.id)
            remove(icon)
            return
        }
        let target = convert(CGPoint(x: frame.midX, y: frame.midY), to: overlay)
        let distance = hypot(target.x - icon.center.x, target.y - icon.center.y)
        // The finger's speed toward the target, in spring lengths per second.
        let along = distance > 1 ? (velocity.x * (target.x - icon.center.x) + velocity.y * (target.y - icon.center.y)) / (distance * distance) : 0
        flightCount += 1
        let flight = flightCount
        flights[icon.id] = flight
        Motion.iconReorder.animate(velocity: min(max(along, -RunnerMetrics.maxSpringVelocity), RunnerMetrics.maxSpringVelocity)) {
            icon.center = target
        } completion: { [weak self] _ in
            guard let self, self.flights[icon.id] == flight else { return }
            self.flights[icon.id] = nil
            self.held.remove(icon.id)
            self.placedLayout = nil
            self.setNeedsLayout()
            self.setNeedsUpdateProperties()
        }
    }

    // MARK: Pages

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let width = geometry.size.width
        guard width > 0 else { return }
        let count = model.pageCount(library.layout.pages)
        let page = min(max(Int((scrollView.contentOffset.x / width).rounded()), 0), count - 1)
        if page != model.page { model.page = page }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if model.pageCount(library.layout.pages) > 1 { model.pagesMoved(true) }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { model.pagesMoved(false) }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        model.pagesMoved(false)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        model.pagesMoved(false)
        // A page flipped under a held icon: it hovers over the new page,
        // and keeps flipping if it is still at the edge.
        hover()
    }

    // MARK: The wallpaper

    @objc private func pressedWallpaper(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began { model.longPressedWallpaper() }
    }

    @objc private func tappedWallpaper() {
        if model.isEditing { model.stopEditing() }
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: self)
        // Only empty wallpaper: not an icon, not a button.
        if icon(at: point) != nil || touch.view is UIControl { return false }
        if let view = touch.view, view.isDescendant(of: banner) || view.isDescendant(of: editBar) || view.isDescendant(of: empty) {
            return false
        }
        return recognizer === wallpaperTap ? model.isEditing : !model.isEditing
    }
}

/// What sits above the whole Home Screen, the search pill included, while an
/// icon is out of its place: the dim behind a lifted icon, the lifted or
/// carried icon itself, and its menu. With nothing lifted it takes no
/// touches.
final class HomeOverlay: UIView, UIGestureRecognizerDelegate {
    private let dim = UIView()
    private let tap = UITapGestureRecognizer()
    private let carry = UIPanGestureRecognizer()
    private(set) var isLifted = false
    var onTapOutside: () -> Void = {}
    var onCarry: (UIPanGestureRecognizer) -> Void = { _ in }
    var isOnLiftedIcon: (CGPoint) -> Bool = { _ in false }

    override init(frame: CGRect) {
        super.init(frame: frame)
        dim.backgroundColor = .black
        dim.alpha = 0
        dim.isUserInteractionEnabled = false
        addSubview(dim)
        tap.addTarget(self, action: #selector(tapped))
        carry.addTarget(self, action: #selector(carried))
        for recognizer in [tap, carry] {
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        dim.frame = bounds
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isLifted else { return nil }
        let hit = super.hitTest(point, with: event)
        return hit ?? self
    }

    /// Everything but the lifted icon and its menu goes to 80%.
    func setLifted(_ lifted: Bool) {
        isLifted = lifted
        Motion.iconLift.animate { self.dim.alpha = lifted ? HomeMetrics.liftDim : 0 }
    }

    override func addSubview(_ view: UIView) {
        super.addSubview(view)
        sendSubviewToBack(dim)
    }

    @objc private func tapped() { onTapOutside() }
    @objc private func carried() { onCarry(carry) }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view is UIControl { return false }
        let point = touch.location(in: self)
        return recognizer === carry ? isOnLiftedIcon(point) : !isOnLiftedIcon(point)
    }
}

extension CALayer {
    /// Removes the animations on `prefix` and its parts ("position",
    /// "position.x", and UIKit's additive "position-2" and so on).
    func removeAnimations(withKeyPrefix prefix: String) {
        for key in animationKeys() ?? [] where key.hasPrefix(prefix) {
            removeAnimation(forKey: key)
        }
    }
}
