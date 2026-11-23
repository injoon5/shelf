import UIKit

/// The search pill and the field it warps into: one piece of glass, one
/// label, and the round ✕ that arrives beside them. App Library's top bar,
/// at the bottom (PLAN.md §0.3).
///
/// At rest it is the pill above the dock, reading "Search", or page dots
/// while pages move and in edit mode. Pulling down on the Home Screen
/// stretches it toward the field, as far as the finger has gone; a tap plays
/// the same warp. The field sits on the pill's line until the keyboard rises
/// and carries it up to just above itself.
///
/// The warp is one number, `progress`, 0 the pill and 1 the field, on a
/// spring stepped every frame (`ValueSpring`). Everything that follows it is
/// set from that one number in the same frame: the glass's frame, the label
/// (drawn once, at the field's size, and scaled down to the pill's; never two
/// labels), the ✕, and through `onProgress` what the stage owns: the Home
/// Screen blurring and fading, the backdrop, the list. So nothing is ever
/// shown twice, and a finger can catch the warp anywhere and go on from
/// exactly where it is, at the speed it was going.
@MainActor
final class SearchBar: UIView, UITextFieldDelegate {
    var onTapPill: () -> Void = {}
    var onQuery: (String) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    /// The ✕.
    var onClose: () -> Void = {}
    /// Every new point of the warp, for what the stage moves with it.
    var onProgress: (CGFloat) -> Void = { _ in }
    /// Where the warp is headed changed: open or not.
    var onOpenChanged: (Bool) -> Void = { _ in }
    /// The field's top, once the keyboard has moved it: the list ends above it.
    var onFieldMoved: (CGFloat) -> Void = { _ in }

    /// Lifted by the keyboard. The warp happens inside it.
    private let ride = UIView()
    private let glass = UIVisualEffectView()
    private let label = SearchLabel()
    private let dots = DotsView()
    private let field = SearchTextField()
    private let closeButton = GlassCircleButton(symbol: "xmark")
    /// What holds the glass, the label and the ✕: the list's soft edge
    /// reaches up behind them, so rows going under the field blur away as
    /// they do under App Library's bar.
    var edgeContainer: UIView { ride }

    private let warp = ValueSpring(0)
    private var geometry: HomeGeometry?
    /// Where the warp is headed: open (the field) or not (the pill).
    private(set) var isOpen = false
    private var pullStart: CGFloat = 0
    private var keyboardTop: CGFloat?
    private var showsDots = false
    private var dotCount = 1

    /// How far along the warp it is now, on screen.
    var progress: CGFloat { warp.value }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(ride)

        glass.cornerConfiguration = .capsule()
        glass.isAccessibilityElement = true
        glass.accessibilityLabel = String(localized: "Search")
        glass.accessibilityTraits = .button
        glass.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        ride.addSubview(glass)

        dots.isUserInteractionEnabled = false
        dots.alpha = 0
        glass.contentView.addSubview(dots)

        label.isUserInteractionEnabled = false
        ride.addSubview(label)

        field.delegate = self
        field.returnKeyType = .go
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.clearButtonMode = .whileEditing
        field.adjustsFontForContentSizeCategory = true
        field.accessibilityLabel = String(localized: "Search")
        field.textColor = .white
        field.tintColor = .white
        field.keyboardAppearance = .dark
        field.alpha = 0
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        ride.addSubview(field)

        closeButton.accessibilityLabel = String(localized: "Close Search")
        closeButton.alpha = 0
        closeButton.isUserInteractionEnabled = false
        closeButton.addAction(UIAction { [unowned self] _ in onClose() }, for: .touchUpInside)
        ride.addSubview(closeButton)

        warp.onChange = { [unowned self] p in place(p) }

