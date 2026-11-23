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
                }

                Section("Icons") {
                    IconAppearancePicker(appearance: $settings.iconAppearance, faces: previewFaces)
                }

                Section {
                    NavigationLink("App Data") {
                        AppDataList()
                    }
                    NavigationLink("Permissions") {
                        PermissionsList()
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

extension SettingsView {
    /// The icons the appearance picker shows: the dock's, as they are, or
    /// the first apps when the dock is empty.
    private var previewFaces: [IconFace] {
        let dock = library.layout.dock.compactMap(library.item)
        let items = dock.isEmpty ? Array(library.items.prefix(SettingsMetrics.appearanceIconCount)) : dock
        return items.prefix(SettingsMetrics.appearanceIconCount).map(\.face)
    }
}

/// Icon Appearance: a row of live icons over Automatic, Light and Dark.
/// The icons are the Home Screen's own (`IconImage`) and read the same
/// tone the window holds, so they change with the picker as every icon does.
private struct IconAppearancePicker: View {
    @Binding var appearance: IconAppearance
    var faces: [IconFace]

    var body: some View {
        VStack(spacing: SettingsMetrics.appearanceSpacing) {
            HStack(spacing: SettingsMetrics.appearanceIconGap) {
                ForEach(Array(faces.enumerated()), id: \.offset) { _, face in
                    IconImage(face: face, size: SettingsMetrics.appearanceIconSize)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            Picker("Icon Appearance", selection: $appearance) {
                ForEach(IconAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, SettingsMetrics.appearancePadding)
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

/// What one app keeps on the phone: its `DB` store (synced) and its files
/// (this phone only).
struct AppStorageUse: Equatable, Sendable {
    var data = 0
    var files = 0
    var total: Int { data + files }

    /// Every app's, for Settings › App Data.
    @MainActor static func measure(_ library: LibraryStore) async -> [String: AppStorageUse] {
        var use: [String: AppStorageUse] = [:]
        for (slug, bytes) in await library.data.usage() { use[slug, default: .init()].data = bytes }
        let files = library.files
        let slugs = library.apps.map(\.slug)
        let sizes = await Task.detached { slugs.map { ($0, files.usage(of: $0)) } }.value
        for (slug, bytes) in sizes where bytes > 0 { use[slug, default: .init()].files = bytes }
        return use
    }
}

/// Storage used by each app, its data and its files, with Delete Data per app.
private struct AppDataList: View {
    @Environment(LibraryStore.self) private var library
    @State private var usage: [String: AppStorageUse]?
    @State private var deleting: CachedApp?

    private var rows: [(app: CachedApp, use: AppStorageUse)] {
        guard let usage else { return [] }
        return library.apps
            .compactMap { app in usage[app.slug].map { (app, $0) } }
            .filter { $0.use.total > 0 }
            .sorted { $0.use.total > $1.use.total }
    }

    var body: some View {
        List {
            ForEach(rows, id: \.app.id) { row in
                LabeledContent {
                    Text(Int64(row.use.total), format: .byteCount(style: .file))
                } label: {
                    Label {
                        Text(row.app.meta.name)
                        Text(Self.breakdown(row.use))
                    } icon: {
                        Image(systemName: Symbol.resolve(row.app.meta.icon))
                    }
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
        .task { usage = await AppStorageUse.measure(library) }
        .confirmationDialog(deleting.map { "Delete \($0.meta.name)’s Data" } ?? "", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Data", role: .destructive) {
                guard let app = deleting else { return }
                Task {
                    // The synced data everywhere, and the files on this phone.
                    await library.data.deleteAll(for: app.slug)
                    let files = library.files
                    await Task.detached { files.remove(app.slug) }.value
                    withAnimation(Motion.quick) { usage?[app.slug] = AppStorageUse() }
                }
            }
        } message: {
            Text("Its synced data, on every device, and its files on this iPhone.")
        }
    }

    /// "Data 12 KB · Files 3 MB", leaving out what's empty.
    static func breakdown(_ use: AppStorageUse) -> String {
        var parts: [String] = []
        if use.data > 0 { parts.append("Data " + Int64(use.data).formatted(.byteCount(style: .file))) }
        if use.files > 0 { parts.append("Files " + Int64(use.files).formatted(.byteCount(style: .file))) }
        return parts.joined(separator: " · ")
    }
}
