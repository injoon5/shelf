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
}

/// The squircle and its glyph, in the current icon style. No label, no state.
struct IconArt: View {
    @Environment(ShelfSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    var face: IconFace
    var size: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * HomeMetrics.iconCornerRatio, style: .continuous)
    }

    var body: some View {
        let style = settings.iconStyle.resolved(for: scheme)
        Image(systemName: face.symbol)
            // An icon's glyph is part of its artwork: it scales with the icon, not with text.
            .font(.system(size: size * HomeMetrics.glyphRatio, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(style == .dark ? AnyShapeStyle(face.tint) : AnyShapeStyle(.white))
            .frame(width: size, height: size)
            .background { fill(style) }
            .modifier(IconGlass(style: style, accent: settings.accent.color, shape: shape))
            .overlay { rim }
            .compositingGroup()
    }

    @ViewBuilder
    private func fill(_ style: IconStyle) -> some View {
        switch style {
        case .dark:
            shape.fill(LinearGradient(colors: [HomeMetrics.darkFillTop, HomeMetrics.darkFillBottom], startPoint: .top, endPoint: .bottom))
        case .clear, .tinted:
            EmptyView()
        case .standard, .automatic:
            shape.fill(LinearGradient(colors: [face.tint.mix(with: .white, by: HomeMetrics.fillLift), face.tint],
                                      startPoint: .top, endPoint: .bottom))
        }
    }

    /// The bright edge Liquid Glass icons carry, strongest at the top.
    private var rim: some View {
        shape.strokeBorder(
            LinearGradient(colors: [.white.opacity(HomeMetrics.rimOpacity), .white.opacity(0)], startPoint: .top, endPoint: .bottom),
            lineWidth: HomeMetrics.rimWidth)
    }
}

/// Clear and Tinted icons are system glass; the other styles are painted.
private struct IconGlass: ViewModifier {
    var style: IconStyle
    var accent: Color
    var shape: RoundedRectangle

    func body(content: Content) -> some View {
        switch style {
        case .clear: content.glassEffect(.clear, in: shape)
        case .tinted: content.glassEffect(.regular.tint(accent), in: shape)
        default: content
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
                .padding(HomeMetrics.pieRingWidth * 2)
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

    func body(content: Content) -> some View {
        content
            .brightness(isPressed ? HomeMetrics.pressedBrightness : 0)
            // Down is instant; only the release eases.
            .animation(isPressed ? nil : Motion.quick, value: isPressed)
    }
}

/// The label under a Home Screen icon.
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
        .animation(Motion.quick, value: isNew)
    }
}
