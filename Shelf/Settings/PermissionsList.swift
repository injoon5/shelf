import SwiftUI
import UIKit

/// Settings › Permissions (plan §4.0): each capability, and the apps that
/// have asked for it, each with a switch. Off is the "denied" answer the API
/// gives the app; on lets it ask iOS again if it has to. When iOS has refused
/// Shelf itself, the capability says so, its switches are off and
/// disabled, and a button opens Shelf's page in iOS Settings.
struct PermissionsList: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase

    private var gate: PermissionGate { library.permissions }

    var body: some View {
        List {
            ForEach(Capability.allCases) { capability in
                section(capability)
            }
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
        // Back from iOS Settings, iOS's answers may have changed.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { gate.systemMayHaveChanged() }
        }
    }

    @ViewBuilder
    private func section(_ capability: Capability) -> some View {
        let system = gate.systemStatus(capability)
        let apps = gate.ledger.apps(for: capability)
        Section {
            if system.isRefused {
                VStack(alignment: .leading, spacing: PermissionMetrics.textSpacing) {
                    Text(capability.systemDenied)
                        .font(.subheadline)
                    if system == .restricted {
                        Text("It’s restricted on this iPhone, by Screen Time or a profile.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if system == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            if apps.isEmpty {
                Text("No apps have asked.")
                    .foregroundStyle(.secondary)
            }
            ForEach(apps, id: \.slug) { row in
                Toggle(isOn: Binding(
                    get: { !system.isRefused && row.answer == .allowed },
                    set: { gate.setAllowed($0, capability, for: row.slug, name: row.name) })) {
                    Label {
                        Text(library.app(row.slug)?.meta.name ?? row.name)
                    } icon: {
                        IconImage(face: face(for: row.slug), size: PermissionMetrics.rowIconSize)
                    }
                }
                .disabled(system.isRefused)
            }
        } header: {
            Label(capability.title, systemImage: capability.symbol)
        }
    }

    /// The app's own icon, or the generic one for an app the library
    /// doesn't have (yet).
    private func face(for slug: String) -> IconFace {
        library.app(slug).map { IconFace($0.meta) } ?? IconFace(AppMeta(slug: slug, name: "", tint: .gray))
    }
}
