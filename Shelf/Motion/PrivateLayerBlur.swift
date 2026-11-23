import QuartzCore

/// PRIVATE API, and the only place Shelf uses it: Core Animation's own
/// Gaussian blur filter (`CAFilter`, type "gaussianBlur"), which UIKit and
/// Springboard use but iOS doesn't publish.
///
/// Why: behind a closing card, Springboard's Home Screen is blurred with a
/// real radius that shrinks as the card lands (about 20 points while the
/// card is most of the screen, 8 at twice the icon's size, none once it has
/// landed; measured in `design/reference/springboard/README.md`). The public
/// blur, `UIVisualEffectView`, has one fixed radius per style and can only be
/// faded in and out, which reads as a sharp Home Screen under a frosted
/// pane, not as one coming into focus.
///
/// Looked up by name, and failing soft: if the class or the filter ever goes
/// away, `isAvailable` is false and the stage falls back to the public blur.
@MainActor
enum PrivateLayerBlur {
    private static let filterClass = NSClassFromString("CAFilter") as? NSObject.Type
    private static let make = NSSelectorFromString("filterWithType:")
    private static let name = "shelfBlur"

    static let isAvailable: Bool = makeFilter() != nil

    private static func makeFilter() -> NSObject? {
        guard let filterClass, filterClass.responds(to: make) else { return nil }
        guard let filter = filterClass.perform(make, with: "gaussianBlur")?.takeUnretainedValue() as? NSObject else {
            return nil
        }
        filter.setValue(name, forKey: "name")
        // Edges blur against themselves, not against transparency, so the
        // Home Screen's edges don't darken.
        filter.setValue(true, forKey: "inputNormalizeEdges")
        return filter
    }

    /// Blurs `layer` and everything in it by `radius` points; none at 0.
    /// Call inside a transaction with actions disabled.
    static func setRadius(_ radius: CGFloat, on layer: CALayer) {
        guard isAvailable else { return }
        if radius < 0.05 {
            if layer.filters != nil { layer.filters = nil }
            return
        }
        if layer.filters == nil, let filter = makeFilter() {
            layer.filters = [filter]
        }
        layer.setValue(radius, forKeyPath: "filters.\(name).inputRadius")
    }
}
