import UIKit

/// One icon on the Home Screen, in the grid or the dock: an app or Settings,
/// with its artwork (`IconArtView`), its label, and edit mode's minus badge.
///
/// The view is the icon's whole cell, but its layer's position is the
/// artwork's centre (the anchor point sits there), so the stage places,
/// springs, lifts and drops an icon by where its artwork is, and the jiggle
/// and the lift turn about the artwork's centre, as Springboard's do.
///
/// It takes no touches itself: the Home Screen's one recognizer
/// (`IconTouchRecognizer`) finds the icon under a finger and drives it.
final class IconView: UIView {
    enum Place { case grid, dock }

    let id: String
    private(set) var item: HomeItem
    var place: Place = .grid {
        didSet { if place != oldValue { updateLabel(animated: true) } }
    }
    let art: IconArtView

    /// What the jiggle turns, apart from the view, whose own transform is the
    /// lift: so the two never fight over one property.
    private let wobble = UIView()
    private let label = IconLabelView()
    private let badge = MinusBadge()
    private var iconSize: CGFloat
    private(set) var isJiggling = false
    private(set) var isLifted = false
    private var showsBadge = false
    private var hidesLabel = false

    init(item: HomeItem, iconSize: CGFloat) {
        id = item.id
        self.item = item
        self.iconSize = iconSize
        art = IconArtView(face: item.face, iconSize: iconSize)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(wobble)
        wobble.addSubview(art)
        wobble.addSubview(label)
        wobble.addSubview(badge)
        badge.alpha = 0
        label.name = item.name
        label.isNew = item.app?.isNew == true
        // Drawn once and composited as one bitmap while it jiggles or pages:
        // the rim's mask and the label's shadow would otherwise be drawn
        // again every frame, for every icon.
        wobble.layer.shouldRasterize = true
        registerForTraitChanges([UITraitDisplayScale.self]) { (icon: IconView, _) in
            icon.wobble.layer.rasterizationScale = icon.traitCollection.displayScale
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let scale = window?.traitCollection.displayScale, scale > 0 { wobble.layer.rasterizationScale = scale }
    }

    // MARK: Content

    func configure(_ item: HomeItem, isDownloading: Bool) {
        self.item = item
        art.face = item.face
        label.name = item.name
        label.isNew = item.app?.isNew == true
        art.setPending(isRunnable: item.app?.isRunnable ?? true, isDownloading: isDownloading)
    }

    /// Sizes the cell: the artwork at the top, centred, and the label below.
    func setCell(iconSize: CGFloat, labelWidth: CGFloat, labelHeight: CGFloat, labelFont: UIFont) {
        self.iconSize = iconSize
        let width = max(labelWidth, iconSize)
        let height = iconSize + HomeMetrics.labelGap + labelHeight
        let position = layer.position
        layer.anchorPoint = CGPoint(x: 0.5, y: iconSize / 2 / height)
        bounds = CGRect(x: 0, y: 0, width: width, height: height)
        layer.position = position
        wobble.layer.anchorPoint = layer.anchorPoint
        wobble.frame = bounds
        art.center = CGPoint(x: width / 2, y: iconSize / 2)
        label.font = labelFont
        label.frame = CGRect(x: (width - labelWidth) / 2, y: iconSize + HomeMetrics.labelGap, width: labelWidth, height: labelHeight)
        let badgeCenter = CGPoint(x: width / 2 - iconSize / 2 + HomeMetrics.badgeInset, y: HomeMetrics.badgeInset)
        badge.bounds = CGRect(x: 0, y: 0, width: HomeMetrics.badgeSize, height: HomeMetrics.badgeSize)
        badge.center = badgeCenter
        updateLabel(animated: false)
    }

    /// Where the artwork is, in `space`'s coordinates, as laid out (not
    /// mid-animation): what a card grows out of and lands on.
    func artFrame(in space: UIView) -> CGRect {
        let center = superview.map { space.convert(layer.position, from: $0) } ?? layer.position
        return CGRect(x: center.x - iconSize / 2, y: center.y - iconSize / 2, width: iconSize, height: iconSize)
    }

    /// Whether `point` (in this view's coordinates) is on the minus badge,
    /// or close enough for a finger.
    func badgeContains(_ point: CGPoint) -> Bool {
        guard showsBadge else { return false }
        let target = max(HomeMetrics.minimumHit, HomeMetrics.badgeSize)
        let center = wobble.convert(badge.center, to: self)
        return hypot(point.x - center.x, point.y - center.y) <= target / 2
    }

    /// Whether `point` (in this view's coordinates) is on the artwork or
    /// its label: what a finger has to touch to press the icon.
    func touchArea(contains point: CGPoint) -> Bool {
        bounds.insetBy(dx: 0, dy: 0).contains(point)
    }

    // MARK: States

    /// While an app's card stands in for its icon, the artwork isn't drawn.
    /// Its label stays, as on Springboard.
    var hidesArt = false {
        didSet { art.isHidden = hidesArt }
    }

    func setPressed(_ isPressed: Bool) {
        art.setPressed(isPressed)
    }

    /// Lifted under a long press or a drag: larger about the artwork's
    /// centre, still, and without its label or badge.
    func setLifted(_ lifted: Bool, velocity: CGFloat = 0) {
        guard lifted != isLifted else { return }
        isLifted = lifted
        // A bitmap scaled up would blur; drawn as it is, the icon stays sharp.
        wobble.layer.shouldRasterize = !lifted
        Motion.iconLift.animate(velocity: velocity) {
            self.transform = lifted ? CGAffineTransform(scaleX: HomeMetrics.liftScale, y: HomeMetrics.liftScale) : .identity
        }
        updateLabel(animated: true)
        updateBadge(animated: true)
    }

    /// The label shows in the grid and hides in the dock and while lifted.
    private func updateLabel(animated: Bool) {
        let hidden = place == .dock || isLifted
        guard hidden != hidesLabel || !animated else { return }
        hidesLabel = hidden
        fade(label, to: hidden ? 0 : 1, animated: animated)
    }

    func setBadge(_ shown: Bool, animated: Bool) {
        let shown = shown && item.isDeletable
        guard shown != showsBadge else { return }
        showsBadge = shown
        updateBadge(animated: animated)
    }

    private func updateBadge(animated: Bool) {
        let shown = showsBadge && !isLifted
        let change = {
            self.badge.alpha = shown ? 1 : 0
            self.badge.transform = shown ? .identity : CGAffineTransform(scaleX: 0.6, y: 0.6)
        }
        if animated { Motion.editMode.animate(change) } else { UIView.performWithoutAnimation(change) }
    }

    private func fade(_ view: UIView, to alpha: CGFloat, animated: Bool) {
        if animated {
            Motion.release.animate { view.alpha = alpha }
        } else {
            UIView.performWithoutAnimation { view.alpha = alpha }
        }
    }

    // MARK: Jiggle

    /// Edit mode's wobble: a small rotation and a smaller vertical shift,
    /// each icon starting at its own moment so they never move in step.
    ///
    /// It is one repeating Core Animation animation per icon, which the
    /// render server plays by itself: nothing runs on the main thread (where
    /// Kiln runs apps) for any frame of it.
    func setJiggling(_ on: Bool) {
        guard on != isJiggling else { return }
        isJiggling = on
        let layer = wobble.layer
        if on {
            layer.add(Self.jiggle(startingIn: Double.random(in: 0..<Motion.jigglePeriod), on: layer), forKey: Self.jiggleKey)
        } else {
            // From wherever the swing is, back to rest.
            let shown = layer.presentation()
            let angle = shown?.value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0
            let shift = shown?.value(forKeyPath: "transform.translation.y") as? CGFloat ?? 0
            layer.removeAnimation(forKey: Self.jiggleKey)
            for (keyPath, value) in [("transform.rotation.z", angle), ("transform.translation.y", shift)] {
                let settle = CASpringAnimation(perceptualDuration: Motion.release.playedDuration, bounce: 0)
                settle.keyPath = keyPath
                settle.fromValue = value
                settle.toValue = 0
                settle.duration = settle.settlingDuration
                layer.add(settle, forKey: keyPath)
            }
        }
    }

    static let jiggleKey = "jiggle"

    /// Out to one side, back through the middle to the other, and home, as
    /// a sine would: easing out toward each side and in from it.
    static func jiggle(startingIn delay: Double, on layer: CALayer) -> CAAnimation {
        let angle = HomeMetrics.jiggleAngle * .pi / 180
        let shift = HomeMetrics.jiggleShift
        let times: [NSNumber] = [0, 0.25, 0.5, 0.75, 1]
        let curves = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn),
                      CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotation.values = [0, angle, 0, -angle, 0]
        let lift = CAKeyframeAnimation(keyPath: "transform.translation.y")
        lift.values = [0, shift, 0, -shift, 0]
        for keyframes in [rotation, lift] {
            keyframes.keyTimes = times
            keyframes.timingFunctions = curves
        }
        let group = CAAnimationGroup()
        group.animations = [rotation, lift]
        group.duration = Motion.jigglePeriod * Motion.Spring.slowdown
        group.repeatCount = .infinity
        // Each icon starts at its own moment; until then it is at rest,
        // which is where the swing starts, so nothing jumps.
        group.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay * Motion.Spring.slowdown
        group.isRemovedOnCompletion = false
        return group
    }