        maximumContentSizeCategory = UIContentSizeCategory(ShelfMetrics.textSizeCap)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) { (bar: SearchBar, _) in
            bar.restyle()
        }
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Only the glass, the field and the ✕ take touches; the rest of the
    // Home Screen is under this view.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self || hit === ride ? nil : hit
    }

    // MARK: Layout

    private var pill: CGRect {
        guard let geometry else { return .zero }
        let frame = geometry.pillFrame
        let width = showsDots ? max(frame.width, dots.width(for: dotCount) + 2 * HomeMetrics.pillDotsPadding) : frame.width
        return CGRect(x: frame.midX - width / 2, y: frame.minY, width: width, height: frame.height)
    }

    private var fieldFrame: CGRect {
        guard let geometry else { return .zero }
        return SearchWarp.field(screenWidth: geometry.size.width, pill: geometry.pillFrame)
    }

    func layout(_ geometry: HomeGeometry) {
        guard geometry != self.geometry else { return }
        self.geometry = geometry
        ride.bounds = CGRect(origin: .zero, size: geometry.size)
        ride.center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        placeField()
        place(warp.value)
    }

    /// Everything that follows the warp, at progress `p`. The spring may
    /// carry `p` a little past the field: the glass stretches with it, and
    /// everything else stops at the field.
    private func place(_ p: CGFloat) {
        let shown = min(max(p, 0), 1)
        let pill = pill
        let target = fieldFrame
        UIView.performWithoutAnimation {
            glass.frame = pill.interpolated(to: target, min(max(p, 0), SearchWarp.overshoot))
            dots.center = CGPoint(x: glass.bounds.midX, y: glass.bounds.midY)
            label.place(shown, pill: pill, field: target)

            let arrival = SearchMetrics.closeArrival.ramp(shown)
            closeButton.alpha = arrival
            let scale = 0.5 + 0.5 * arrival
            closeButton.transform = CGAffineTransform(scaleX: scale, y: scale)
            field.alpha = SearchMetrics.caretArrival.ramp(shown)
        }
        onProgress(p)
    }

    private func placeField() {
        guard let geometry else { return }
        let frame = fieldFrame
        let leading = SearchMetrics.typedInset
        field.frame = CGRect(x: frame.minX + leading, y: frame.minY,
                             width: frame.width - leading - SearchMetrics.textTrailing, height: frame.height)
        UIView.performWithoutAnimation {
            closeButton.transform = .identity
            closeButton.frame = SearchWarp.close(screenWidth: geometry.size.width, field: frame)
        }
    }

    // MARK: Opening and closing

    /// Warps to the field from wherever it is, and raises the keyboard with
    /// it. `velocity` is in warps per second; nil keeps the speed it has.
    func open(velocity: CGFloat? = nil) {
        if !isOpen {
            field.text = ""
            textChanged()
        }
        setOpen(true)
        setDots(false, animated: true)
        stopGlassAnimations()
        warp.animate(to: 1, Motion.searchWarp, velocity: velocity)
        field.becomeFirstResponder()
    }

    /// Warps back to the pill from wherever it is.
    func close(velocity: CGFloat? = nil) {
        setOpen(false)
        field.resignFirstResponder()
        stopGlassAnimations()
        warp.animate(to: 0, Motion.searchWarp, velocity: velocity)
    }

    /// Lets the keyboard go, leaving search open: an app opened from it.
    func dismissKeyboard() {
        field.resignFirstResponder()
    }

    private func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        glass.accessibilityElementsHidden = open
        closeButton.isUserInteractionEnabled = open
        onOpenChanged(open)
    }

    /// The pill's own resize (for its dots) is a view animation; the warp
    /// takes the glass over from wherever that has got to.
    private func stopGlassAnimations() {
        glass.freezeOnScreen()
    }

    // MARK: Pulling

    /// A pull down on the Home Screen has begun: the warp stops where it is
    /// on screen, and follows the finger from there.
    func beginPull() {
        warp.stop()
        stopGlassAnimations()
        pullStart = warp.value
        setDots(false, animated: true)
    }

    func pull(_ distance: CGFloat) {
        warp.set(SearchWarp.progress(pull: distance, from: pullStart))
    }

    /// The pull has been let go of, moving down at `velocity` (pt/s).
    /// Returns whether search opened.
    func endPull(velocity: CGFloat) -> Bool {
        let warpVelocity = velocity / SearchMetrics.pullDistance
        if SearchWarp.opens(progress: warp.value, velocity: velocity) {
            open(velocity: warpVelocity)
            return true
        }
        setOpen(false)
        warp.animate(to: 0, Motion.searchWarp, velocity: warpVelocity)
        return false
    }

    // MARK: Page dots

    /// Dots stand in for "Search" while pages move and in edit mode.
    func setDots(_ shown: Bool, count: Int? = nil, current: Int? = nil, animated: Bool) {
        let shown = shown && !isOpen
        if let current { dots.current = current }
        let countChanged = count.map { $0 != dotCount } ?? false
        if let count { dotCount = count; dots.count = count }
        guard shown != showsDots || countChanged else { return }
        showsDots = shown
        guard geometry != nil else { return }
        let change = {
            self.dots.alpha = shown ? 1 : 0
            self.label.alpha = shown ? 0 : 1
        }
        if animated {
            UIView.animate(withDuration: Motion.pillFade, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: change)
            if !isOpen, !warp.isMoving, warp.value == 0 {
                UIView.retarget([glass], Motion.pillResize) {
                    self.glass.frame = self.pill
                    self.dots.center = CGPoint(x: self.glass.bounds.midX, y: self.glass.bounds.midY)
                }
            }
        } else {
            change()
            place(warp.value)
        }
        glass.accessibilityLabel = shown ? String(localized: "Page \(dots.current + 1) of \(dotCount)") : String(localized: "Search")
    }

    // MARK: The field

    /// Where the field will be once the keyboard has lifted it, as far as
    /// is known.
    var restingField: CGRect {
        fieldFrame.offsetBy(dx: 0, dy: isOpen ? SearchWarp.lift(field: fieldFrame, keyboardTop: keyboardTop) : 0)
    }

    @objc private func tapped() { onTapPill() }

    @objc private func textChanged() {
        let text = field.text ?? ""
        label.showsText = text.isEmpty
        onQuery(text)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onSubmit()
        return false
    }

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let info = note.userInfo, let end = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let top = convert(end, from: nil).minY
        keyboardTop = top < bounds.maxY ? top : nil
        let lift = isOpen ? SearchWarp.lift(field: fieldFrame, keyboardTop: keyboardTop) : 0
        let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0
        let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
        // The field rides with the keyboard, on the keyboard's own curve,
        // from wherever it is on screen.
        ride.freezeOnScreen()
        UIView.animate(withDuration: duration, delay: 0,
                       options: [UIView.AnimationOptions(rawValue: curve << 16), .allowUserInteraction]) {
            self.ride.transform = CGAffineTransform(translationX: 0, y: lift)
        }
        onFieldMoved(fieldFrame.minY + lift)
    }

    private func restyle() {
        glass.effect = HomeGlass.effect(traitCollection, interactive: true)
        let category = min(traitCollection.preferredContentSizeCategory, UIContentSizeCategory(ShelfMetrics.textSizeCap))
        let traits = UITraitCollection(preferredContentSizeCategory: category == .unspecified ? .large : category)
        let fieldFont = UIFont.preferredFont(forTextStyle: SearchMetrics.fieldTextStyle, compatibleWith: traits)
        // Springboard's pill keeps its size at every text size.
        let pillFont = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        label.configure(fieldSize: fieldFont.pointSize, pillSize: pillFont.pointSize)
        field.font = fieldFont
        dots.layoutDots()
        placeField()
        place(warp.value)
    }
}

