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
    var data: AppData

    var body: some View {
        // The card's own face is the launch screen, so the stage shows
        // nothing of its own until the app is built.
        AppStage(app: run.app.meta, source: run.source, store: .synced, data: data,
                 isReady: state.isSettled, showsLaunchScreen: false)
    }
}

/// The moving part of a card: the app's icon (`IconArtView`, the same
/// renderer as the Home Screen's, so a card at icon size is the icon), with a
/// picture of the app over it. At full screen the icon's tile and glyph are
/// the app's launch screen; every size between is both.
///
/// Like every `IconArtView`, its bounds are centred on its own origin, so
/// the glyph and the picture sit at (0, 0) and stay centred while the
/// outline springs, with no animations of their own to keep in step.
final class CardFaceView: IconArtView {
    /// Holds the app's picture at full-screen size, scaled to the card's width.
    let content = UIView()
    private let screen: CGSize
    /// Carries the corner's springs, which the outline's paths do too, so
    /// where the corner is on screen can be read back when a finger catches
    /// the card.
    private let corner = CALayer()

    init(face: IconFace, iconSize: CGFloat, screen: CGSize) {
        self.screen = screen
        super.init(face: face, iconSize: iconSize)
        corner.isHidden = true
        layer.addSublayer(corner)
        content.bounds = CGRect(origin: .zero, size: screen)
        content.center = .zero
        content.alpha = 0
        addSubview(content)
    }

    /// Puts the card at `frame` at once.
    func place(_ frame: CardFrame) {
        withoutActions {
            layer.removeAnimations(withKeyPrefix: "position")
            corner.removeAllAnimations()
            layer.position = frame.center
            corner.cornerRadius = frame.radius
            content.layer.removeAllAnimations()
            content.layer.setValue(frame.size.width / screen.width, forKeyPath: "transform.scale")
        }
        setOutline(frame.size, radius: frame.radius)
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
        springOutline(to: frame.size, radius: frame.radius, spring, velocity: sizeVelocity)
        corner.spring("cornerRadius", to: frame.radius, spring, velocity: sizeVelocity)
        content.layer.spring("transform.scale", to: frame.size.width / screen.width, spring, velocity: sizeVelocity)
    }

    /// Stops the card where it is on screen and returns where that is.
    func freeze() -> CardFrame {
        let frame = shownCard
        layer.removeAllAnimationsDeeply()
        content.layer.removeAllAnimationsDeeply()
        place(frame)
        return frame
    }

    var isMoving: Bool { layer.isAnimating || content.layer.isAnimating }

    /// Where the card's springs are headed.
    var targetFrame: CGRect { CardFrame(center: layer.position, size: layer.bounds.size, radius: corner.cornerRadius).rect }

    /// Ends the springs at their targets, which the model already holds.
    func finishMoving() {
        layer.removeAllAnimationsDeeply()
        content.layer.removeAllAnimationsDeeply()
    }

    private var shownCard: CardFrame {
        let shown = layer.presentation() ?? layer
        return CardFrame(center: shown.position, size: shown.bounds.size,
                         radius: (corner.presentation() ?? corner).cornerRadius)
    }

    var shownFrame: CGRect { shownCard.rect }
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
    private var heldFrom = Phase.open
    private(set) var landingFades = false

    private let screen: CGSize
    private let iconSize: CGFloat
    private let fullRadius: CGFloat
    private var grab: (frame: CardFrame, scale: CGFloat, finger: CGPoint, direction: CloseDirection)?
    private var travel: CGFloat = 0

    var slug: String { run.id }

    init(run: HomeModel.Run, data: AppData, face: IconFace, screen: CGSize, iconSize: CGFloat, fullRadius: CGFloat,
         from source: CGRect) {
        self.run = run
        self.screen = screen
        self.iconSize = iconSize
        self.fullRadius = fullRadius
        startProgress = CardMotion.progress(width: source.width, iconSize: iconSize, screenWidth: screen.width)
        self.face = CardFaceView(face: face, iconSize: iconSize, screen: screen)
        host = UIHostingController(rootView: CardRoot(run: run, state: state, data: data))
        // Clear until the app is built, so the card's face is its launch screen.
        host.view.backgroundColor = .clear
        host.view.isHidden = true
        self.face.place(CardFrame(rect: source, radius: HomeMetrics.iconRadius(iconSize)))
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
        face.isHidden = false
        face.alpha = 1
        face.spring(to: full, spring, centerVelocity: centerVelocity, widthVelocity: widthVelocity)
    }

    /// Goes back to full screen after a finger let it go short of closing:
    /// on the open's spring if it was caught on its way home.
    func reopen(centerVelocity: CGPoint, widthVelocity: CGFloat) {
        open(heldFrom == .closing ? Motion.cardOpen : Motion.cardReturn, centerVelocity: centerVelocity, widthVelocity: widthVelocity)
    }

    /// Shrinks into `landing`, from wherever it is.
    func close(to landing: CGRect, fades: Bool, centerVelocity: CGPoint = .zero, widthVelocity: CGFloat = 0) {
        if phase == .open { takePicture() }
        phase = .closing
        landingFades = fades
        face.spring(to: CardFrame(rect: landing, radius: HomeMetrics.iconRadius(landing.width)), Motion.cardClose,
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

    /// The card's spring has come to rest. Returns whether it has landed
    /// on its icon.
    func settle() -> Bool {
        switch phase {
        case .opening:
            phase = .open
            host.view.isHidden = false
            // Covered by the live app until a finger or a close needs it.
            face.isHidden = true
            face.content.subviews.forEach { $0.removeFromSuperview() }
            state.isSettled = true
            return false
        case .closing:
            phase = .landed
            return true
        default:
            return false
        }
    }

    /// Swaps the live app for a picture of it, which can move.
    private func takePicture() {
        face.isHidden = false
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
