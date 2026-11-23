import UIKit

/// App Library's index: A to Z and # down the trailing edge, every letter
/// always, white. A finger on it jumps to that letter's section and
/// scrubbing moves on letter by letter, with a selection tick at each.
///
/// Shelf's own rather than the collection view's: that one has no public
/// way to colour it or set its letters' size and pitch, and App Library's
/// is white over the dark backdrop, 10.4 pt semibold on a 13.27 pt pitch.
final class SearchIndexView: UIControl {
    /// A letter was touched or scrubbed onto.
    var onSelect: (String) -> Void = { _ in }

    private let titles = SearchSections.indexTitles
    private var labels: [UILabel] = []
    private(set) var touchedTitle: String?
    private lazy var tick = UISelectionFeedbackGenerator(view: self)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let font = UIFont.systemFont(ofSize: SearchMetrics.indexFontSize, weight: SearchMetrics.indexWeight)
        for title in titles {
            let label = UILabel()
            label.text = title
            label.font = font
            label.textColor = .white
            label.textAlignment = .center
            label.isUserInteractionEnabled = false
            addSubview(label)
            labels.append(label)
        }
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Section index")
        accessibilityTraits = .adjustable
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The letters' pitch: App Library's, closer when the height is short
    /// (the keyboard up on a small phone).
    private var pitch: CGFloat {
        min(SearchMetrics.indexPitch, bounds.height / CGFloat(titles.count))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pitch = pitch
        let top = bounds.midY - pitch * CGFloat(titles.count) / 2
        for (index, label) in labels.enumerated() {
            label.frame = CGRect(x: 0, y: top + CGFloat(index) * pitch, width: bounds.width, height: pitch)
        }
    }

    /// The letter at `y`, the nearest one past either end.
    func title(at y: CGFloat) -> String {
        let pitch = pitch
        let top = bounds.midY - pitch * CGFloat(titles.count) / 2
        let index = Int(((y - top) / pitch).rounded(.down))
        return titles[min(max(index, 0), titles.count - 1)]
    }

    // MARK: Touches

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        touchedTitle = nil
        tick.prepare()
        choose(touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        choose(touch)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        touchedTitle = nil
    }

    override func cancelTracking(with event: UIEvent?) {
        touchedTitle = nil
    }

    private func choose(_ touch: UITouch) {
        let title = title(at: touch.location(in: self).y)
        guard title != touchedTitle else { return }
        tick.selectionChanged(at: touch.location(in: self))
        touchedTitle = title
        onSelect(title)
    }

    // A finger's width, though the letters are narrow.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let extra = max(SearchMetrics.indexHitWidth - bounds.width, 0)
        return bounds.insetBy(dx: -extra / 2, dy: 0).contains(point)
    }

    // MARK: VoiceOver

    private var accessibleIndex = 0

    override func accessibilityIncrement() {
        accessibleIndex = min(accessibleIndex + 1, titles.count - 1)
        onSelect(titles[accessibleIndex])
        accessibilityValue = titles[accessibleIndex]
    }

    override func accessibilityDecrement() {
        accessibleIndex = max(accessibleIndex - 1, 0)
        onSelect(titles[accessibleIndex])
        accessibilityValue = titles[accessibleIndex]
    }
}