/// The magnifier and "Search": one row, drawn at the field's size and scaled
/// to the pill's, so there is only ever one, and its text is never a bitmap
/// scaled up.
///
/// The pill's label is Springboard's (`closeup-search-pill.png`): caption
/// size, medium, at 70% white, with a small bold magnifier 3.33 pt from the
/// text. The field's is App Library's: Title 2, regular, white, with the
/// magnifier centred 27 pt into the field and the text 48 pt in. Between the two
/// the row's scale, its weight, its colour and the magnifier's size and gap
/// all move with the warp, so it reads as one label getting bigger.
private final class SearchLabel: UIView {
    private let glyph = UIImageView()
    private let text = UILabel()
    private var fieldSize: CGFloat = 22
    private var pillSize: CGFloat = 12
    /// The magnifier as drawn in the pill and in the field, in points.
    private var pillGlyph = CGSize(width: 10, height: 10)
    private var fieldGlyph = CGSize(width: 17, height: 17)
    /// "Search" as wide as it is in the pill, at the pill's size.
    private var pillTextWidth: CGFloat = 40
    /// The letter-spacing, in the row's own points, that makes "Search"
    /// drawn at the field's size as wide as the pill's once scaled down: SF
    /// tracks a 12 pt size looser than a 22 pt one.
    private var pillKern: CGFloat = 0
    /// The magnifier in each weight it passes through, boldest first: the
    /// pill's is bold, the field's regular.
    private var glyphs: [UIImage] = []
    private var shownWeight: CGFloat = .nan
    private var shownGlyph = -1

