import PhotosUI
import SwiftUI

/// Settings, as a sheet from its icon, which sits in the layout like any
/// app's (`Layout.settings`). It keeps the system's own
/// sheet glass: no custom background.
struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ShelfSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var picked: PhotosPickerItem?
    @State private var confirmsSignOut = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Site", value: Account.site.host() ?? Account.site.absoluteString)
                    NavigationLink {
                        ChangeToken()
                    } label: {
                        LabeledContent("Token") {
                            if library.tokenRejected {
                                Text("Expired").foregroundStyle(.red)
                            } else {
                                Text(verbatim: "••••••••")
                            }
                        }
                    }
                }

                Section {
                    Button {
                        Task { await library.sync() }
                    } label: {
                        LabeledContent {
                            if library.isSyncing {
                                ProgressView()
                            } else if let last = library.lastSynced {
                                Text(last, format: .relative(presentation: .named))
                            }
                        } label: {
                            Text("Sync Now").foregroundStyle(.tint)
                        }
                    }
                    .disabled(library.isSyncing)
                }

                Section {
                    Picker("Wallpaper", selection: $settings.wallpaper) {
                        Text("Photo").tag(WallpaperChoice.photo)
                        Text("Gradient").tag(WallpaperChoice.gradient)
                        if settings.customWallpaper != nil {
                            Text("Custom").tag(WallpaperChoice.custom)
                        }
                    }
                    PhotosPicker("Choose Photo", selection: $picked, matching: .images)
                    Picker("Icon Style", selection: $settings.iconStyle) {
                        ForEach(IconStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                }

                Section {
                    NavigationLink("App Data") {
                        AppDataList()
                    }
                    Button("Reset Layout") {
                        withAnimation(Motion.reorder) { library.resetLayout() }
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        confirmsSignOut = true
                    }
                    .confirmationDialog("Sign Out", isPresented: $confirmsSignOut) {
                        Button("Sign Out", role: .destructive) {
                            dismiss()
                            Task { await library.signOut() }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .animation(Motion.quick, value: settings.iconStyle)
        }
        .presentationDetents([.medium, .large])
        .dynamicTypeSize(...ShelfMetrics.textSizeCap)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    settings.setCustomWallpaper(data)
                }
                picked = nil
            }
        }
    }
}

private struct ChangeToken: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            ConnectForm(style: .plain) { dismiss() }
                .padding(SettingsMetrics.formPadding)
        }
        .navigationTitle("Token")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Storage used by each app, with Delete Data per app.
private struct AppDataList: View {
    @Environment(LibraryStore.self) private var library
    @State private var usage: [String: Int]?
    @State private var deleting: CachedApp?

    private var rows: [(app: CachedApp, bytes: Int)] {
        guard let usage else { return [] }
        return library.apps
            .compactMap { app in usage[app.slug].map { (app, $0) } }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
    }

    var body: some View {
        List {
            ForEach(rows, id: \.app.id) { row in
                LabeledContent {
                    Text(Int64(row.bytes), format: .byteCount(style: .file))
                } label: {
                    Label(row.app.meta.name, systemImage: Symbol.resolve(row.app.meta.icon))
                }
                .swipeActions {
                    Button("Delete Data", role: .destructive) { deleting = row.app }
                }
                .contextMenu {
                    Button("Delete Data", systemImage: "trash", role: .destructive) { deleting = row.app }
                }
            }
        }
        .overlay {
            if usage != nil, rows.isEmpty {
                ContentUnavailableView("No App Data", systemImage: "externaldrive")
            }
        }
        .navigationTitle("App Data")
        .navigationBarTitleDisplayMode(.inline)
        .task { usage = await library.data.usage() }
        .confirmationDialog(deleting.map { "Delete \($0.meta.name)’s Data" } ?? "", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Data", role: .destructive) {
                guard let app = deleting else { return }
                Task {
                    await library.data.deleteAll(for: app.slug)
                    withAnimation(Motion.quick) { usage?[app.slug] = 0 }
                }
            }
        }
    }
}
