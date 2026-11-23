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
/// As Springboard's, the card is one picture stretched to its frame: the
/// app's picture and the icon's glyph are squashed to the card's width and
/// height, not cropped, and the corners stay the display's until the card is
/// nearly an icon. On its way to an icon below it, it leans back.
///
/// Like every `IconArtView`, its bounds are centred on its own origin, so
/// the glyph and the picture sit at (0, 0) and stay centred while the
/// outline changes.
///
/// It has no Core Animation animations of its own. A finger places it, or
/// its flight (`CardFlight`, a spring per property) does, every frame, so
/// what is on screen is always `shown`: a finger catches it exactly there,
/// and a new target carries on from there at the speed it had.
final class CardFaceView: IconArtView {
    /// Holds the app's picture at full-screen size, stretched to the card.
    let content = UIView()
    private let screen: CGSize
    private let fullRadius: CGFloat
    /// Where the card is on screen.
    private(set) var shown: CardFrame
    /// Where it is headed, if it is moving by itself.
    private(set) var flight: CardFlight?
    private var springs = Motion.cardOpen
    /// The lean, in radians about the horizontal axis, and what the
    /// current flight does with it.
    private(set) var lean: CGFloat = 0
    private var leanFrom: CGFloat = 0
    private var flightStartProgress: CGFloat = 1
    private var leans = false

    init(face: IconFace, iconSize: CGFloat, screen: CGSize, fullRadius: CGFloat) {
        self.screen = screen
        self.fullRadius = fullRadius
        shown = CardFrame(center: .zero, size: CGSize(width: iconSize, height: iconSize),
                          radius: HomeMetrics.iconRadius(iconSize))
        super.init(face: face, iconSize: iconSize)
        content.bounds = CGRect(origin: .zero, size: screen)
        content.center = .zero
        content.alpha = 0
        addSubview(content)
    }

    private func progress(_ frame: CardFrame) -> CGFloat {
        CardMotion.progress(width: frame.size.width, iconSize: iconSize, screenWidth: screen.width)
    }

    /// Puts the card at `frame` at once, its corner drawn for its size.
    ///
    /// In one transaction: its outline, its picture and its glyph reach the
    /// screen in the same frame, or the tile shows around the picture.
    func place(_ frame: CardFrame) {
        let size = frame.size
        shown = CardFrame(center: frame.center, size: size, radius: CardMotion.cornerRadius(size: size, full: fullRadius))
        withoutActions {
            layer.position = frame.center
            content.layer.transform = CATransform3DMakeScale(size.width / screen.width, size.height / screen.height, 1)
            stretchArt(to: size)
            setOutline(size, radius: shown.radius)
        }
    }

    /// Sends the card to `target` on `springs`, from where it is on screen,
    /// at `velocity` (per second, of played time), or at the speed it is
    /// already moving. A card that `leans` leans toward an icon below it on
    /// the way; one that doesn't straightens up as it goes.
    func fly(to target: CardFrame, _ springs: Motion.CardSprings, velocity: CardVelocity? = nil, leans: Bool = false,
             at time: Double = CACurrentMediaTime()) {
        let velocity = velocity ?? flight?.velocity(at: time) ?? .zero
        self.springs = springs
        if flight == nil || leans != self.leans { flightStartProgress = progress(shown) }
        self.leans = leans
        leanFrom = lean
        flight = CardFlight(from: shown, velocity: velocity, to: target, springs: springs,
                            slowdown: Motion.Spring.slowdown, at: time)
    }

    /// The same flight, to where its target has moved, carrying on at the
    /// speed it has.
    func retarget(_ target: CardFrame, at time: Double) {
        guard let flight, !flight.target.isClose(to: target, within: RunnerMetrics.restTolerance) else { return }
        fly(to: target, springs, leans: leans, at: time)
    }

    /// Moves the card to where its flight has it at `time`. Returns whether
    /// it has arrived: the flight's tail of sub-pixel motion would
    /// otherwise keep the launch screen up (and the app unbuilt) for most of
    /// a second longer than anyone can see.
    func step(at time: Double) -> Bool {
        guard let flight else { return true }
        let arrived = flight.isSettled(at: time)
        let frame = arrived ? flight.target : flight.frame(at: time)
        place(frame)
        setLean(arrived ? 0 : lean(for: frame, in: flight))
        if arrived { self.flight = nil }
        return arrived
    }

    /// The lean for `frame` on `flight`: what it had when the flight began,
    /// fading out as the card gets where it is going, plus, landing, the
    /// lean toward its icon.
    private func lean(for frame: CardFrame, in flight: CardFlight) -> CGFloat {
        let now = progress(frame), start = flightStartProgress, end = progress(flight.target)
        let left = abs(start - end) > 0.001 ? min(max((now - end) / (start - end), 0), 1) : 0
        var lean = leanFrom * left
        if leans {
            lean += CardMotion.lean(centerY: frame.center.y, height: frame.size.height, targetY: flight.target.center.y,
                                    startProgress: start, progress: now)
        }
        return min(max(lean, -RunnerMetrics.maxLean), RunnerMetrics.maxLean)
    }