    // MARK: Shake

    /// A quick side-to-side shake: this icon can't open right now.
    func shake() {
        let distance = HomeMetrics.shakeDistance
        let steps = Motion.shakeSteps
        let total = steps.reduce(0, +)
        var elapsed = 0.0
        var times: [NSNumber] = [0]
        for step in steps {
            elapsed += step
            times.append(NSNumber(value: elapsed / total))
        }
        let shake = CAKeyframeAnimation(keyPath: "position.x")
        shake.values = [0, distance, -distance, distance / 2, 0]
        shake.keyTimes = times
        shake.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut),
                                 CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(controlPoints: 0.2, 1.4, 0.4, 1)]
        shake.duration = total * Motion.Spring.slowdown
        shake.isAdditive = true
        layer.add(shake, forKey: "shake")
    }
}

/// The name under an icon, white with a soft shadow, and the blue dot of an
/// app added or changed and not opened since.
final class IconLabelView: UIView {
    private let text = UILabel()
    private let dot = UIView()

    var name = "" {
        didSet { if name != oldValue { text.text = name; setNeedsLayout() } }
    }
    var isNew = false {
        didSet { if isNew != oldValue { dot.isHidden = !isNew; setNeedsLayout() } }
    }
    var font: UIFont = .systemFont(ofSize: HomeMetrics.labelSize, weight: .medium) {
        didSet { text.font = font; setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        text.font = font
        text.textColor = .white
        text.lineBreakMode = .byTruncatingTail
        text.textAlignment = .center
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Float(HomeMetrics.labelShadowOpacity)
        layer.shadowRadius = HomeMetrics.labelShadowRadius
        layer.shadowOffset = CGSize(width: 0, height: HomeMetrics.labelShadowY)
        dot.backgroundColor = .systemBlue
        dot.layer.cornerRadius = HomeMetrics.newDotSize / 2
        dot.isHidden = true
        addSubview(dot)
        addSubview(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The dot and the name, centred together; the name is cut short with
    /// an ellipsis when the two don't fit.
    override func layoutSubviews() {
        super.layoutSubviews()
        let lead = isNew ? HomeMetrics.newDotSize + HomeMetrics.newDotGap : 0
        let natural = text.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: bounds.height)).width
        let width = min(natural.rounded(.up), bounds.width - lead)
        let start = (bounds.width - lead - width) / 2
        dot.frame = CGRect(x: start, y: (bounds.height - HomeMetrics.newDotSize) / 2,
                           width: HomeMetrics.newDotSize, height: HomeMetrics.newDotSize)
        text.frame = CGRect(x: start + lead, y: 0, width: width, height: bounds.height)
    }
}

/// Edit mode's minus badge: a grey disc with a dark dash, on the icon's
/// top-left corner (`closeup-edit-badge-icon.png`).
final class MinusBadge: UIView {
    private let dash = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = HomeMetrics.badgeFill
        dash.backgroundColor = .black
        dash.layer.cornerRadius = HomeMetrics.badgeDash.height / 2
        addSubview(dash)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        dash.bounds = CGRect(origin: .zero, size: HomeMetrics.badgeDash)
        dash.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

extension HomeItem {
    /// What the icon is drawn from.
    @MainActor
    var face: IconFace {
        switch self {
        case .app(let app): IconFace(app.meta)
        case .settings: .settings
        }
    }
}
