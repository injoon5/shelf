import SwiftUI

/// SF Symbol names come from the server and from model replies, so any of
/// them may not exist. A name that isn't a symbol becomes the generic glyph.
@MainActor
enum Symbol {
    static let fallback = "app"
    private static var known: [String: String] = [:]

    static func resolve(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return fallback }
        if let hit = known[name] { return hit }
        let resolved = UIImage(systemName: name) == nil ? fallback : name
        known[name] = resolved
        return resolved
    }
}

extension Tint {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}

/// What an icon is drawn from. Apps and Shelf's own Settings icon share it.
struct IconFace: Equatable {
    var symbol: String
    var tint: Color

    @MainActor
    init(_ app: AppMeta) {
        symbol = Symbol.resolve(app.icon)
        tint = app.tint.color
    }

    init(symbol: String, tint: Color) {
        self.symbol = symbol
        self.tint = tint
    }

    static let settings = IconFace(symbol: "gearshape.fill", tint: .gray)

    /// The tile, top to bottom: the system's near-black in dark mode,
    /// otherwise the tint, lifted toward white at the top. The same in every
    /// place an icon is painted: `IconArt`, and an app's card (`CardFace`).
    func fill(dark: Bool) -> (top: Color, bottom: Color) {
        dark ? (HomeMetrics.darkFillTop, HomeMetrics.darkFillBottom)
            : (tint.mix(with: .white, by: HomeMetrics.fillLift), tint)
    }

    /// Colour icons in dark mode are the system's dark variant, with the
    /// glyph in the app's colour. Every other glyph is white.
    static func tintsGlyph(_ style: IconStyle, dark: Bool) -> Bool {
        style == .color && dark
    }
}

/// The squircle and its glyph, in the current icon style. No label, no state.
struct IconArt: View {
    @Environment(ShelfSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @Environment(\.jiggleTurn) private var turn
    var face: IconFace
    var size: CGFloat
    /// Off while an install pie stands where the glyph goes.
    var showsGlyph = true

    private var shape: RoundedRectangle { HomeMetrics.iconShape(size) }

    var body: some View {
        let style = settings.iconStyle
        Image(systemName: face.symbol)
            // An icon's glyph is part of its artwork: it scales with the icon, not with text.
            .font(.system(size: size * HomeMetrics.glyphRatio, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(glyphStyle(style))
            .opacity(showsGlyph ? 1 : 0)
            .frame(width: size, height: size)
            .rotationEffect(turn)
            .background { fill(style) }
            .modifier(IconGlass(isOn: style == .clear, scheme: scheme, shape: shape.rotation(turn)))
            .overlay { rim.rotationEffect(turn) }
            .compositingGroup()
    }

    /// A white glyph is a shade darker at the foot.
    private func glyphStyle(_ style: IconStyle) -> AnyShapeStyle {
        if IconFace.tintsGlyph(style, dark: scheme == .dark) { return AnyShapeStyle(face.tint) }
        return AnyShapeStyle(LinearGradient(colors: [.white, .white.opacity(HomeMetrics.glyphShade)],
                                            startPoint: .top, endPoint: .bottom))
    }

    /// Clear icons have no fill: they are glass.
    @ViewBuilder
    private func fill(_ style: IconStyle) -> some View {
        if style == .color {
            let fill = face.fill(dark: scheme == .dark)
            shape.fill(LinearGradient(colors: [fill.top, fill.bottom], startPoint: .top, endPoint: .bottom))
        }
    }

    /// The bright edge Liquid Glass icons carry: strongest at the top, gone
    /// at the sides, a faint return along the bottom.
    private var rim: some View {
        shape.strokeBorder(
            LinearGradient(stops: [
                .init(color: .white.opacity(HomeMetrics.rimOpacity), location: 0),
                .init(color: .white.opacity(0), location: 0.5),
                .init(color: .white.opacity(HomeMetrics.rimReturnOpacity), location: 1),
            ], startPoint: .top, endPoint: .bottom),
            lineWidth: HomeMetrics.rimWidth)
    }
}

/// The icon's outline inside a whole Home Screen cell: the icon sits at the
/// top, centred, with its label below. The system lifts and drags a cell
/// clipped to this, so its previews have the icon's own corners and no label.
struct IconOutline: Shape {
    var size: CGFloat

    func path(in rect: CGRect) -> Path {
        HomeMetrics.iconShape(size).path(in: CGRect(x: rect.midX - size / 2, y: rect.minY, width: size, height: size))
    }
}

/// Clear icons are the Home Screen's own glass.
private struct IconGlass<S: Shape>: ViewModifier {
    var isOn: Bool
    var scheme: ColorScheme
    var shape: S

    func body(content: Content) -> some View {
        if isOn {
            content.glassEffect(HomeMetrics.glass(scheme), in: shape)
        } else {
            content
        }
    }
}

/// The App Store install state: a ring with a pie filling inside it.
struct InstallPie: View {
    var progress: Double
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().strokeBorder(.white, lineWidth: HomeMetrics.pieRingWidth)
            PieSlice(progress: progress)
                .fill(.white)
                .padding(HomeMetrics.pieInset)
        }
        .frame(width: size, height: size)
    }
}

private struct PieSlice: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center, radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * min(max(progress, 0), 1)), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// Icons darken on touch-down and never shrink, as Springboard's do. The
/// style only reports the press; `IconPress` applies it to the artwork alone,
/// so the label stays as it is.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.isIconPressed, configuration.isPressed)
    }
}

extension EnvironmentValues {
    @Entry var isIconPressed = false
}

struct IconPress: ViewModifier {
    @Environment(\.isIconPressed) private var isPressed
    var size: CGFloat

    func body(content: Content) -> some View {
        content
            // Darkening by multiplying, as Springboard does, keeps the glyph
            // and the fill in proportion instead of greying them.
            .overlay {
                HomeMetrics.iconShape(size)
                    .fill(.black.opacity(isPressed ? HomeMetrics.pressedDim : 0))
                    .modifier(JiggleTurn())
                    .allowsHitTesting(false)
            }
            // Down is instant; only the release eases.
            .animation(isPressed ? nil : Motion.quick, value: isPressed)
    }
}

struct IconLabel: View {
    var name: String
    var isNew: Bool
    var size: CGFloat
    var width: CGFloat

    var body: some View {
        HStack(spacing: HomeMetrics.newDotGap) {
            if isNew {
                Circle().fill(.blue)
                    .frame(width: HomeMetrics.newDotSize, height: HomeMetrics.newDotSize)
                    .transition(.scale.combined(with: .opacity))
            }
            Text(name)
                .font(.system(size: size, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(HomeMetrics.labelShadowOpacity), radius: HomeMetrics.labelShadowRadius, y: HomeMetrics.labelShadowY)
        .frame(width: width)
        .modifier(JiggleTurn())
        .animation(Motion.quick, value: isNew)
    }
}
