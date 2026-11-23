import SwiftUI
import UIKit

/// The icon's artwork in Core Animation: the tile's gradient, the glyph, the
/// rim, and the pressed and downloading states, all on the icon's outline.
/// No label, no badge. The one icon renderer: the grid and the dock draw it
/// inside an `IconView`, an app's card draws its face with it (`CardFaceView`),
/// and sheets embed it through `IconImage`.
///
/// Its bounds are centred on its own origin, so every layer in it sits at
/// (0, 0) and stays centred while the outline changes (a card growing out
/// of its icon) with nothing of its own to keep in step: the outline's
/// layers take new paths and bounds, and the glyph and the pie keep their
/// size (a card's face scales its glyph with the card, `fitArt`).
///
/// The outline is a path, not a layer's `cornerRadius`: Core Animation's
/// continuous corner is rounder than Springboard's by up to 6 pixels at 3x,
/// and SwiftUI's continuous rounded rectangle at `iconCornerRatio` is
/// Springboard's to the pixel (`design/reference/README.md`).
class IconArtView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    /// The side the glyph and the pie are drawn for: the icon's size, which
    /// a card's face keeps as it grows.
    let iconSize: CGFloat
    var face: IconFace {
        didSet { if face != oldValue { repaint() } }
    }

    private var tile: CAGradientLayer { layer as! CAGradientLayer }
    /// The outline, which clips the tile and everything in it.
    private let tileMask = CAShapeLayer()
    private let glyph = CALayer()
    /// The bright edge Liquid Glass icons carry, painted through a mask
    /// that is only the outline's border.
    private let rim = CAGradientLayer()
    private let rimEdge = CAShapeLayer()
    private let pendingDim = CAShapeLayer()
    private let pie = InstallPieLayer()
    private let pressed = CAShapeLayer()

    private var isPending = false
    private var isSlow = false
    private var slowTask: Task<Void, Never>?
    private var wasDownloading = false

    init(face: IconFace, iconSize: CGFloat) {
        self.face = face
        self.iconSize = iconSize
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        tile.startPoint = CGPoint(x: 0.5, y: 0)
        tile.endPoint = CGPoint(x: 0.5, y: 1)
        tileMask.fillColor = UIColor.black.cgColor
        tile.mask = tileMask

        rim.colors = [UIColor.white.withAlphaComponent(HomeMetrics.rimOpacity).cgColor,
                      UIColor.white.withAlphaComponent(0).cgColor,
                      UIColor.white.withAlphaComponent(HomeMetrics.rimReturnOpacity).cgColor]
        rim.locations = [0, 0.5, 1]
        rimEdge.lineWidth = HomeMetrics.rimWidth
        rimEdge.strokeColor = UIColor.black.cgColor
        rimEdge.fillColor = nil
        rim.mask = rimEdge

        pendingDim.fillColor = UIColor.black.withAlphaComponent(HomeMetrics.pendingDim).cgColor
        pendingDim.opacity = 0
        pie.opacity = 0
        pressed.fillColor = UIColor.black.cgColor
        pressed.opacity = 0

        for sublayer in [glyph, rim, pendingDim, pie, pressed] as [CALayer] {
            sublayer.position = .zero
            layer.addSublayer(sublayer)
        }
        tileMask.position = .zero
        rimEdge.position = .zero
        pie.configure(side: iconSize * HomeMetrics.pieRatio)
        setOutline(CGSize(width: iconSize, height: iconSize))

        registerForTraitChanges([IconToneTrait.self, UITraitUserInterfaceStyle.self, UITraitDisplayScale.self]) { (art: IconArtView, _) in
            art.repaint()
        }
        repaint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Painting

    private func repaint() {
        let palette = IconPalette(face, tone: traitCollection.iconTone)
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 3
        withoutActions {
            tile.colors = [palette.top.cgColor, palette.bottom.cgColor]
            glyph.contents = IconGlyph.image(face.symbol, iconSize: iconSize, color: palette.glyph, scale: scale).cgImage
            glyph.contentsScale = scale
            glyph.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
            pie.contentsScale = scale
        }
    }

    // MARK: The outline

    /// The gradients that fill the outline's bounds.
    private var boundedLayers: [CALayer] { [layer, rim] }

    /// Each shape layer and its path for an outline of `size`, with corners
    /// of `radius`.
    private func paths(_ size: CGSize, radius: CGFloat) -> [(CAShapeLayer, CGPath)] {
        let rect = Self.centered(size)
        let outline = IconPath.path(rect, radius: radius)
        let edge = HomeMetrics.rimWidth / 2
        return [(tileMask, outline), (pendingDim, outline), (pressed, outline),
                // The rim is stroked inside the outline, as `strokeBorder` does.
                (rimEdge, IconPath.path(rect.insetBy(dx: edge, dy: edge), radius: radius - edge))]
    }

    /// The outline, at once: `size` across with corners of `radius` (an
    /// icon's, unless this is a card's face on its way to full screen).
    func setOutline(_ size: CGSize, radius: CGFloat? = nil) {
        let radius = radius ?? HomeMetrics.iconRadius(size.width)
        let bounds = Self.centered(size)
        withoutActions {
            for bounded in boundedLayers {
                bounded.removeAnimation(forKey: "bounds")
                bounded.bounds = bounds
            }
            for (shape, path) in paths(size, radius: radius) {
                shape.removeAnimation(forKey: "path")
                shape.path = path
            }
        }
    }

    /// Scales the glyph for an outline of `size` without changing its
    /// shape, as Springboard's card does: only the tile's fill stretches to
    /// the card. The glyph is as big as the outline's width makes it, where
    /// it would be on a square icon at the outline's top, as the app's
    /// picture on a card is drawn from its top. An icon's glyph is drawn at
    /// its size.
    func fitArt(to size: CGSize) {
        let scale = size.width / iconSize
        let y = (size.width - size.height) / 2
        withoutActions {
            glyph.transform = CATransform3DScale(CATransform3DMakeTranslation(0, min(y, 0), 0), scale, scale, 1)
        }
    }

    static func centered(_ size: CGSize) -> CGRect {
        CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    }

    // MARK: States

    /// Touch-down lays black over the whole tile, glyph included, at once;
    /// the release eases it off. Darkening by multiplying, as Springboard
    /// does, keeps the glyph and the fill in proportion instead of greying
    /// them. The tile never scales.
    func setPressed(_ isPressed: Bool) {
        if isPressed {
            withoutActions {
                pressed.removeAnimation(forKey: "opacity")
                pressed.opacity = Float(HomeMetrics.pressedDim)
            }
        } else if pressed.opacity != 0 {
            pressed.spring("opacity", to: Float(0), Motion.release)
        }
    }

    /// An icon whose source may still be on the way. While it is, the tile
    /// darkens and the install pie takes the glyph's place, so the two never
    /// draw over each other.
    ///
    /// A brand-new app has nothing else to show, so its pie appears at once.
    /// An update to an app that already runs shows nothing unless it is slow.
    func setPending(isRunnable: Bool, isDownloading: Bool) {
        if isDownloading != wasDownloading {
            wasDownloading = isDownloading
            slowTask?.cancel()
            if isDownloading {
                // The real size is a few kilobytes, gone in one packet, so the pie
                // creeps toward full and finishes when the download does.
                pie.creep()
                slowTask = Task { [weak self] in
                    try? await Task.sleep(for: Motion.spinnerDelay)
                    guard !Task.isCancelled, let self else { return }
                    self.isSlow = true
                    self.showPending(!isRunnable || self.isSlow)
                }
            } else {
                isSlow = false
                pie.finish(at: isRunnable ? 1 : 0)
            }
        }
        showPending(!isRunnable || (isDownloading && isSlow))
    }

    private func showPending(_ pending: Bool) {
        guard pending != isPending else { return }
        isPending = pending
        let fade = CABasicAnimation()
        fade.duration = Motion.fadeDuration * Motion.Spring.slowdown
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        for (sublayer, shown) in [(pendingDim, pending), (pie, pending), (glyph, !pending)] {
            let from = sublayer.presentation()?.opacity ?? sublayer.opacity
            let to: Float = shown ? 1 : 0
            sublayer.opacity = to
            let animation = fade.copy() as! CABasicAnimation
            animation.keyPath = "opacity"
            animation.fromValue = from
            animation.toValue = to
            sublayer.add(animation, forKey: "opacity")
        }
    }

    var showsPending: Bool { isPending }
}

