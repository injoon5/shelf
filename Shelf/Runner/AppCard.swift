import SwiftUI
import UIKit

/// What an open app's SwiftUI side needs from its card.
@MainActor
@Observable
final class CardState {
    /// The open has come to rest. Kiln parses on the main thread, so the app
    /// is built only after this: never while anything is moving.
    var isSettled = false
}

/// The app inside a card.
struct CardRoot: View {
    var run: HomeModel.Run
    var state: CardState

    var body: some View {
        // The card's own face is the launch screen, so the stage shows
        // nothing of its own until the app is built.
        AppStage(app: run.app.meta, source: run.source, store: .synced,
                 isReady: state.isSettled, showsLaunchScreen: false)
    }
}

/// How an app's icon is painted, for its card: the same fill and glyph as
/// `IconArt`, so a card at icon size is the icon and a card at full screen
/// is the app's launch screen, and every size between is both.
struct CardFace {
    var top: UIColor
    var bottom: UIColor
    var glyph: UIColor
    var symbol: String
    var glyphSize: CGFloat

    @MainActor
    init(_ face: IconFace, style: IconStyle, dark: Bool, iconSize: CGFloat) {
        var environment = EnvironmentValues()
        environment.colorScheme = dark ? .dark : .light
        func ui(_ color: Color) -> UIColor { UIColor(cgColor: color.resolve(in: environment).cgColor) }
        // Clear icons are glass, which a moving card can't be; the colour
        // icon of the same appearance stands in for them.
        if dark {
            top = ui(HomeMetrics.darkFillTop)
            bottom = ui(HomeMetrics.darkFillBottom)
            glyph = style == .color ? ui(face.tint) : .white
        } else {
            top = ui(face.tint.mix(with: .white, by: HomeMetrics.fillLift))
            bottom = ui(face.tint)
            glyph = .white
        }
        symbol = face.symbol
        glyphSize = iconSize * HomeMetrics.glyphRatio
    }
}

