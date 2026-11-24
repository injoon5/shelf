// Name: Sign Up
// Icon: person.crop.circle.badge.plus
// Tint: blue
// Covers: Focus & Keyboard, Environment, Text

import SwiftUI

enum Field: Hashable {
    case name, email, password
}

@Observable
final class Draft {
    var name = ""
    var email = ""
    var password = ""
    var saves = 0
}

extension EnvironmentValues {
    @Entry var accent: Color = .blue
}

struct Filled: PreferenceKey {
    static var defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

struct FieldRow: View {
    let title: String
    @Binding var text: String
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(accent)
                .textCase(.uppercase)
                .fontWidth(typeSize >= .accessibility1 ? .standard : .condensed)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .preference(key: Filled.self, value: text.isEmpty ? 0 : 1)
    }
}

struct ContentView: View {
    @State private var draft = Draft()
    @FocusState private var field: Field?
    @FocusState private var bioFocused: Bool
    @State private var bio = ""
    @State private var filled = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    FieldRow(title: "Name", text: $draft.name)
                        .focused($field, equals: .name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { field = .email }
                    FieldRow(title: "Email", text: $draft.email)
                        .focused($field, equals: .email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .onSubmit { field = .password }
                    SecureField("Password", text: $draft.password)
                        .focused($field, equals: .password)
                        .textContentType(.newPassword)
                        .submitLabel(.done)
                        .onSubmit { field = nil; bioFocused = true }
                }
                Section("About") {
                    TextEditor(text: $bio)
                        .frame(minHeight: 80)
                        .focused($bioFocused)
                    Text("\(filled) of 2 fields filled")
                        .contentTransition(.numericText(value: Double(filled)))
                        .monospacedDigit()
                }
                Section("Now") {
                    LabeledContent("Scene", value: "\(scenePhase)")
                    LabeledContent("Appearance", value: colorScheme == .dark ? "Dark" : "Light")
                    LabeledContent("Width", value: sizeClass == .regular ? "Regular" : "Compact")
                    LabeledContent("Saved", value: "\(draft.saves) times")
                    Button("Terms of Service") { openURL(URL(string: "https://ij5.dev")!) }
                }
                Section {
                    Button("Next field") {
                        switch field {
                        case .name: field = .email
                        case .email: field = .password
                        default: field = .name
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Done") { field = nil; bioFocused = false }
                }
            }
            .environment(\.accent, colorScheme == .dark ? .mint : .indigo)
            .environment(draft)
            .onPreferenceChange(Filled.self) { value in filled = value }
            .scrollDismissesKeyboard(.interactively)
            .defaultFocus($field, .name)
            .navigationTitle("Sign Up")
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { draft.saves += 1 }
            }
        }
    }
}
