import UIKit

/// An icon's long-press menu: a glass panel of actions beside the lifted
/// icon, as Springboard's (`longpress-menu-grid-photos.png`).
///
/// It is Shelf's own, not `UIContextMenuInteraction`'s: once that menu is
/// up, UIKit cancels the touch for every other recognizer, the window's
/// included, so a finger that moves on could never carry the icon into a
/// drag (PLAN.md §0.2, step 1). Here the touch stays Shelf's throughout.
final class IconMenuView: UIView {
    private let glass = UIVisualEffectView()
    private let stack = UIView()
    private var rows: [MenuRow] = []
    private var separators: [UIView] = []
    /// Rows and the lines between groups, top to bottom.
    private var items: [UIView] = []
    private var font = UIFont.preferredFont(forTextStyle: .body)
    var onAction: (IconAction) -> Void = { _ in }

    /// `groups` in reading order; a menu that opens upward lists them the
    /// other way, so the first action is always the one nearest the icon.
    init(groups: [[IconAction]], upward: Bool) {
        super.init(frame: .zero)
        glass.cornerConfiguration = .corners(radius: .fixed(HomeMetrics.menuCornerRadius))
        glass.effect = UIGlassEffect(style: .regular)
        addSubview(glass)
        glass.contentView.addSubview(stack)
        maximumContentSizeCategory = UIContentSizeCategory(ShelfMetrics.textSizeCap)
        let ordered = upward ? groups.reversed().map { $0.reversed() } : groups
        for (index, group) in ordered.enumerated() {
            if index > 0 {
                let line = UIView()
                line.backgroundColor = .separator
                stack.addSubview(line)
                separators.append(line)
                items.append(line)
            }
            for action in group {
                let row = MenuRow(action: action)
                row.addTarget(self, action: #selector(chose(_:)), for: .touchUpInside)
                stack.addSubview(row)
                rows.append(row)
                items.append(row)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var rowHeight: CGFloat {
        UIFontMetrics(forTextStyle: .body).scaledValue(for: HomeMetrics.menuRowHeight, compatibleWith: traitCollection)
    }

    /// The menu's size at the current text size.
    var fittingSize: CGSize {
        let separatorsHeight = CGFloat(separators.count) * HomeMetrics.menuSectionGap
        return CGSize(width: HomeMetrics.menuWidth,
                      height: 2 * HomeMetrics.menuPadding + CGFloat(rows.count) * rowHeight + separatorsHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        stack.frame = bounds
        var y = HomeMetrics.menuPadding
        let pixel = 1 / max(traitCollection.displayScale, 1)
        for item in items {
            if item is MenuRow {
                item.frame = CGRect(x: 0, y: y, width: bounds.width, height: rowHeight)
                y += rowHeight
            } else {
                item.frame = CGRect(x: 0, y: y + HomeMetrics.menuSectionGap / 2 - pixel / 2, width: bounds.width, height: pixel)
                y += HomeMetrics.menuSectionGap
            }
        }
    }

    @objc private func chose(_ row: MenuRow) {
        onAction(row.action)
    }

    // MARK: Where it goes

    /// Where a menu of `size` goes beside an icon lifted to `icon`, inside
    /// `area` (the screen less its safe areas): below the icon with their
    /// leading edges in line, or above it (a dock icon's, one low on the
    /// screen) when there is no room below. It keeps to the icon's trailing
    /// edge when its leading one would run off the screen.
    static func placement(size: CGSize, icon: CGRect, area: CGRect) -> (frame: CGRect, upward: Bool) {
        let gap = HomeMetrics.menuGap
        let upward = icon.maxY + gap + size.height > area.maxY && icon.minY - gap - size.height >= area.minY
        let y = upward ? icon.minY - gap - size.height : min(icon.maxY + gap, area.maxY - size.height)
        let margin = HomeMetrics.menuMargin
        var x = icon.minX
        if x + size.width > area.maxX - margin { x = icon.maxX - size.width }
        x = min(max(x, area.minX + margin), area.maxX - margin - size.width)
        return (CGRect(x: x, y: y, width: size.width, height: size.height), upward)
    }
}

/// One action: its glyph, then its title. It highlights under a finger.
private final class MenuRow: UIControl {
    let action: IconAction
    private let glyph = UIImageView()
    private let title = UILabel()
    private let highlight = UIView()

    init(action: IconAction) {
        self.action = action
        super.init(frame: .zero)
        isEnabled = action.isEnabled
        highlight.backgroundColor = .tertiarySystemFill
        highlight.alpha = 0
        highlight.isUserInteractionEnabled = false
        addSubview(highlight)
        let color: UIColor = !action.isEnabled ? .tertiaryLabel : action.isDestructive ? .systemRed : .label
        title.text = action.title
        title.font = .preferredFont(forTextStyle: .body)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = color
        glyph.image = UIImage(systemName: action.symbol,
                              withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .medium))
        glyph.tintColor = color
        glyph.contentMode = .center
        addSubview(glyph)
        addSubview(title)
        accessibilityLabel = action.title
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: isHighlighted ? 0 : Motion.fadeDuration) {
                self.highlight.alpha = self.isHighlighted ? 1 : 0
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds
        glyph.sizeToFit()
        glyph.center = CGPoint(x: HomeMetrics.menuGlyphCenter, y: bounds.midY)
        let start = HomeMetrics.menuTextStart
        title.frame = CGRect(x: start, y: 0, width: bounds.width - start - HomeMetrics.menuTrailing, height: bounds.height)
    }
}