/// The moving part of a card: the icon's fill and glyph, with a picture of
/// the app over them.
///
/// Its bounds are kept centred on its own origin, so the glyph and the
/// picture sit at (0, 0) and stay centred while the bounds animate, with
/// no animations of their own to keep in step.
final class CardFaceView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    let glyph = UIImageView()
    /// Holds the app's picture at full-screen size, scaled to the card's width.
    let content = UIView()
    private let screen: CGSize

    init(face: CardFace, screen: CGSize) {
        self.screen = screen
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        let gradient = layer as! CAGradientLayer
        gradient.colors = [face.top.cgColor, face.bottom.cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer.cornerCurve = .continuous
        layer.masksToBounds = true

        let configuration = UIImage.SymbolConfiguration(pointSize: face.glyphSize, weight: .medium)
            .applying(UIImage.SymbolConfiguration(hierarchicalColor: face.glyph))
        glyph.image = UIImage(systemName: face.symbol, withConfiguration: configuration)
        glyph.sizeToFit()
        glyph.center = .zero
        addSubview(glyph)

        content.bounds = CGRect(origin: .zero, size: screen)
        content.center = .zero
        content.alpha = 0
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Puts the card at `frame` at once.
    func place(_ frame: CardFrame) {
        withoutActions {
            layer.position = frame.center
            layer.bounds = Self.centered(frame.size)
            layer.cornerRadius = frame.radius
            content.layer.setValue(frame.size.width / screen.width, forKeyPath: "transform.scale")
        }
    }

    /// Springs the card to `frame` from wherever it is on screen. The
    /// centre's speed is in points per second; the size's in points of
    /// width per second.
    func spring(to frame: CardFrame, _ spring: Motion.Spring, centerVelocity: CGPoint = .zero, widthVelocity: CGFloat = 0) {
        let shown = layer.presentation() ?? layer
        let sizeVelocity = CardMotion.springVelocity(widthVelocity, from: shown.bounds.width, to: frame.size.width)
        layer.spring("position.x", to: frame.center.x, spring,
                     velocity: CardMotion.springVelocity(centerVelocity.x, from: shown.position.x, to: frame.center.x))
        layer.spring("position.y", to: frame.center.y, spring,
                     velocity: CardMotion.springVelocity(centerVelocity.y, from: shown.position.y, to: frame.center.y))
        layer.spring("bounds", to: NSValue(cgRect: Self.centered(frame.size)), spring, velocity: sizeVelocity)
        layer.spring("cornerRadius", to: frame.radius, spring, velocity: sizeVelocity)
        content.layer.spring("transform.scale", to: frame.size.width / screen.width, spring, velocity: sizeVelocity)
    }

    /// Stops the card where it is on screen and returns where that is.
    func freeze() -> CardFrame {
        let shown = layer.presentation() ?? layer
        let frame = CardFrame(center: shown.position, size: shown.bounds.size, radius: shown.cornerRadius)
        layer.removeAllAnimationsDeeply()
        place(frame)
        return frame
    }

    var isMoving: Bool { layer.isAnimating || content.layer.isAnimating }

    /// Where the card's springs are headed.
    var targetFrame: CGRect {
        CGRect(x: layer.position.x - layer.bounds.width / 2, y: layer.position.y - layer.bounds.height / 2,
               width: layer.bounds.width, height: layer.bounds.height)
    }

    /// Ends the springs at their targets, which the model already holds.
    func finishMoving() {
        layer.removeAllAnimationsDeeply()
    }

    var shownFrame: CGRect {
        let shown = layer.presentation() ?? layer
        return CGRect(x: shown.position.x - shown.bounds.width / 2, y: shown.position.y - shown.bounds.height / 2,
                      width: shown.bounds.width, height: shown.bounds.height)
    }

    private static func centered(_ size: CGSize) -> CGRect {
        CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    }
}

/// One open app: a card that grows out of its icon, the live app over it
/// once it has, and back.
///
/// While the card moves, the live app stays put, full screen and hidden,
/// and the card shows a picture of it instead. So the app never lays out
/// again mid-flight (a scaled view's safe area changes every frame), and
/// its own presentations, keyboard and navigation are untouched.
@MainActor
final class AppCard {
    enum Phase {
        /// Growing to full screen (or going back there).
        case opening
        /// At rest, full screen, live.
        case open
        /// Under a finger.
        case held
        /// Shrinking into its icon.
        case closing
        /// On its icon, about to go.
        case landed
    }

    let run: HomeModel.Run
    let state = CardState()
    let host: UIHostingController<CardRoot>
    let face: CardFaceView
    private(set) var phase = Phase.opening
    /// What it was doing when a finger caught it.
    private(set) var heldFrom = Phase.open
    private(set) var landingFades = false

    private let screen: CGSize
    private let iconSize: CGFloat
    private let fullRadius: CGFloat
    private var grab: (frame: CardFrame, scale: CGFloat, finger: CGPoint, direction: CloseDirection)?
    private var travel: CGFloat = 0

    var slug: String { run.id }

    init(run: HomeModel.Run, face: CardFace, screen: CGSize, iconSize: CGFloat, fullRadius: CGFloat, from source: CGRect) {
        self.run = run
        self.screen = screen
        self.iconSize = iconSize
        self.fullRadius = fullRadius
        startProgress = CardMotion.progress(width: source.width, iconSize: iconSize, screenWidth: screen.width)
        self.face = CardFaceView(face: face, screen: screen)
        host = UIHostingController(rootView: CardRoot(run: run, state: state))
        // Clear until the app is built, so the card's face is its launch screen.
        host.view.backgroundColor = .clear
        host.view.isHidden = true
        self.face.place(CardFrame(rect: source, radius: iconSize * HomeMetrics.iconCornerRatio))
    }

    private var full: CardFrame {
        CardFrame(rect: CGRect(origin: .zero, size: screen), radius: fullRadius)
    }

    /// How open the card is on screen: 1 full screen, 0 its icon. A card
    /// added this turn of the run loop has no presentation yet, and its
    /// model already holds its target, so it is where it started.
    var progress: CGFloat {
        guard let shown = face.layer.presentation() else { return startProgress }
        return CardMotion.progress(width: shown.bounds.width, iconSize: iconSize, screenWidth: screen.width)
    }
    private let startProgress: CGFloat

    private var lastShown: CGRect?

    /// Whether the card's spring has come to rest: no longer moving on
    /// screen and within a fraction of a point of its target. A spring's
    /// tail of sub-pixel motion would otherwise keep the launch screen up
    /// (and the app unbuilt) for most of a second longer than anyone can see.
    func hasComeToRest() -> Bool {
        guard face.isMoving else { return true }
        guard face.layer.presentation() != nil else { return false }
        let shown = face.shownFrame
        defer { lastShown = shown }
        let tolerance = RunnerMetrics.restTolerance
        let target = face.targetFrame
        guard let lastShown, shown.isClose(to: lastShown, within: tolerance), shown.isClose(to: target, within: tolerance) else {
            return false
        }
        face.finishMoving()
        self.lastShown = nil
        return true
    }

    /// Grows (or goes back) to full screen from wherever it is.
    func open(_ spring: Motion.Spring = Motion.cardOpen, centerVelocity: CGPoint = .zero, widthVelocity: CGFloat = 0) {
        phase = .opening
        landingFades = false
        face.alpha = 1
        face.spring(to: full, spring, centerVelocity: centerVelocity, widthVelocity: widthVelocity)
    }

    /// Shrinks into `landing`, from wherever it is.
    func close(to landing: CGRect, fades: Bool, centerVelocity: CGPoint = .zero, widthVelocity: CGFloat = 0) {
        if phase == .open { takePicture() }
        phase = .closing
        landingFades = fades
        face.spring(to: CardFrame(rect: landing, radius: landing.width * HomeMetrics.iconCornerRatio), Motion.cardClose,
                    centerVelocity: centerVelocity, widthVelocity: widthVelocity)
    }

    /// A finger has caught the card at `finger`: it stops where it is on
    /// screen and from now on follows the finger.
    func hold(finger: CGPoint, direction: CloseDirection) {
        heldFrom = phase
        if phase == .open { takePicture() }
        phase = .held
        let frame = face.freeze()
        grab = (frame, frame.size.width / screen.width, finger, direction)
        travel = 0
    }

    func move(_ translation: CGPoint) {
        guard let grab else { return }
        let tracked = CardMotion.tracked(start: grab.frame, startScale: grab.scale, finger: grab.finger,
                                         translation: translation, direction: grab.direction, screenHeight: screen.height)
        travel = tracked.travel
        face.place(tracked.frame)
    }

    /// The finger has let go, moving at `velocity`: whether the card should
    /// close, and how fast its centre and width were moving.
    func release(velocity: CGPoint) -> (closes: Bool, centerVelocity: CGPoint, widthVelocity: CGFloat) {
        guard let grab else { return (false, .zero, 0) }
        self.grab = nil
        let travelVelocity = grab.direction.travel(velocity)
        let slope = CardMotion.scaleSlope(travel: travel, screenHeight: screen.height,
                                          floor: CardMotion.floor(startScale: grab.scale))
        let widthVelocity = grab.frame.size.width / max(grab.scale, .ulpOfOne) * slope * travelVelocity
        return (CardMotion.closes(travel: travel, velocity: travelVelocity), velocity, widthVelocity)
    }

    /// Called every frame while anything moves: what the card shows follows
    /// its size on screen.
    func tick() {
        let progress = progress
        face.content.alpha = CardMotion.contentOpacity(progress: progress)
        if landingFades { face.alpha = min(progress / RunnerMetrics.landingFade, 1) }
    }

    /// The card's spring has come to rest.
    func settle() {
        switch phase {
        case .opening:
            phase = .open
            host.view.isHidden = false
            face.content.subviews.forEach { $0.removeFromSuperview() }
            state.isSettled = true
        case .closing:
            phase = .landed
        default:
            break
        }
    }

    /// Swaps the live app for a picture of it, which can move.
    private func takePicture() {
        host.view.endEditing(true)
        if let picture = host.view.snapshotView(afterScreenUpdates: false) {
            face.content.subviews.forEach { $0.removeFromSuperview() }
            picture.frame = face.content.bounds
            face.content.addSubview(picture)
            face.content.alpha = 1
        }
        host.view.isHidden = true
    }
}

private extension CGRect {
    func isClose(to other: CGRect, within tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