    private func setLean(_ angle: CGFloat) {
        guard angle != lean else { return }
        lean = angle
        var transform = CATransform3DIdentity
        transform.m34 = -1 / RunnerMetrics.leanPerspective
        withoutActions { layer.transform = CATransform3DRotate(transform, angle, 1, 0, 0) }
    }

    /// Stops the card where it is on screen and returns where that is. It
    /// keeps its lean until it moves again.
    func freeze() -> CardFrame {
        flight = nil
        return shown
    }

    var isMoving: Bool { flight != nil }
    var shownFrame: CGRect { shown.rect }
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
    private var translation: CGPoint = .zero

    var slug: String { run.id }

    init(run: HomeModel.Run, data: AppData, face: IconFace, screen: CGSize, iconSize: CGFloat, fullRadius: CGFloat,
         from source: CGRect) {
        self.run = run
        self.screen = screen
        self.iconSize = iconSize
        self.fullRadius = fullRadius
        self.face = CardFaceView(face: face, iconSize: iconSize, screen: screen, fullRadius: fullRadius)
        host = UIHostingController(rootView: CardRoot(run: run, state: state, data: data))
        // Clear until the app is built, so the card's face is its launch screen.
        host.view.backgroundColor = .clear
        host.view.isHidden = true
        self.face.place(CardFrame(rect: source, radius: HomeMetrics.iconRadius(iconSize)))
    }

    private var full: CardFrame {
        CardFrame(rect: CGRect(origin: .zero, size: screen), radius: fullRadius)
    }

    /// How open the card is on screen: 1 full screen, 0 its icon.
    var progress: CGFloat {
        CardMotion.progress(width: face.shown.size.width, iconSize: iconSize, screenWidth: screen.width)
    }

    /// Moves the card along its flight to `time`. Returns whether it has
    /// come to rest.
    func step(at time: Double) -> Bool {
        face.step(at: time)
    }

    /// Grows (or goes back) to full screen from wherever it is, at
    /// `velocity`, or at the speed it is already moving.
    func open(_ springs: Motion.CardSprings = Motion.cardOpen, velocity: CardVelocity? = nil) {
        phase = .opening
        landingFades = false
        face.isHidden = false
        face.alpha = 1
        face.fly(to: full, springs, velocity: velocity)
    }

    /// Goes back to full screen after a finger let it go short of closing:
    /// on the open's springs if it was caught on its way home.
    func reopen(velocity: CardVelocity) {
        open(heldFrom == .closing ? Motion.cardOpen : Motion.cardReturn, velocity: velocity)
    }

    /// Shrinks into `landing`, from wherever it is, at `velocity` or the
    /// speed it already has.
    func close(to landing: CGRect, fades: Bool, velocity: CardVelocity? = nil) {
        if phase == .open { takePicture() }
        phase = .closing
        landingFades = fades
        face.fly(to: Self.landed(landing), Motion.cardClose, velocity: velocity, leans: true)
    }

    /// The icon it is landing on has moved (the pages turned under it, say):
    /// it heads there instead, without a jolt.
    func follow(landing: CGRect, fades: Bool, at time: Double) {
        guard phase == .closing else { return }
        landingFades = fades
        face.retarget(Self.landed(landing), at: time)
    }

    private static func landed(_ landing: CGRect) -> CardFrame {
        CardFrame(rect: landing, radius: HomeMetrics.iconRadius(landing.width))
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
        translation = .zero
    }

    func move(_ translation: CGPoint) {
        guard let grab else { return }
        let tracked = CardMotion.tracked(start: grab.frame, startScale: grab.scale, finger: grab.finger,
                                         translation: translation, direction: grab.direction, screenHeight: screen.height)
        travel = tracked.travel
        self.translation = translation
        face.place(tracked.frame)
    }

    /// The finger has let go, moving at `velocity`: whether the card should
    /// close, and how fast the card itself was moving.
    ///
    /// The decision is the finger's: its travel and its speed, however
    /// little the card's edge moved against its limit, so a flick still
    /// closes. The springs that follow carry on at the card's own speed,
    /// which near the limit is far less than the finger's, so nothing jumps
    /// and a flick never throws the card off the screen before it turns for
    /// its icon. Springboard's card does the same: after a flick its centre
    /// keeps the little speed it had and it shrinks where it is.
    func release(velocity: CGPoint) -> (closes: Bool, velocity: CardVelocity) {
        guard let grab else { return (false, .zero) }
        self.grab = nil
        let closes = CardMotion.closes(travel: travel, velocity: grab.direction.travel(velocity))
        let cardVelocity = CardMotion.trackedVelocity(start: grab.frame, startScale: grab.scale, finger: grab.finger,
                                                      translation: translation, velocity: velocity,
                                                      direction: grab.direction, screenHeight: screen.height)
        // A finger's speed is real time; the springs run in played time.
        return (closes, cardVelocity.scaled(by: 1 / Motion.Spring.slowdown))
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

extension CardFrame {
    func isClose(to other: CardFrame, within tolerance: CGFloat) -> Bool {
        abs(center.x - other.center.x) <= tolerance && abs(center.y - other.center.y) <= tolerance
            && abs(size.width - other.size.width) <= tolerance && abs(size.height - other.size.height) <= tolerance
            && abs(radius - other.radius) <= tolerance
    }
}