    var showsText = true {
        didSet { text.isHidden = !showsText }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.anchorPoint = CGPoint(x: 0, y: 0.5)
        text.text = String(localized: "Search")
        glyph.contentMode = .scaleToFill
        addSubview(glyph)
        addSubview(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(fieldSize: CGFloat, pillSize: CGFloat) {
        self.fieldSize = fieldSize
        self.pillSize = pillSize
        glyphs = [UIImage.SymbolWeight.bold, .semibold, .medium, .regular].compactMap { weight in
            UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(
                pointSize: fieldSize * SearchMetrics.glyphScale, weight: weight, scale: .medium))?.withRenderingMode(.alwaysTemplate)
        }
        let pill = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: pillSize, weight: .bold, scale: .small))
        fieldGlyph = glyphs.last?.size ?? fieldGlyph
        pillGlyph = pill?.size ?? pillGlyph
        let word = text.text ?? ""
        pillTextWidth = NSAttributedString(string: word, attributes: [.font: UIFont.systemFont(ofSize: pillSize, weight: .medium)]).size().width
        let drawn = NSAttributedString(string: word, attributes: [.font: UIFont.systemFont(ofSize: fieldSize, weight: .medium)]).size().width
        pillKern = (pillTextWidth * fieldSize / pillSize - drawn) / CGFloat(max(word.count, 1))
        shownWeight = .nan
        shownGlyph = -1
    }

    /// The row at `p` of the way from the pill to the field.
    func place(_ p: CGFloat, pill: CGRect, field: CGRect) {
        let pillScale = pillSize / fieldSize
        let scale = lerp(pillScale, 1, p)

        // Medium in the pill, regular in the field, through every weight
        // between, and the pill's looser spacing easing out.
        let weight = lerp(UIFont.Weight.medium.rawValue, UIFont.Weight.regular.rawValue, p)
        if abs(weight - shownWeight) > 0.002 || shownWeight.isNaN {
            shownWeight = weight
            text.attributedText = NSAttributedString(string: String(localized: "Search"), attributes: [
                .font: UIFont.systemFont(ofSize: fieldSize, weight: UIFont.Weight(weight)),
                .kern: pillKern * (1 - p),
            ])
            text.sizeToFit()
        }
        // The magnifier's weight can only step; it steps while it's small.
        let step = min(Int(p * CGFloat(glyphs.count + 1)), glyphs.count - 1)
        if step != shownGlyph, glyphs.indices.contains(step) {
            shownGlyph = step
            glyph.image = glyphs[step]
        }
        let ink = UIColor.white.withAlphaComponent(lerp(HomeMetrics.pillTextOpacity, 1, p))
        text.textColor = ink
        glyph.tintColor = ink

        // In the row's own points, which the row's scale takes to the screen.
        let glyphWidth = lerp(pillGlyph.width / pillScale, fieldGlyph.width, p)
        let glyphHeight = glyphWidth * fieldGlyph.height / max(fieldGlyph.width, 1)
        let fieldGlyphStart = SearchMetrics.glyphCenter - fieldGlyph.width / 2
        let textStart = lerp((pillGlyph.width + HomeMetrics.pillGlyphGap) / pillScale,
                             SearchMetrics.textInset - fieldGlyphStart, p)
        let height = max(text.bounds.height, glyphHeight)
        bounds = CGRect(x: 0, y: 0, width: textStart + text.bounds.width, height: height)
        glyph.frame = CGRect(x: 0, y: (height - glyphHeight) / 2, width: glyphWidth, height: glyphHeight)
        text.frame.origin = CGPoint(x: textStart, y: (height - text.bounds.height) / 2)

        // The pill's row is centred in it; the field's starts at the magnifier's inset.
        let pillRow = pillGlyph.width + HomeMetrics.pillGlyphGap + pillTextWidth
        let leading = lerp(pill.midX - pillRow / 2, field.minX + fieldGlyphStart, p)
        transform = CGAffineTransform(scaleX: scale, y: scale)
        center = CGPoint(x: leading, y: lerp(pill.midY, field.midY, p))
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

/// The field's text, with App Library's caret: 24 pt tall, centred on the
/// field and on where the next letter goes.
private final class SearchTextField: UITextField {
    override func caretRect(for position: UITextPosition) -> CGRect {
        let caret = super.caretRect(for: position)
        let size = SearchMetrics.caretSize
        // UIKit's starts at that point; App Library's straddles it.
        return CGRect(x: caret.minX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
}

/// A round glass button with a white glyph: search's ✕, App Library's. Its
/// glass is the field's own (`HomeGlass`), so the two read as one material.
final class GlassCircleButton: UIControl {
    private let glass = UIVisualEffectView()
    private let glyph = UIImageView()

    init(symbol: String) {
        super.init(frame: .zero)
        glass.cornerConfiguration = .capsule()
        glass.isUserInteractionEnabled = false
        addSubview(glass)
        glyph.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(
            pointSize: SearchMetrics.closeGlyphSize, weight: .regular, scale: .medium))
        glyph.tintColor = .white
        glyph.contentMode = .center
        glass.contentView.addSubview(glyph)
        isAccessibilityElement = true
        accessibilityTraits = .button
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (button: GlassCircleButton, _) in
            button.glass.effect = HomeGlass.effect(button.traitCollection, interactive: true)
        }
        glass.effect = HomeGlass.effect(traitCollection, interactive: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        glyph.frame = glass.contentView.bounds
    }
}

/// Springboard's page dots, the current one white.
private final class DotsView: UIView {
    var count = 1 {
        didSet { if count != oldValue { layoutDots() } }
    }
    var current = 0 {
        didSet { if current != oldValue { recolor() } }
    }
    private var dots: [UIView] = []

    func width(for count: Int) -> CGFloat {
        CGFloat(count) * HomeMetrics.pageDotSize + CGFloat(max(count - 1, 0)) * HomeMetrics.pageDotGap
    }

    func layoutDots() {
        dots.forEach { $0.removeFromSuperview() }
        dots = (0..<count).map { index in
            let dot = UIView(frame: CGRect(x: CGFloat(index) * (HomeMetrics.pageDotSize + HomeMetrics.pageDotGap), y: 0,
                                           width: HomeMetrics.pageDotSize, height: HomeMetrics.pageDotSize))
            dot.layer.cornerRadius = HomeMetrics.pageDotSize / 2
            dot.backgroundColor = .white
            addSubview(dot)
            return dot
        }
        bounds.size = CGSize(width: width(for: count), height: HomeMetrics.pageDotSize)
        recolor()
    }

    private func recolor() {
        UIView.animate(springDuration: Motion.pillResize.playedDuration, bounce: Motion.pillResize.bounce,
                       initialSpringVelocity: 0, delay: 0, options: [.beginFromCurrentState]) {
            for (index, dot) in self.dots.enumerated() {
                dot.alpha = index == self.current ? 1 : HomeMetrics.pageDotDim
            }
        }
    }
}

/// The rules the search pill warps into the field by, apart from any view.
enum SearchWarp {
    /// How far past the field the glass may stretch when the spring carries
    /// it there.
    static let overshoot: CGFloat = 1.03

    /// How far along the warp a pull of `pull` points takes it, from `start`.
    static func progress(pull: CGFloat, from start: CGFloat) -> CGFloat {
        min(max(start + pull / SearchMetrics.pullDistance, 0), 1)
    }

    /// Whether a pull let go of at `progress`, moving down at `velocity`
    /// (pt/s), opens search.
    static func opens(progress: CGFloat, velocity: CGFloat) -> Bool {
        if velocity > SearchMetrics.openVelocity { return true }
        if velocity < -SearchMetrics.openVelocity { return false }
        return progress > SearchMetrics.openProgress
    }

    /// The field before the keyboard lifts it: App Library's, on the pill's
    /// line, from the leading inset to the ✕.
    static func field(screenWidth: CGFloat, pill: CGRect) -> CGRect {
        let height = SearchMetrics.fieldHeight
        let inset = SearchMetrics.sideInset
        return CGRect(x: inset, y: pill.midY - height / 2,
                      width: screenWidth - 2 * inset - SearchMetrics.closeSize - SearchMetrics.closeGap, height: height)
    }

    /// The round ✕, beside the field and as tall as it.
    static func close(screenWidth: CGFloat, field: CGRect) -> CGRect {
        let size = SearchMetrics.closeSize
        return CGRect(x: screenWidth - SearchMetrics.sideInset - size, y: field.midY - size / 2, width: size, height: size)
    }

    /// How far the keyboard lifts the field: enough to sit just above it.
    static func lift(field: CGRect, keyboardTop: CGFloat?) -> CGFloat {
        guard let keyboardTop else { return 0 }
        return min(0, keyboardTop - SearchMetrics.keyboardGap - field.maxY)
    }
}

extension CGRect {
    /// The rectangle `t` of the way from `self` to `other`.
    func interpolated(to other: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: minX + (other.minX - minX) * t, y: minY + (other.minY - minY) * t,
               width: width + (other.width - width) * t, height: height + (other.height - height) * t)
    }
}