/// The App Store install state: a ring with a pie filling inside it.
final class InstallPieLayer: CALayer {
    private let ring = CAShapeLayer()
    private let slice = CAShapeLayer()

    override init() {
        super.init()
        addSublayer(ring)
        addSublayer(slice)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(side: CGFloat) {
        bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let center = CGPoint(x: side / 2, y: side / 2)
        let width = HomeMetrics.pieRingWidth
        ring.frame = bounds
        ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: width / 2, dy: width / 2)).cgPath
        ring.lineWidth = width
        ring.strokeColor = UIColor.white.cgColor
        ring.fillColor = nil

        // A wedge is a circle stroked as wide as its radius, so the stroke's
        // end draws it, and Core Animation can move that end on its own.
        let radius = side / 2 - HomeMetrics.pieInset
        slice.frame = bounds
        slice.path = UIBezierPath(arcCenter: center, radius: radius / 2, startAngle: -.pi / 2,
                                  endAngle: 3 * .pi / 2, clockwise: true).cgPath
        slice.lineWidth = radius
        slice.strokeColor = UIColor.white.cgColor
        slice.fillColor = nil
        slice.strokeEnd = 0
    }

    override var contentsScale: CGFloat {
        didSet {
            ring.contentsScale = contentsScale
            slice.contentsScale = contentsScale
        }
    }

    /// From empty toward nearly full, slowing as it goes.
    @MainActor
    func creep() {
        withoutActions {
            slice.removeAllAnimations()
            slice.strokeEnd = CGFloat(Motion.pieCreepTarget)
        }
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = Motion.pieCreepTarget
        animation.duration = Motion.pieCreepDuration * Motion.Spring.slowdown
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        slice.add(animation, forKey: "strokeEnd")
    }

    /// The download is over: full if it worked, empty if not.
    @MainActor
    func finish(at progress: CGFloat) {
        slice.spring("strokeEnd", to: progress, Motion.pieFill)
    }
}

/// The icon's outline as a path: Springboard's, which is SwiftUI's continuous
/// rounded rectangle (with corners `iconCornerRatio` of the side, for an icon).
enum IconPath {
    static func path(_ rect: CGRect, radius: CGFloat) -> CGPath {
        RoundedRectangle(cornerRadius: max(radius, 0), style: .continuous).path(in: rect).cgPath
    }
}
