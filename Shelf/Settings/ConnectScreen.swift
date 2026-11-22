import SwiftUI

/// The first run: Shelf's glyph, where the apps live, and the token.
struct ConnectScreen: View {
    var body: some View {
        VStack(spacing: SettingsMetrics.glyphGap) {
            IconArt(face: IconFace(symbol: "square.grid.2x2.fill", tint: .indigo), size: SettingsMetrics.glyphSize)
                .accessibilityHidden(true)
            ConnectForm(style: .glass)
        }
        .padding(SettingsMetrics.formPadding)
        .frame(maxWidth: SettingsMetrics.formWidth)
        // The form keeps clear of the keyboard and rides up with it; the
        // wallpaper behind stays where it is.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.standard, value: isKeyboardUp)
        .background { Wallpaper() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in isKeyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in isKeyboardUp = false }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @State private var isKeyboardUp = false
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
                .frame(maxWidth: .infinity, minHeight: SettingsMetrics.fieldHeight - 14)
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
            do {
                // A different site is a different library: start it clean.
                if library.isSignedIn, siteURL != Account.site { await library.signOut() }
                try await library.signIn(site: siteURL, token: token.trimmingCharacters(in: .whitespaces))
                onConnected()
            } catch {
                failure = error as? API.Failure ?? .offline
                shakes += 1
                focus = .token
            }
        }
    }
}
