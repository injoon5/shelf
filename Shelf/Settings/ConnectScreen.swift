import SwiftUI

/// The first run: Shelf's glyph, where the apps live, and the token.
struct ConnectScreen: View {
    var body: some View {
        VStack(spacing: SettingsMetrics.glyphGap) {
            ShelfMark(size: SettingsMetrics.glyphSize)
                .accessibilityHidden(true)
            ConnectForm(style: .glass)
        }
        .padding(SettingsMetrics.formPadding)
        .frame(maxWidth: SettingsMetrics.formWidth)
        // The form keeps clear of the keyboard and rides up with it; the
        // wallpaper behind stays where it is.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.standard, value: isKeyboardUp)
        .background { WallpaperBackground().ignoresSafeArea() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in isKeyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in isKeyboardUp = false }
        .dynamicTypeSize(...ShelfMetrics.textSizeCap)
    }

    @State private var isKeyboardUp = false
}

/// Shelf's own icon, drawn: three apps lifted just off a shelf, the last one
/// leaning. The numbers are those of `Resources/AppIcon.icon` on its
/// 1024-point canvas; only the real icon gets the system's glass.
private struct ShelfMark: View {
    @Environment(\.colorScheme) private var scheme
    var size: CGFloat

    private var dark: Bool { scheme == .dark }
    private var paper: Color { dark ? Color(red: 0.87, green: 0.89, blue: 0.96) : .white }
    private var accent: Color { dark ? Color(red: 1, green: 0.58, blue: 0.31) : Color(red: 1, green: 0.54, blue: 0.24) }
    private var plank: Color { dark ? Color(red: 0.56, green: 0.60, blue: 0.77) : .white.opacity(0.9) }
    private var sky: [Color] {
        dark ? [Color(red: 0.12, green: 0.11, blue: 0.29), Color(red: 0.05, green: 0.04, blue: 0.11)]
             : [Color(red: 0.43, green: 0.45, blue: 0.94), Color(red: 0.23, green: 0.21, blue: 0.72)]
    }

    var body: some View {
        let k = size / 1024
        ZStack {
            LinearGradient(colors: sky, startPoint: .top, endPoint: .bottom)
            Capsule().fill(plank)
                .frame(width: 832 * k, height: 96 * k)
                .position(x: 512 * k, y: 637 * k)
            tile(x: 140, paper)
            tile(x: 398, accent)
            tile(x: 677, paper)
                .rotationEffect(.degrees(-12), anchor: UnitPoint(x: 677 / 1024, y: 567 / 1024))
        }
        .frame(width: size, height: size)
        .clipShape(HomeMetrics.iconShape(size))
    }

    private func tile(x: CGFloat, _ color: Color) -> some View {
        let k = size / 1024
        return RoundedRectangle(cornerRadius: 62 * k, style: .continuous).fill(color)
            .frame(width: 228 * k, height: 228 * k)
            .position(x: (x + 114) * k, y: 453 * k)
    }
}

/// A site, a token and a Connect button. The token is checked against the
/// server before anything is saved: a wrong one shakes the field and leaves
/// no trace.
struct ConnectForm: View {
    enum Style {
        /// Glass fields over the wallpaper.
        case glass
        /// Rows in a form.
        case plain
    }

    @Environment(LibraryStore.self) private var library
    var style: Style
    var onConnected: () -> Void = {}

    @State private var site = Account.site.absoluteString
    @State private var token = ""
    @State private var isChecking = false
    @State private var failure: API.Failure?
    @State private var shakes = 0
    @FocusState private var focus: Field?

    private enum Field { case site, token }

    private var siteURL: URL? {
        let text = site.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: text.contains("://") ? text : "https://" + text),
              let scheme = url.scheme, ["https", "http"].contains(scheme), url.host() != nil else { return nil }
        return url
    }

    private var canConnect: Bool {
        siteURL != nil && !token.trimmingCharacters(in: .whitespaces).isEmpty && !isChecking
    }

    var body: some View {
        VStack(spacing: SettingsMetrics.formSpacing) {
            field {
                TextField("Site", text: $site)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .focused($focus, equals: .site)
                    .submitLabel(.next)
                    .onSubmit { focus = .token }
            }
            field {
                SecureField("Token", text: $token)
                    .textContentType(.password)
                    .focused($focus, equals: .token)
                    .submitLabel(.go)
                    .onSubmit(connect)
            }
            .modifier(Shake(trigger: shakes))

            Button(action: connect) {
                ZStack {
                    Text("Connect").opacity(isChecking ? 0 : 1)
                    if isChecking { ProgressView() }
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: SettingsMetrics.buttonHeight)
            }
            .buttonStyle(.glassProminent)
            .disabled(!canConnect)

            if let failure {
                Label(message(for: failure), systemImage: failure == .unauthorized ? "key" : "wifi.slash")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(style == .glass ? AnyShapeStyle(.white) : AnyShapeStyle(.red))
                    .transition(.opacity)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .animation(Motion.quick, value: failure)
        .sensoryFeedback(.error, trigger: shakes)
    }

    @ViewBuilder
    private func field(@ViewBuilder _ content: () -> some View) -> some View {
        let shape = RoundedRectangle(cornerRadius: SettingsMetrics.fieldRadius, style: .continuous)
        let row = content()
            .padding(.horizontal, SettingsMetrics.fieldInset)
            .frame(minHeight: SettingsMetrics.fieldHeight)
        switch style {
        case .glass: row.glassEffect(.regular.interactive(), in: shape)
        case .plain: row.background(Color(.tertiarySystemFill), in: shape)
        }
    }

    private func message(for failure: API.Failure) -> String {
        switch failure {
        case .unauthorized: "Token Not Right"
        case .offline: "Can’t Reach Server"
        case .rejected(_, let message): message
        }
    }

    private func connect() {
        guard canConnect, let siteURL else { return }
        isChecking = true
        failure = nil
        Task {
            defer { isChecking = false }
            do throws(API.Failure) {
                try await library.signIn(site: siteURL, token: token.trimmingCharacters(in: .whitespaces))
                onConnected()
            } catch {
                failure = error
                shakes += 1
                focus = .token
            }
        }
    }
}

/// A quick side-to-side shake: the token was refused.
private struct Shake: ViewModifier {
    var trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            let step = Motion.shakeSteps
            SpringKeyframe(HomeMetrics.shakeDistance, duration: step[0], spring: Motion.shakeStep)
            SpringKeyframe(-HomeMetrics.shakeDistance, duration: step[1], spring: Motion.shakeStep)
            SpringKeyframe(HomeMetrics.shakeDistance / 2, duration: step[2], spring: Motion.shakeStep)
            SpringKeyframe(0, duration: step[3], spring: Motion.shakeHome)
        }
    }
}
