import UIKit

// PRIVATE API. Everything Shelf uses that Apple doesn't publish is in this
// file and nowhere else:
//
// - `CABackdropLayer`, a layer that draws what is behind it in the window,
//   which is what `UIVisualEffectView` is built on;
// - `CAFilter` with the `gaussianBlur` and `colorMatrix` types, set as its
//   `filters`, with the blur's `inputRadius` and `inputNormalizeEdges` and
//   the matrix's `inputColorMatrix` (a `CAColorMatrix`, 20 floats).
//
// Why: search's backdrop is the Home Screen blurred and darkened by an amount
// that follows the finger (PLAN.md §0.3), and App Library's is a Gaussian
// blur with a 40 pt standard deviation (`SearchMetrics.blurSigma`). A
// `UIBlurEffect` has one fixed radius per style and a tint of its own, and
// the only public way to blur by less is to scrub a paused animator, which
// gives no control of the radius. These filters give exactly the measured
// blur, at any point of the pull.
//
// If either class is ever missing, the backdrop draws nothing and search sits
// over a plain dim instead (`BackdropView.isBlurring` is false).

/// The Home Screen behind search, blurred by `radius` and its colours
/// scaled and offset, all set at once every frame of the warp.
@MainActor
final class BackdropView: UIView {
    override class var layerClass: AnyClass {
        NSClassFromString("CABackdropLayer") ?? CALayer.self
    }

    private let blur = BackdropView.filter("gaussianBlur")
    private let colors = BackdropView.filter("colorMatrix")
    /// Stands in when the private classes aren't there.
    private let fallbackDim = CALayer()

    /// Whether this is the real backdrop, blurring what's behind it.
    let isBlurring: Bool

    override init(frame: CGRect) {
        isBlurring = NSClassFromString("CABackdropLayer") != nil && blur != nil && colors != nil
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        if isBlurring, let blur, let colors {
            blur.setValue(true, forKey: "inputNormalizeEdges")
            // The blur happens on a quarter-size copy: a 40 pt deviation
            // loses nothing to it, and the GPU does a sixteenth of the work.
            layer.setValue(0.25, forKey: "scale")
            layer.filters = [blur, colors]
        } else {
            fallbackDim.backgroundColor = UIColor.black.cgColor
            layer.addSublayer(fallbackDim)
        }
        set(radius: 0, scale: 1, offset: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        withoutActions { fallbackDim.frame = bounds }
    }

    /// Blurs by `radius` (a standard deviation, in points), then makes each
    /// channel `scale` × itself + `offset` (in 0...1). A backdrop at rest
    /// (radius 0, scale 1, offset 0) is hidden, so it costs nothing.
    func set(radius: CGFloat, scale: CGFloat, offset: CGFloat) {
        let resting = radius <= 0.01 && abs(scale - 1) < 0.001 && abs(offset) < 0.001
        withoutActions {
            layer.isHidden = resting
            guard isBlurring else {
                // Nothing to blur with: a dim that darkens about as much.
                fallbackDim.opacity = Float(1 - scale - offset)
                return
            }
            layer.setValue(radius * Self.radiusPerSigma, forKeyPath: "filters.gaussianBlur.inputRadius")
            var matrix = ColorMatrix(scale: Float(scale), offset: Float(offset))
            let value = NSValue(bytes: &matrix, objCType: ColorMatrix.objCType)
            layer.setValue(value, forKeyPath: "filters.colorMatrix.inputColorMatrix")
        }
    }

    /// Core Animation's `inputRadius` for a Gaussian of one point's standard
    /// deviation. Calibrated on the simulator by fitting a capture of
    /// Shelf's backdrop the same way App Library's was fitted.
    static let radiusPerSigma: CGFloat = 1

    private static func filter(_ type: String) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let make = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: make) else { return nil }
        let filter = filterClass.perform(make, with: type)?.takeUnretainedValue() as? NSObject
        filter?.setValue(type, forKey: "name")
        return filter
    }
}

/// `CAColorMatrix`: four rows of five, red, green, blue and alpha out, each
/// a sum of red, green, blue and alpha in plus an offset.
private struct ColorMatrix {
    var m11: Float, m12: Float, m13: Float, m14: Float, m15: Float
    var m21: Float, m22: Float, m23: Float, m24: Float, m25: Float
    var m31: Float, m32: Float, m33: Float, m34: Float, m35: Float
    var m41: Float, m42: Float, m43: Float, m44: Float, m45: Float

    static let objCType = "{CAColorMatrix=ffffffffffffffffffff}"

    /// Each colour channel times `scale`, plus `offset`; alpha untouched.
    init(scale: Float, offset: Float) {
        (m11, m12, m13, m14, m15) = (scale, 0, 0, 0, offset)
        (m21, m22, m23, m24, m25) = (0, scale, 0, 0, offset)
        (m31, m32, m33, m34, m35) = (0, 0, scale, 0, offset)
        (m41, m42, m43, m44, m45) = (0, 0, 0, 1, 0)
    }
}
