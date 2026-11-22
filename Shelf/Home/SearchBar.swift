import SwiftUI
import UIKit

/// The search pill and the field it warps into: one piece of glass.
///
/// At rest it is the pill above the dock, reading "Search", or page dots
/// while pages move and in edit mode. Pulling down on the Home Screen
/// stretches it toward the field, as far as the finger has gone; a tap plays
/// the same warp. The field sits on the pill's line, full width, until the
/// keyboard rises and carries it up to just above itself.
///
/// The warp is one progress, 0 the pill and 1 the field, and everything that
/// follows it (the glass's frame, the label sliding into the placeholder's
/// place, the grid fading, the wallpaper dimming, the results appearing) is
/// set from it in the same animation. Every animation starts from what is
/// on screen, so the warp can be caught, reversed or retargeted anywhere.
@MainActor
final class SearchBar: UIView, UITextFieldDelegate {
    /// What fades with the warp, owned by the stage.
    struct Fades {
        /// The grid and the dock.
        var home: UIView
        var results: UIView
        var dim: UIView
    }

    var onTapPill: () -> Void = {}
    var onQuery: (String) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    /// The field's top, once the keyboard has moved it: the results end above it.
    var onFieldMoved: (CGFloat) -> Void = { _ in }

    private let fades: Fades
    /// Lifted by the keyboard. The warp happens inside it.
    private let ride = UIView()
    private let glass = UIVisualEffectView()
    /// The magnifier and "Search": the pill's label, which becomes the
    /// field's placeholder. Drawn at the field's size and scaled down to the
    /// pill's, so the text is never scaled up.
    private let label = UIView()
    private let pillRow = LabelRow()
    private let fieldRow = LabelRow()
    private let dots = DotsView()
    private let field = UITextField()

    private var geometry: HomeGeometry?
    /// Where the warp is headed: open (the field) or not (the pill).
    private(set) var isOpen = false
    private var pullStart: CGFloat = 0
    private var keyboardTop: CGFloat?
    private var showsDots = false
    private var dotCount = 1
    private var bodyFont = UIFont.preferredFont(forTextStyle: .body)
    private var pillScale: CGFloat = 1

