import SwiftUI
import UIKit

/// What an open app's SwiftUI side needs from its card.
@MainActor
@Observable
final class CardState {
    /// The open has come to rest. Kiln parses on the main thread, so the app
    /// is built only after this: never while anything is moving.
    var isSettled = false
    /// The app (or its error screen) has finished fading in over the
    /// card's launch surface, which can go.
    @ObservationIgnored var onLaunched: () -> Void = {}
}

/// The app inside a card.
struct CardRoot: View {
    var run: HomeModel.Run
    var state: CardState
    var data: AppData

    var body: some View {
        // The card's own face is the launch surface, under the stage, so
        // the stage shows nothing of its own until the app is built, and
        // then fades the app in over it.
        AppStage(app: run.app.meta, source: run.source, store: .synced, data: data,
                 isReady: state.isSettled, showsLaunchScreen: false, onLaunched: { state.onLaunched() })
    }
}

/// The moving part of a card: the app's icon (`IconArtView`, the same
/// renderer as the Home Screen's, so a card at icon size is the icon), with a
/// picture over it: the app's launch surface as it opens (`LaunchSurfaceView`,
/// or its last snapshot), the app itself as it closes. Which shows, and how
/// much, follows the card's size (`CardLook`).
///
/// As Springboard's, growing and shrinking alike, everything on the card
/// keeps its shape and is scaled by the card's width from its top: the
/// picture is cropped at the bottom, and the glyph is where it would be on
/// a square icon at the card's top (`fitArt`). Only the tile's fill
/// stretches to the card. The corners stay the display's until the card is
/// nearly an icon. It leans in depth by where its icon is (`CardLean`).
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
    /// The lean, about the card's horizontal and vertical axes, and what
    /// the current flight does with it.
    private(set) var lean = CardLean.none
    private var leanFrom = CardLean.none
    private var flightStartProgress: CGFloat = 1
    private var leans = false
    /// The middle of the icon a growing card left, while it leans by it.
    private var leansFrom: CGPoint?

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
        let wide = size.width / screen.width
        // As tall as its width makes it, from the card's top; never shorter
        // than the card (one growing past the screen's shape).
        let tall = max(wide, size.height / screen.height)
        withoutActions {
            layer.position = frame.center
            content.layer.transform = CATransform3DMakeScale(wide, tall, 1)
            content.layer.position = CGPoint(x: 0, y: (screen.height * tall - size.height) / 2)
            fitArt(to: size)
            setOutline(size, radius: shown.radius)
        }
    }

    /// Sends the card to `target` on `springs`, from where it is on screen,
    /// at `velocity` (per second, of played time), or at the speed it is
    /// already moving. A card that `leans` leans toward an icon below it on
    /// the way, landing; one that `leansFrom` an icon's height leans the
    /// same way growing out of it, less as it grows; any other straightens
    /// up as it goes. It leans from the angle it has, without a jolt.
    func fly(to target: CardFrame, _ springs: Motion.CardSprings, velocity: CardVelocity? = nil, leans: Bool = false,
             leansFrom icon: CGPoint? = nil, at time: Double = CACurrentMediaTime()) {
        let velocity = velocity ?? flight?.velocity(at: time) ?? .zero
        self.springs = springs
        if flight == nil || leans != self.leans || (icon == nil) != (leansFrom == nil) { flightStartProgress = progress(shown) }
        self.leans = leans
        leansFrom = icon
        let flight = CardFlight(from: shown, velocity: velocity, to: target, springs: springs,
                                slowdown: Motion.Spring.slowdown, at: time)
        self.flight = flight
        // What it leans by now, less what this flight's own lean is here,
        // fading out as it goes.
        let left = remaining(progress(shown), in: flight)
        leanFrom = left > 0 ? (lean - ownLean(for: shown, in: flight)) * (1 / left) : .none
    }

    /// The same flight, to where its target has moved, carrying on at the
    /// speed it has.
    func retarget(_ target: CardFrame, at time: Double) {
        guard let flight, !flight.target.isClose(to: target, within: RunnerMetrics.restTolerance) else { return }
        fly(to: target, springs, leans: leans, leansFrom: leansFrom, at: time)
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
        setLean(arrived ? .none : lean(for: frame, in: flight))
        if arrived { self.flight = nil }
        return arrived
    }

    /// The lean for `frame` on `flight`: what it had when the flight began,
    /// fading out as the card gets where it is going, plus its own: landing,
    /// toward its icon; growing, away from the one it left.
    private func lean(for frame: CardFrame, in flight: CardFlight) -> CardLean {
        (leanFrom * remaining(progress(frame), in: flight) + ownLean(for: frame, in: flight)).limited
    }

    /// How much of the way from where the flight started to its target the
    /// card still has to go, at `progress`: 1 setting off, 0 there.
    private func remaining(_ progress: CGFloat, in flight: CardFlight) -> CGFloat {
        let start = flightStartProgress, end = self.progress(flight.target)
        return abs(start - end) > 0.001 ? min(max((progress - end) / (start - end), 0), 1) : 0
    }

    private func ownLean(for frame: CardFrame, in flight: CardFlight) -> CardLean {
        let now = progress(frame)
        if leans {
            let lost = max(flightStartProgress - now, 0)
            return CardLean(back: CardMotion.lean(centerY: frame.center.y, height: frame.size.height,
                                                  targetY: flight.target.center.y,
                                                  startProgress: flightStartProgress, progress: now),
                            side: CardMotion.sideLean(centerX: frame.center.x, width: frame.size.width,
                                                      iconX: flight.target.center.x, amount: lost))
        }
        if let icon = leansFrom {
            return CardLean(back: CardMotion.openingLean(centerY: frame.center.y, height: frame.size.height,
                                                         iconY: icon.y, progress: now),
                            side: CardMotion.sideLean(centerX: frame.center.x, width: frame.size.width,
                                                      iconX: icon.x, amount: 1 - now))
        }
        return .none
    }

    private func setLean(_ lean: CardLean) {
        guard lean != self.lean else { return }
        self.lean = lean
        var transform = CATransform3DIdentity
        transform.m34 = -1 / RunnerMetrics.leanPerspective
        transform = CATransform3DRotate(transform, lean.back, 1, 0, 0)
        transform = CATransform3DRotate(transform, lean.side, 0, 1, 0)
        withoutActions { layer.transform = transform }
    }

    /// Stops the card where it is on screen and returns where that is. It
    /// keeps its lean until it moves again.
    func freeze() -> CardFrame {
        flight = nil
        return shown
    }

    var isMoving: Bool { flight != nil }
    var shownFrame: CGRect { shown.rect }

    /// Shows `picture` over the icon, full-screen size, in place of what
    /// was there: a crossfade when any of it is showing.
    func show(_ picture: UIView, fading: Bool = false) {
        picture.frame = content.bounds
        let swap = { [content] in
            content.subviews.forEach { $0.removeFromSuperview() }
            content.addSubview(picture)
        }
        if fading, content.alpha > 0.01, !isHidden {
            UIView.transition(with: content, duration: Motion.fadeDuration * Motion.Spring.slowdown,
                              options: [.transitionCrossDissolve, .allowUserInteraction], animations: swap)
        } else {
            swap()
        }
    }
}