    init(fades: Fades) {
        self.fades = fades
        super.init(frame: .zero)
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
        label.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
        label.addSubview(pillRow)
        label.addSubview(fieldRow)
        ride.addSubview(label)

        field.delegate = self
        field.returnKeyType = .go
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.clearButtonMode = .whileEditing
        field.adjustsFontForContentSizeCategory = true
        field.accessibilityLabel = String(localized: "Search")
        field.alpha = 0
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        ride.addSubview(field)

        maximumContentSizeCategory = .extraExtraExtraLarge
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) { (bar: SearchBar, _) in
            bar.restyle()
        }
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Only the glass and the field take touches; the rest of the Home
    // Screen is under this view.
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
        UIView.performWithoutAnimation {
            placeField()
            place(isOpen ? 1 : 0)
        }
    }

    /// Everything that follows the warp, at progress `p`.
    private func place(_ p: CGFloat) {
        let pill = pill
        let field = fieldFrame
        glass.frame = pill.interpolated(to: field, p)
        dots.center = CGPoint(x: glass.bounds.midX, y: glass.bounds.midY)

        let scale = pillScale + (1 - pillScale) * p
        label.transform = CGAffineTransform(scaleX: scale, y: scale)
        let start = CGPoint(x: pill.midX - pillRow.bounds.width * pillScale / 2, y: pill.midY)
        let end = CGPoint(x: field.minX + HomeMetrics.searchSideInset, y: field.midY)
        label.center = CGPoint(x: start.x + (end.x - start.x) * p, y: start.y + (end.y - start.y) * p)
        pillRow.alpha = 1 - p
        fieldRow.alpha = p

        fades.home.alpha = 1 - p
        fades.results.alpha = p
        fades.dim.alpha = p * HomeMetrics.searchDim
    }

    private func placeField() {
        let frame = fieldFrame
        let leading = HomeMetrics.searchSideInset + fieldRow.textStart
        field.frame = CGRect(x: frame.minX + leading, y: frame.minY,
                             width: frame.width - leading - HomeMetrics.searchTextTrailing, height: frame.height)
    }

    /// How far along the warp the glass is on screen now.
    private var shownProgress: CGFloat {
        let width = (glass.layer.presentation() ?? glass.layer).bounds.width
        return SearchWarp.progress(width: width, pill: pill, field: fieldFrame)
    }

    private var moving: [UIView] { [glass, label, pillRow, fieldRow, field] }
    private var fading: [UIView] { [fades.home, fades.results, fades.dim] }

    // MARK: Opening and closing

    /// Warps to the field from wherever the glass is, and raises the keyboard
    /// with it. `velocity` is in warps per second.
    func open(velocity: CGFloat = 0) {
        isOpen = true
        field.text = ""
        textChanged()
        setDots(false, animated: true)
        warp(to: 1, velocity: velocity)
        field.becomeFirstResponder()
        interactionChanged()
    }

    /// Warps back to the pill from wherever the glass is.
    func close(velocity: CGFloat = 0) {
        isOpen = false
        field.resignFirstResponder()
        warp(to: 0, velocity: velocity)
        interactionChanged()
    }

    private func warp(to target: CGFloat, velocity: CGFloat) {
        let distance = target - shownProgress
        let springVelocity = abs(distance) > .ulpOfOne ? velocity / distance : 0
        UIView.retarget(moving, fading: fading, Motion.searchWarp, velocity: springVelocity) {
            self.place(target)
            self.field.alpha = target
        }
    }

    private func interactionChanged() {
        fades.home.isUserInteractionEnabled = !isOpen
        fades.results.isUserInteractionEnabled = isOpen
        glass.accessibilityElementsHidden = isOpen
    }

    // MARK: Pulling

    /// A pull down on the Home Screen has begun: the warp stops where it is
    /// on screen, and follows the finger from there.
    func beginPull() {
        moving.forEach { $0.freezeOnScreen() }
        fading.forEach { $0.freezeOpacityOnScreen() }
        pullStart = shownProgress
        setDots(false, animated: true)
    }

    func pull(_ distance: CGFloat) {
        let p = SearchWarp.progress(pull: distance, from: pullStart)
        UIView.performWithoutAnimation { place(p) }
    }

    /// The pull has been let go of, moving down at `velocity` (pt/s).
    /// Returns whether search opened.
    func endPull(velocity: CGFloat) -> Bool {
        let p = shownProgress
        let warpVelocity = velocity / HomeMetrics.searchPullDistance
        if SearchWarp.opens(progress: p, velocity: velocity) {
            open(velocity: warpVelocity)
            return true
        }
        warp(to: 0, velocity: warpVelocity)
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
            if !isOpen, shownProgress == 0 {
                UIView.retarget([glass], Motion.pillResize) { self.place(0) }
            }
        } else {
            change()
            UIView.performWithoutAnimation { place(isOpen ? 1 : 0) }
        }
        glass.accessibilityLabel = shown ? String(localized: "Page \(dots.current + 1) of \(dotCount)") : String(localized: "Search")
    }

    // MARK: The field

    /// Light or dark text, after what sits behind the field.
    func setTone(_ tone: ColorScheme) {
        let ink: UIColor = tone == .dark ? .white : .black
        field.textColor = ink
        field.tintColor = ink
        field.keyboardAppearance = tone == .dark ? .dark : .light
        fieldRow.color = ink.withAlphaComponent(HomeMetrics.searchPlaceholderOpacity)
    }

    /// Where the field will be once the keyboard has lifted it, as far as
    /// is known: for working out what is behind it.
    var restingField: CGRect {
        fieldFrame.offsetBy(dx: 0, dy: SearchWarp.lift(field: fieldFrame, keyboardTop: keyboardTop))
    }

    @objc private func tapped() { onTapPill() }

    @objc private func textChanged() {
        let text = field.text ?? ""
        fieldRow.showsText = text.isEmpty
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
        let glassEffect = UIGlassEffect(style: .clear)
        if traitCollection.userInterfaceStyle == .dark {
            glassEffect.tintColor = UIColor(HomeMetrics.darkGlassTint)
        }
        glassEffect.isInteractive = true
        glass.effect = glassEffect

        let category = min(traitCollection.preferredContentSizeCategory, .extraExtraExtraLarge)
        bodyFont = UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
        // Springboard's pill keeps its size at every text size.
        let pillFont = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        pillScale = pillFont.pointSize / bodyFont.pointSize
        let medium = UIFont.systemFont(ofSize: bodyFont.pointSize, weight: .medium)
        pillRow.configure(font: medium, symbolScale: .small, symbolWeight: .bold,
                          gap: HomeMetrics.pillGlyphGap / pillScale,
                          color: .white.withAlphaComponent(HomeMetrics.pillTextOpacity))
        fieldRow.configure(font: bodyFont, symbolScale: .medium, symbolWeight: .regular,
                           gap: HomeMetrics.searchGlyphGap, color: fieldRow.color)
        field.font = bodyFont
        label.bounds = CGRect(x: 0, y: 0, width: max(pillRow.bounds.width, fieldRow.bounds.width),
                              height: max(pillRow.bounds.height, fieldRow.bounds.height))
        for row in [pillRow, fieldRow] {
            row.center = CGPoint(x: row.bounds.width / 2, y: label.bounds.midY)
        }
        dots.layoutDots()
        let shown = isOpen ? CGFloat(1) : 0
        UIView.performWithoutAnimation {
            placeField()
            place(shown)
        }
    }
}