/// One open app: a card that grows out of its icon, the live app over it
/// once it has, and back.
///
/// While the card moves, the live app stays put, full screen and hidden,
/// and the card shows a picture of it instead. So the app never lays out
/// again mid-flight (a scaled view's safe area changes every frame), and
/// its own presentations, keyboard and navigation are untouched.
///
/// Opening, the picture is the launch surface. The card's face stays
/// under the live app, showing it, until the app has been built and has
/// faded in over it (`launched`). Closing, the picture is the app as it
/// was, which is also kept as its launch snapshot for next time.
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
    /// The app has been built and has faded in over the launch surface.
    private(set) var isLaunched = false
    /// It has set off for full screen once: only that first open grows out
    /// of its icon.
    private var wasOpened = false
    /// What the card shows and the Home Screen's look, this frame.
    private(set) var look = CardMotion.look(progress: 0, opening: true)
    private var handoff = LookHandoff.fromIcon
    /// Given the app's picture as the card leaves it, to keep as its
    /// launch snapshot.
    var keepsPicture: (UIImage) -> Void = { _ in }

    private let screen: CGSize
    private let iconSize: CGFloat
    private let fullRadius: CGFloat
    /// The middle of the icon it opened from.
    private let icon: CGPoint
    private var grab: (frame: CardFrame, scale: CGFloat, finger: CGPoint, direction: CloseDirection)?
    private var travel: CGFloat = 0
    private var translation: CGPoint = .zero

    var slug: String { run.id }

    /// `surface` is what the app opens on: its snapshot, or a launch
    /// surface, at full-screen size.
    init(run: HomeModel.Run, data: AppData, face: IconFace, surface: UIView, screen: CGSize, iconSize: CGFloat,
         fullRadius: CGFloat, from source: CGRect) {
        self.run = run
        self.screen = screen
        self.iconSize = iconSize
        self.fullRadius = fullRadius
        icon = CGPoint(x: source.midX, y: source.midY)
        self.face = CardFaceView(face: face, iconSize: iconSize, screen: screen, fullRadius: fullRadius)
        host = UIHostingController(rootView: CardRoot(run: run, state: state, data: data))
        // Clear until the app is built, so the card's face is its launch screen.
        host.view.backgroundColor = .clear
        host.view.isHidden = true
        self.face.place(CardFrame(rect: source, radius: HomeMetrics.iconRadius(iconSize)))
        self.face.show(surface)
        state.onLaunched = { [weak self] in self?.launched() }
    }

    /// The app's last snapshot has been read from disk: it takes the place
    /// of the launch surface, if the app isn't there yet.
    func showSnapshot(_ picture: UIImage) {
        guard !isLaunched, phase == .opening || phase == .open || phase == .held else { return }
        let view = UIImageView(image: picture)
        view.contentMode = .scaleToFill
        face.show(view, fading: true)
    }

    /// The app has faded in over the launch surface.
    private func launched() {
        isLaunched = true
        guard phase == .open else { return }
        // Covered by the live app until a finger or a close needs it.
        face.isHidden = true
        face.content.subviews.forEach { $0.removeFromSuperview() }
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
        turn(opening: true)
        phase = .opening
        landingFades = false
        face.isHidden = false
        face.alpha = 1
        // Out of its icon, it leans away from it; back from a finger or a
        // landing, it straightens up.
        face.fly(to: full, springs, velocity: velocity, leansFrom: wasOpened ? nil : icon)
        wasOpened = true
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
        if phase != .closing { turn(opening: false) }
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
        // A finger shrinks it: the close's look, from what it shows now.
        turn(opening: false)
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
        look = handoff.look(at: progress)
        face.content.alpha = look.content
        if landingFades { face.alpha = min(progress / RunnerMetrics.landingFade, 1) }
    }

    /// The card sets off growing or shrinking: its look carries on from
    /// what it is now toward that direction's (`LookHandoff`).
    private func turn(opening: Bool) {
        handoff = LookHandoff(from: look, at: progress, opening: opening)
    }

    /// The card's spring has come to rest. Returns whether it has landed
    /// on its icon.
    func settle() -> Bool {
        switch phase {
        case .opening:
            phase = .open
            host.view.isHidden = false
            state.isSettled = true
            if isLaunched {
                // Covered by the live app until a finger or a close needs it.
                face.isHidden = true
                face.content.subviews.forEach { $0.removeFromSuperview() }
            }
            // Otherwise the face stays, full screen, as the launch surface
            // under the app (clear until it is built), until it fades in.
            return false
        case .closing:
            phase = .landed
            return true
        default:
            return false
        }
    }

    /// Swaps the live app for a picture of it, which can move, and keeps
    /// that picture as its launch snapshot. An app not yet built has
    /// nothing to take: the launch surface the face still shows stays.
    private func takePicture() {
        face.isHidden = false
        guard isLaunched else {
            host.view.isHidden = true
            return
        }
        host.view.endEditing(true)
        if let snapshot = snapshot() { keepsPicture(snapshot) }
        if let picture = host.view.snapshotView(afterScreenUpdates: false) {
            face.show(picture)
            face.content.alpha = 1
        }
        host.view.isHidden = true
    }

    /// The app as it is on screen, as an image to keep. `drawHierarchy`
    /// rather than `snapshotView`, whose view can't be drawn into a file,
    /// or `layer.render`, which misses what SwiftUI draws on the GPU.
    private func snapshot() -> UIImage? {
        let view = host.view!
        let format = UIGraphicsImageRendererFormat(for: view.traitCollection)
        format.opaque = true
        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            drawn = view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        return drawn ? image : nil
    }
}

extension CardFrame {
    func isClose(to other: CardFrame, within tolerance: CGFloat) -> Bool {
        abs(center.x - other.center.x) <= tolerance && abs(center.y - other.center.y) <= tolerance
            && abs(size.width - other.size.width) <= tolerance && abs(size.height - other.size.height) <= tolerance
            && abs(radius - other.radius) <= tolerance
    }
}