/// A magnifier and "Search", laid out at their natural size.
private final class LabelRow: UIView {
    private let glyph = UIImageView()
    private let text = UILabel()
    /// Where the text starts, from the row's leading edge.
    private(set) var textStart: CGFloat = 0
    var color: UIColor = .white {
        didSet {
            glyph.tintColor = color
            text.textColor = color
        }
    }
    var showsText = true {
        didSet { text.isHidden = !showsText }
    }

    init() {
        super.init(frame: .zero)
        text.text = String(localized: "Search")
        addSubview(glyph)
        addSubview(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(font: UIFont, symbolScale: UIImage.SymbolScale, symbolWeight: UIImage.SymbolWeight, gap: CGFloat, color: UIColor) {
        let configuration = UIImage.SymbolConfiguration(font: font, scale: symbolScale)
            .applying(UIImage.SymbolConfiguration(weight: symbolWeight))
        glyph.image = UIImage(systemName: "magnifyingglass", withConfiguration: configuration)
        glyph.sizeToFit()
        text.font = font
        text.sizeToFit()
        let height = max(glyph.bounds.height, text.bounds.height)
        glyph.center = CGPoint(x: glyph.bounds.width / 2, y: height / 2)
        textStart = glyph.bounds.width + gap
        text.frame.origin = CGPoint(x: textStart, y: (height - text.bounds.height) / 2)
        bounds = CGRect(x: 0, y: 0, width: textStart + text.bounds.width, height: height)
        self.color = color
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
    /// How far along the warp a pull of `pull` points takes it, from `start`.
    static func progress(pull: CGFloat, from start: CGFloat) -> CGFloat {
        min(max(start + pull / HomeMetrics.searchPullDistance, 0), 1)
    }

    /// Whether a pull let go of at `progress`, moving down at `velocity`
    /// (pt/s), opens search.
    static func opens(progress: CGFloat, velocity: CGFloat) -> Bool {
        if velocity > HomeMetrics.searchOpenVelocity { return true }
        if velocity < -HomeMetrics.searchOpenVelocity { return false }
        return progress > HomeMetrics.searchOpenProgress
    }

    /// The field before the keyboard lifts it: full width, on the pill's line.
    static func field(screenWidth: CGFloat, pill: CGRect) -> CGRect {
        let height = HomeMetrics.searchFieldHeight
        return CGRect(x: HomeMetrics.searchSideInset, y: pill.midY - height / 2,
                      width: screenWidth - 2 * HomeMetrics.searchSideInset, height: height)
    }

    /// How far the keyboard lifts the field: enough to sit just above it.
    static func lift(field: CGRect, keyboardTop: CGFloat?) -> CGFloat {
        guard let keyboardTop else { return 0 }
        return min(0, keyboardTop - HomeMetrics.searchKeyboardGap - field.maxY)
    }

    /// How far along the warp a glass `width` wide is.
    static func progress(width: CGFloat, pill: CGRect, field: CGRect) -> CGFloat {
        let span = field.width - pill.width
        guard span > 0 else { return 0 }
        return min(max((width - pill.width) / span, 0), 1)
    }
}

extension CGRect {
    /// The rectangle `t` of the way from `self` to `other`.
    func interpolated(to other: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: minX + (other.minX - minX) * t, y: minY + (other.minY - minY) * t,
               width: width + (other.width - width) * t, height: height + (other.height - height) * t)
    }
}
